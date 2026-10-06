import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/application/settings_providers.dart';
import '../domain/event.dart';
import 'my_events_provider.dart';

// iPhone Live Activities: a meet I'm going to on the lock screen and in the
// Dynamic Island. "Starts in 1:12:05" from 2 h before the start, then
// "Live" with the time since the start until the meet ends. The timers run
// on the phone (SwiftUI timer text), so there are no pushes and no server
// cost. Native side: ios/Runner/LiveActivityBridge.swift (channel) and
// ios/TTSpotWidgets (the views). A no-op on Android and iOS < 16.1.

/// Starts by itself from this long before the start.
const kLiveActivityLead = Duration(hours: 2);

/// How long it shows after the start when the meet has no end time.
const kLiveActivityDefaultLength = Duration(hours: 3);

/// When the activity goes: the meet's end, else [kLiveActivityDefaultLength]
/// after the start.
DateTime liveActivityEndsAt(Event e) {
  final end = e.endsAt;
  return end != null && end.isAfter(e.startsAt) ? end : e.startsAt.add(kLiveActivityDefaultLength);
}

/// Still worth showing: not cancelled and not over.
bool liveActivityAlive(Event e, DateTime now) => !e.isCancelled && now.isBefore(liveActivityEndsAt(e));

/// May start by itself: from [kLiveActivityLead] before the start until it ends.
bool liveActivityWindowOpen(Event e, DateTime now) =>
    liveActivityAlive(e, now) && !now.isBefore(e.startsAt.subtract(kLiveActivityLead));

/// The type the widget draws: TT for instant meets, Official for official clubs.
String liveActivityType(Event e) {
  if (e.isInstant) return EventType.tt.db;
  if (e.isOfficialClubEvent) return EventType.official.db;
  return e.type.db;
}

/// What [planLiveActivities] decided.
class LiveActivityPlan {
  const LiveActivityPlan({this.start = const [], this.end = const {}});

  /// Start these, or refresh them when already running (title / time edits).
  final List<Event> start;

  /// End these event ids.
  final Set<String> end;

  bool get isEmpty => start.isEmpty && end.isEmpty;
}

/// On app open / resume: keep running activities whose meet is still mine
/// and not over; end the rest (meet over, cancelled, left, or the switch is
/// off). With none left, start the soonest meet of mine inside its window.
/// One at a time, so the lock screen stays clean.
LiveActivityPlan planLiveActivities({
  required bool enabled,
  required List<Event> mine,
  required Set<String> running,
  required DateTime now,
}) {
  if (!enabled) return LiveActivityPlan(end: running);
  final byId = {for (final e in mine) e.id: e};
  final keep = [
    for (final id in running)
      if (byId[id] case final e? when liveActivityAlive(e, now)) e,
  ];
  final end = running.difference({for (final e in keep) e.id});
  if (keep.isNotEmpty) return LiveActivityPlan(start: keep, end: end);
  final open = mine.where((e) => liveActivityWindowOpen(e, now)).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return LiveActivityPlan(start: open.take(1).toList(), end: end);
}

/// The native side. Swapped for a fake in tests.
class LiveActivityChannel {
  const LiveActivityChannel();
  static const _ch = MethodChannel('my.ttspot.app/live_activity');

  Future<bool> supported() async => await _ch.invokeMethod<bool>('supported') ?? false;

  Future<Set<String>> active() async => {...?(await _ch.invokeListMethod<String>('active'))};

  Future<bool> start(Event e) async =>
      await _ch.invokeMethod<bool>('start', {
        'eventId': e.id,
        'title': e.title,
        'venue': e.venueName,
        'startsAt': e.startsAt.millisecondsSinceEpoch,
        'endsAt': liveActivityEndsAt(e).millisecondsSinceEpoch,
        'type': liveActivityType(e),
      }) ??
      false;

  Future<void> end(String eventId) => _ch.invokeMethod<int>('end', {'eventId': eventId});

  Future<void> endAll() => _ch.invokeMethod<int>('endAll');
}

/// Starts and ends the meet Live Activity. Every call is best effort: a
/// failure never reaches the member (the activity is a nice-to-have).
class LiveActivityService {
  LiveActivityService({
    required this.enabled,
    required this.loadMine,
    this.channel = const LiveActivityChannel(),
    bool? platformSupported,
    DateTime Function()? clock,
  })  : _platform = platformSupported ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS),
        _now = clock ?? DateTime.now;

  /// The "Live Activities" switch in Settings.
  final bool Function() enabled;

  /// Meets I host or joined. [fresh]: refetch instead of the cached list.
  final Future<List<Event>> Function({bool fresh}) loadMine;
  final LiveActivityChannel channel;
  final bool _platform;
  final DateTime Function() _now;

  Future<void> _queue = Future.value();

  /// One call at a time (resume + join can land together).
  Future<void> _serial(Future<void> Function() job) {
    final next = _queue.then((_) => job()).catchError((Object e) {
      debugPrint('live activity: $e');
    });
    _queue = next;
    return next;
  }

  Future<bool> _ready() async => _platform && await channel.supported();

  /// App open / resume: end stale ones, refresh or start the right one.
  Future<void> sync({bool fresh = false}) => _serial(() async {
        if (!await _ready()) return;
        final running = await channel.active();
        final on = enabled();
        // Nothing to end and the switch is off: skip the fetch.
        if (!on && running.isEmpty) return;
        final plan = planLiveActivities(enabled: on, mine: on ? await loadMine(fresh: fresh) : const [], running: running, now: _now());
        for (final id in plan.end) {
          await channel.end(id);
        }
        for (final e in plan.start) {
          await channel.start(e);
        }
      });

  /// Just joined [eventId]: show it when it starts within [kLiveActivityLead].
  Future<void> joined(String eventId) => _serial(() async {
        if (!await _ready() || !enabled()) return;
        final mine = await loadMine(fresh: true);
        final e = mine.where((e) => e.id == eventId).firstOrNull;
        if (e == null || !liveActivityWindowOpen(e, _now())) return;
        await _only(e);
      });

  /// "I'm on my way" to [e]: show it now, however early (until the meet ends).
  Future<void> onMyWay(Event e) => _serial(() async {
        if (!await _ready() || !enabled() || !liveActivityAlive(e, _now())) return;
        await _only(e);
      });

  /// Left or cancelled [eventId].
  Future<void> end(String eventId) => _serial(() async {
        if (!_platform) return;
        await channel.end(eventId);
      });

  /// Switch off, sign out, account deleted.
  Future<void> endAll() => _serial(() async {
        if (!_platform) return;
        await channel.endAll();
      });

  /// [e] on its own: others end first.
  Future<void> _only(Event e) async {
    for (final id in await channel.active()) {
      if (id != e.id) await channel.end(id);
    }
    await channel.start(e);
  }
}

/// My meets, refetched at most every 15 min on resume (joins refetch at once).
const _kMineMaxAge = Duration(minutes: 15);

final liveActivityServiceProvider = Provider<LiveActivityService>((ref) {
  DateTime? fetchedAt;
  return LiveActivityService(
    enabled: () => ref.read(settingsProvider).liveActivities,
    loadMine: ({bool fresh = false}) async {
      final now = DateTime.now();
      if (fresh || fetchedAt == null || now.difference(fetchedAt!) > _kMineMaxAge) {
        ref.invalidate(myEventsProvider);
        fetchedAt = now;
      }
      final m = await ref.read(myEventsProvider.future);
      return [...m.upcoming, ...m.past];
    },
  );
});
