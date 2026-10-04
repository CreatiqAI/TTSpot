// How friends' pins follow realtime without a refetch for every ping. Kept
// free of Flutter and Supabase so it can be unit tested with a fake clock.
//
// Every write to user_locations reaches each friend and clubmate who can see
// that row (realtime on the table, filtered by its RLS), and an open app
// writes at least every [kPresenceHeartbeat]. Fetching visible_pins for each
// of those is the expensive part, and almost none of them need it: the
// payload already holds the new position and time. So:
//
//   my own row, someone I blocked      ignore (my position is not a pin)
//   a pin I hold, same place and meet  patch it from the payload, at once:
//                                      a heartbeat, a move of any size, a
//                                      live flip. No fetch.
//   ... and it was "last seen"         patch at once, then fetch: back on
//                                      the map, so their car and names may
//                                      have changed meanwhile
//   someone new, gone, at a new place  fetch (names come from the server)
//   or meet, or a payload I can't read
//
// Fetches go through [PinRefresher]: at most one per [kPinFetchGap], the
// first at once.

import 'dart:async';

import 'friend.dart';
import 'presence.dart';

/// At most one visible_pins fetch per this long, per app.
const kPinFetchGap = Duration(seconds: 10);

/// A burst of changes (a meet ending, ten friends leaving) settles into one
/// fetch after this.
const kPinFetchSettle = Duration(milliseconds: 600);

/// One realtime change to a `user_locations` row, as far as the payload says.
class PinChange {
  const PinChange({
    required this.userId,
    this.deleted = false,
    this.lat,
    this.lng,
    this.heading,
    this.updatedAt,
    this.placeId,
    this.eventId,
    this.ghost = false,
  });

  final String userId;

  /// The row is gone (the payload then has the user id only).
  final bool deleted;
  final double? lat;
  final double? lng;
  final double? heading;
  final DateTime? updatedAt;
  final String? placeId;
  final String? eventId;
  final bool ghost;

  /// From a realtime record: the new row for an insert or update, the old
  /// one (just the key, under RLS) for a delete. Null without a user id.
  static PinChange? fromRecord(Map<String, dynamic> m, {bool deleted = false}) {
    final id = m['user_id'];
    if (id is! String) return null;
    return PinChange(
      userId: id,
      deleted: deleted,
      lat: _num(m['lat']),
      lng: _num(m['lng']),
      heading: _num(m['heading']),
      updatedAt: _time(m['updated_at']),
      placeId: m['place_id'] is String ? m['place_id'] as String : null,
      eventId: m['event_id'] is String ? m['event_id'] as String : null,
      ghost: m['ghost'] == true || m['share_mode'] == 'ghost',
    );
  }

  static double? _num(Object? v) => v is num ? v.toDouble() : null;

  static final _zone = RegExp(r'([zZ]|[+-]\d\d(:?\d\d)?)$');

  /// Realtime sends timestamptz with an offset; read a bare one as UTC.
  static DateTime? _time(Object? v) {
    if (v is! String) return null;
    return DateTime.tryParse(_zone.hasMatch(v) ? v : '${v}Z')?.toLocal();
  }
}

/// What a [PinChange] asks of the pin list.
enum PinStep {
  /// Nothing on my map changes.
  ignore,

  /// Move the pin I hold to the payload's position and time. No fetch.
  patch,

  /// Patch now, then fetch: they were last seen and are back.
  patchThenFetch,

  /// Fetch the list: someone new or gone, or a new place or meet name.
  fetch,
}

/// What to do with [c] given the pin I hold for that person ([held], null
/// when they are not on my map), at [now].
PinStep pinStep(PinChange c, {required String me, required FriendPin? held, Set<String> blocked = const {}, required DateTime now}) {
  if (c.userId == me || blocked.contains(c.userId)) return PinStep.ignore;
  if (held == null) {
    // Gone or hidden and I don't show them anyway: nothing to take off.
    if (c.deleted || c.ghost) return PinStep.ignore;
    return PinStep.fetch;
  }
  if (c.deleted || c.ghost) return PinStep.fetch;
  final at = c.updatedAt;
  final lat = c.lat;
  final lng = c.lng;
  if (at == null || lat == null || lng == null) return PinStep.fetch;
  // A stranger's pin is rounded and faceless; realtime only brings friends
  // and clubmates, so this one just became one. Fetch the real pin.
  if (held.isStranger) return PinStep.fetch;
  if (c.placeId != held.placeId || c.eventId != held.eventId) return PinStep.fetch;
  // Older than what I hold (out of order), or nothing new.
  if (at.isBefore(held.updatedAt)) return PinStep.ignore;
  if (at == held.updatedAt && lat == held.lat && lng == held.lng && c.heading == held.heading) return PinStep.ignore;
  if (presenceAt(held.updatedAt, now) != Presence.live && presenceAt(at, now) == Presence.live) return PinStep.patchThenFetch;
  return PinStep.patch;
}

/// [pins] with [c] applied to its person, who moves to the front (the list
/// is newest first, as visible_pins sends it). Unchanged when they are not
/// in it or the payload lacks a position.
List<FriendPin> patchPins(List<FriendPin> pins, PinChange c) {
  final at = c.updatedAt;
  final lat = c.lat;
  final lng = c.lng;
  if (at == null || lat == null || lng == null) return pins;
  final i = pins.indexWhere((p) => p.user.id == c.userId);
  if (i < 0) return pins;
  final moved = pins[i].movedTo(lat: lat, lng: lng, updatedAt: at, heading: c.heading);
  return [moved, for (var j = 0; j < pins.length; j++) if (j != i) pins[j]];
}

/// Runs [fetch] when asked, coalesced: at most one per [gap], the first one
/// [settle] after the ask, and never two at a time (an ask during a fetch
/// fetches once more after it, since that fetch may have read too early).
/// [clock] and [timer] are swappable for tests.
class PinRefresher {
  PinRefresher({
    required this.fetch,
    DateTime Function()? clock,
    Timer Function(Duration after, void Function() run)? timer,
    this.gap = kPinFetchGap,
    this.settle = kPinFetchSettle,
  })  : _clock = clock ?? DateTime.now,
        _timer = timer ?? Timer.new;

  final Future<void> Function() fetch;
  final Duration gap;
  final Duration settle;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _timer;

  DateTime? _lastStart;
  Timer? _pending;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  /// Fetches started so far.
  int fetches = 0;

  /// How long from [now] until the next fetch may start.
  Duration waitAt(DateTime now) {
    final last = _lastStart;
    if (last == null) return settle;
    final ready = last.add(gap).difference(now);
    return ready > settle ? ready : settle;
  }

  /// Fetch soon. Asks while one is waiting or running fold into it.
  void request() {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    if (_pending != null) return;
    _pending = _timer(waitAt(_clock()), _run);
  }

  /// Fetch now (the first load): no settle, no gap. Folds into a running one.
  void now() {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _pending?.cancel();
    _run();
  }

  Future<void> _run() async {
    _pending = null;
    if (_disposed) return;
    _running = true;
    _lastStart = _clock();
    fetches++;
    try {
      await fetch();
    } catch (_) {
      // [fetch] reports its own errors.
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        request();
      }
    }
  }

  void dispose() {
    _disposed = true;
    _pending?.cancel();
    _pending = null;
  }
}
