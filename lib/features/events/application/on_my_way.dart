import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env.dart';
import '../../../core/geo/latlng.dart';
import '../../../core/location/live_position.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/geo.dart';
import '../../map/application/map_providers.dart';
import '../../social/application/chat_providers.dart';
import '../domain/event.dart';
import 'live_activity.dart';

// "I'm on my way": a member who joined a meet (or its host) posts their
// driving ETA in the meet chat. One Mapbox Directions request; a straight-line
// guess when that fails.

/// A drive to the meet. [estimated]: a straight-line guess (no route), so the
/// numbers are rougher.
class TripEstimate {
  const TripEstimate({required this.duration, required this.km, this.estimated = false});
  final Duration duration;
  final double km;
  final bool estimated;
}

/// Average speed for the straight-line fallback: Klang Valley traffic, lights
/// and the road being longer than the crow flies, all in one number.
const kFallbackKmh = 35.0;

/// Shown from this long before the start until the meet ends.
const kOnMyWayLead = Duration(hours: 3);

/// One post per meet per this long.
const kOnMyWayGap = Duration(minutes: 10);

/// No route from Mapbox: straight-line distance at [kFallbackKmh].
TripEstimate straightLineEstimate(LatLng from, LatLng to) {
  final km = distanceKm(from, to);
  return TripEstimate(duration: Duration(seconds: (km / kFallbackKmh * 3600).round()), km: km, estimated: true);
}

/// "about 1 min", "about 8 min", "about 25 min", "about 1 h 10 min",
/// "about 2 h". Rounded to 5 minutes from 15 minutes up.
String formatEta(Duration d) {
  var m = (d.inSeconds / 60).round();
  if (m < 1) m = 1;
  if (m >= 15) m = (m / 5).round() * 5;
  if (m < 60) return 'about $m min';
  final h = m ~/ 60, rest = m % 60;
  return rest == 0 ? 'about $h h' : 'about $h h $rest min';
}

/// The chat message, e.g. "On my way · about 25 min (18 km)". Within 200 m
/// it's "On my way · almost there".
String onMyWayText(TripEstimate e) => e.km < 0.2 ? 'On my way · almost there' : 'On my way · ${formatEta(e.duration)} (${formatDistance(e.km)})';

/// Whether the button shows: from [kOnMyWayLead] before [startsAt] until [closesAt].
bool onMyWayWindowOpen({required DateTime startsAt, required DateTime closesAt, required DateTime now}) =>
    !now.isBefore(startsAt.subtract(kOnMyWayLead)) && now.isBefore(closesAt);

/// The first route of a Mapbox Directions response, or null.
TripEstimate? parseMapboxRoute(String body) {
  try {
    final j = jsonDecode(body);
    if (j is! Map || j['code'] != 'Ok') return null;
    final routes = j['routes'];
    if (routes is! List || routes.isEmpty || routes.first is! Map) return null;
    final r = routes.first as Map;
    final seconds = (r['duration'] as num?)?.toDouble();
    final metres = (r['distance'] as num?)?.toDouble();
    if (seconds == null || metres == null || seconds.isNaN || metres.isNaN) return null;
    return TripEstimate(duration: Duration(seconds: seconds.round()), km: metres / 1000);
  } catch (_) {
    return null;
  }
}

/// Driving time with live traffic (Mapbox Directions, `driving-traffic`),
/// one HTTPS request with the public token. Null on any failure.
Future<TripEstimate?> mapboxDrivingEstimate(LatLng from, LatLng to, {Duration timeout = const Duration(seconds: 8)}) async {
  const token = Env.mapboxPublicToken;
  if (token.isEmpty) return null;
  final uri = Uri.https(
    'api.mapbox.com',
    '/directions/v5/mapbox/driving-traffic/${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
    {'alternatives': 'false', 'overview': 'false', 'steps': 'false', 'access_token': token},
  );
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(uri).timeout(timeout);
    final res = await req.close().timeout(timeout);
    final body = await res.transform(utf8.decoder).join().timeout(timeout);
    if (res.statusCode != 200) return null;
    return parseMapboxRoute(body);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// When each meet last got an "On my way" from me, this session.
class OnMyWayThrottle {
  final _last = <String, DateTime>{};

  /// How long until I may post again for [eventId]; null when I may now.
  Duration? waitFor(String eventId, DateTime now) {
    final t = _last[eventId];
    if (t == null) return null;
    final left = kOnMyWayGap - now.difference(t);
    return left > Duration.zero ? left : null;
  }

  void mark(String eventId, DateTime now) => _last[eventId] = now;
  void clear(String eventId) => _last.remove(eventId);
}

final onMyWayThrottleProvider = Provider<OnMyWayThrottle>((ref) => OnMyWayThrottle());

/// What was posted, for Undo.
class OnMyWayPost {
  const OnMyWayPost({required this.eventId, required this.conversationId, required this.messageId, required this.text, required this.estimate});
  final String eventId;
  final String conversationId;
  final String? messageId;
  final String text;
  final TripEstimate estimate;
}

class OnMyWayActions {
  OnMyWayActions(this._ref);
  final Ref _ref;

  /// Where I am now: a fresh live fix, else a new one, else the cached one.
  Future<LatLng?> _here() async {
    final live = _ref.read(livePositionProvider);
    if (live != null && live.age < const Duration(minutes: 2)) return live.latLng;
    final fresh = await _ref.read(livePositionProvider.notifier).refresh();
    if (fresh != null) return fresh;
    try {
      return await _ref.read(userLocationProvider.future);
    } catch (_) {
      return null;
    }
  }

  /// Works out my ETA to [event] and posts it in the meet chat as me.
  Future<OnMyWayPost> post(Event event) async {
    final throttle = _ref.read(onMyWayThrottleProvider);
    final wait = throttle.waitFor(event.id, DateTime.now());
    if (wait != null) {
      final mins = (wait.inSeconds / 60).ceil();
      throw AppException('You just told the meet. You can post again in $mins min.');
    }
    final me = _ref.read(currentUserIdProvider);
    if (me == null) throw const AppException('You\'re signed out. Sign in again.');
    final here = await _here();
    if (here == null) throw const AppException('Turn on location so we can work out your ETA.');

    final estimate = await mapboxDrivingEstimate(here, event.latLng) ?? straightLineEstimate(here, event.latLng);
    final text = onMyWayText(estimate);
    final chat = _ref.read(chatActionsProvider);
    final conv = await chat.openMeetChat(event.id);
    final before = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    await chat.send(conv, text);
    throttle.mark(event.id, DateTime.now());
    _ref.invalidate(inboxProvider);
    unawaited(_ref.read(liveActivityServiceProvider).onMyWay(event));

    // The send path doesn't return the row; find it for Undo.
    String? id;
    try {
      final row = await _ref
          .read(supabaseProvider)
          .from('messages')
          .select('id')
          .eq('conversation_id', conv)
          .eq('sender_id', me)
          .eq('body', text)
          .gte('created_at', before.toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      id = row?['id'] as String?;
    } catch (_) {}
    return OnMyWayPost(eventId: event.id, conversationId: conv, messageId: id, text: text, estimate: estimate);
  }

  /// Takes the message back out of the meet chat (RLS lets a sender delete
  /// their own message; members may already have seen it or its push).
  Future<void> undo(OnMyWayPost p) async {
    if (p.messageId == null) throw const AppException('Couldn\'t take it back. Check your connection and try again.');
    final gone = await _ref.read(supabaseProvider).from('messages').delete().eq('id', p.messageId!).select('id');
    if (gone.isEmpty) throw const AppException('Couldn\'t take it back. Check your connection and try again.');
    _ref.read(onMyWayThrottleProvider).clear(p.eventId);
    _ref.invalidate(messagesProvider(p.conversationId));
    _ref.invalidate(inboxProvider);
  }
}

final onMyWayActionsProvider = Provider<OnMyWayActions>((ref) => OnMyWayActions(ref));
