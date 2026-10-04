import 'dart:async';

import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/friends/domain/friend.dart';
import 'package:car_meet/features/friends/domain/pin_refresh.dart';
import 'package:car_meet/features/friends/domain/presence.dart';
import 'package:flutter_test/flutter_test.dart';

/// The presence heartbeat and how friends' pins follow it, on a fake clock:
/// a still phone stays live with fewer writes, and friends' pings move pins
/// from the payload instead of refetching visible_pins each time.

final _t0 = DateTime(2026, 10, 5, 21);

// ------------------------------------------------------------ fake clock ---

class _FakeTimer implements Timer {
  _FakeTimer(this.at, this.run);
  final DateTime at;
  final void Function() run;
  bool _active = true;
  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}

class _Clock {
  DateTime now = _t0;
  final _timers = <_FakeTimer>[];

  Timer timer(Duration after, void Function() run) {
    final t = _FakeTimer(now.add(after), run);
    _timers.add(t);
    return t;
  }

  /// Moves time on by [d], firing due timers in order and letting what they
  /// start finish.
  Future<void> advance(Duration d) async {
    final end = now.add(d);
    while (true) {
      final due = _timers.where((t) => t.isActive && !t.at.isAfter(end)).toList()..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      final t = due.first;
      now = t.at;
      t.cancel();
      t.run();
      await Future<void>.delayed(Duration.zero);
    }
    now = end;
    await Future<void>.delayed(Duration.zero);
  }
}

// ------------------------------------------------------------------ pins ---

FriendPin _pin(String id, {required DateTime at, double lat = 3.1, double lng = 101.6, String? placeId, String? eventId, bool nearby = false}) => FriendPin(
      user: Profile(id: id, username: id, createdAt: _t0),
      lat: lat,
      lng: lng,
      updatedAt: at,
      placeId: placeId,
      placeName: placeId == null ? null : 'Wheels Cafe',
      eventId: eventId,
      viaNearby: nearby,
      carMake: 'Honda',
      carModel: 'Civic',
    );

PinChange _ping(String id, {required DateTime at, double lat = 3.1, double lng = 101.6, String? placeId, String? eventId}) =>
    PinChange(userId: id, lat: lat, lng: lng, updatedAt: at, placeId: placeId, eventId: eventId);

/// About 55 m north.
const _north55m = 0.0005;

void main() {
  group('heartbeat', () {
    test('nothing before the first ping (the first fix sends it)', () {
      expect(heartbeatDue(now: _t0), isFalse);
    });

    test('only once the last good ping is 40 s old', () {
      expect(heartbeatDue(now: _t0.add(const Duration(seconds: 39)), lastOk: _t0, lastTry: _t0), isFalse);
      expect(heartbeatDue(now: _t0.add(const Duration(seconds: 40)), lastOk: _t0, lastTry: _t0), isTrue);
    });

    test('a failed ping is retried 10 s later, not every tick', () {
      final failed = _t0.add(const Duration(seconds: 40));
      expect(heartbeatDue(now: failed.add(const Duration(seconds: 5)), lastOk: _t0, lastTry: failed), isFalse);
      expect(heartbeatDue(now: failed.add(const Duration(seconds: 10)), lastOk: _t0, lastTry: failed), isTrue);
      // The very first one failed (offline at start).
      expect(heartbeatDue(now: _t0.add(const Duration(seconds: 10)), lastTry: _t0), isTrue);
    });

    test('a ping on its way is not doubled', () {
      final sent = _t0.add(const Duration(seconds: 41));
      expect(heartbeatDue(now: sent.add(const Duration(seconds: 2)), lastOk: _t0, lastTry: sent), isFalse);
    });

    test('a ping, the check tick and one retry all fit inside the live minute', () {
      expect(kPresenceHeartbeat + kHeartbeatCheck + kHeartbeatRetry, lessThan(kLiveWindow));
    });

    test('a still phone checking every 5 s stays live for 2 minutes with 3 writes', () {
      // Writes at 0 s, then on the 5 s ticks once 40 s have passed.
      final writes = <DateTime>[_t0];
      for (var s = 5; s < 120; s += 5) {
        final now = _t0.add(Duration(seconds: s));
        if (heartbeatDue(now: now, lastOk: writes.last, lastTry: writes.last)) writes.add(now);
      }
      expect(writes.length, 3);
      // Live the whole time: never more than a minute between writes.
      for (var s = 0; s < 120; s++) {
        final now = _t0.add(Duration(seconds: s));
        final last = writes.lastWhere((w) => !w.isAfter(now));
        expect(isLiveAt(last, now), isTrue, reason: 'live at $s s');
      }
    });
  });

  group('reading the realtime payload', () {
    test('an update with an offset, a bare time, and Z', () {
      final a = PinChange.fromRecord({'user_id': 'ali', 'lat': 3.1, 'lng': 101.6, 'heading': 90, 'updated_at': '2026-10-05T13:00:05.123456+00:00', 'place_id': 'p1', 'ghost': false})!;
      expect(a.userId, 'ali');
      expect(a.updatedAt, DateTime.utc(2026, 10, 5, 13, 0, 5, 123, 456).toLocal());
      expect(a.heading, 90);
      expect(a.placeId, 'p1');
      expect(a.eventId, isNull);
      expect(PinChange.fromRecord({'user_id': 'ali', 'updated_at': '2026-10-05T13:00:05'})!.updatedAt, DateTime.utc(2026, 10, 5, 13, 0, 5).toLocal());
      expect(PinChange.fromRecord({'user_id': 'ali', 'updated_at': '2026-10-05 13:00:05+00'})!.updatedAt, DateTime.utc(2026, 10, 5, 13, 0, 5).toLocal());
    });

    test('a delete has the key only; no key, no change', () {
      final d = PinChange.fromRecord({'user_id': 'ali'}, deleted: true)!;
      expect(d.deleted, isTrue);
      expect(d.updatedAt, isNull);
      expect(PinChange.fromRecord(const {}), isNull);
    });

    test('ghost by flag or by share mode', () {
      expect(PinChange.fromRecord({'user_id': 'a', 'ghost': true})!.ghost, isTrue);
      expect(PinChange.fromRecord({'user_id': 'a', 'share_mode': 'ghost'})!.ghost, isTrue);
      expect(PinChange.fromRecord({'user_id': 'a', 'share_mode': 'friends'})!.ghost, isFalse);
    });
  });

  group('what a change asks of the pins', () {
    final now = _t0;
    final live = _pin('ali', at: now.subtract(const Duration(seconds: 42)));
    PinStep step(PinChange c, FriendPin? held, {Set<String> blocked = const {}}) => pinStep(c, me: 'me', held: held, blocked: blocked, now: now);

    test('my own ping and blocked people: nothing', () {
      expect(step(_ping('me', at: now), null), PinStep.ignore);
      expect(step(_ping('ali', at: now), live, blocked: {'ali'}), PinStep.ignore);
    });

    test('a heartbeat from a live friend: patch, no fetch', () {
      expect(step(_ping('ali', at: now), live), PinStep.patch);
    });

    test('a move of over 50 m: patch at once, no fetch', () {
      expect(step(_ping('ali', at: now, lat: 3.1 + _north55m), live), PinStep.patch);
    });

    test('last seen and back (live flip): patch at once, then fetch their car and names', () {
      final seen = _pin('ali', at: now.subtract(const Duration(minutes: 30)));
      expect(step(_ping('ali', at: now), seen), PinStep.patchThenFetch);
    });

    test('someone new on my map: fetch', () {
      expect(step(_ping('bob', at: now), null), PinStep.fetch);
    });

    test('a new place or meet: fetch (the name comes from the server)', () {
      expect(step(_ping('ali', at: now, placeId: 'p1'), live), PinStep.fetch);
      expect(step(_ping('ali', at: now, eventId: 'e1'), live), PinStep.fetch);
      final atCafe = _pin('ali', at: now.subtract(const Duration(seconds: 42)), placeId: 'p1');
      expect(step(_ping('ali', at: now, placeId: 'p1'), atCafe), PinStep.patch);
    });

    test('gone or hidden: fetch when shown, nothing when not', () {
      expect(step(const PinChange(userId: 'ali', deleted: true), live), PinStep.fetch);
      expect(step(const PinChange(userId: 'bob', deleted: true), null), PinStep.ignore);
      expect(step(PinChange(userId: 'ali', lat: 3.1, lng: 101.6, updatedAt: now, ghost: true), live), PinStep.fetch);
    });

    test('a payload without a position or time: fetch', () {
      expect(step(const PinChange(userId: 'ali'), live), PinStep.fetch);
    });

    test('a stranger who just became a friend: fetch the real pin', () {
      final stranger = _pin('ali', at: now.subtract(const Duration(seconds: 42)), nearby: true);
      expect(step(_ping('ali', at: now), stranger), PinStep.fetch);
    });

    test('out of order or nothing new: nothing', () {
      expect(step(_ping('ali', at: live.updatedAt.subtract(const Duration(seconds: 5))), live), PinStep.ignore);
      expect(step(_ping('ali', at: live.updatedAt), live), PinStep.ignore);
    });
  });

  group('patching', () {
    test('moves the pin, keeps who they are and their car, newest first', () {
      final pins = [
        _pin('bob', at: _t0.subtract(const Duration(seconds: 10))),
        _pin('ali', at: _t0.subtract(const Duration(minutes: 5)), placeId: 'p1'),
      ];
      final out = patchPins(pins, PinChange(userId: 'ali', lat: 3.2, lng: 101.7, heading: 45, updatedAt: _t0, placeId: 'p1'));
      expect(out.map((p) => p.user.id), ['ali', 'bob']);
      expect(out.first.lat, 3.2);
      expect(out.first.lng, 101.7);
      expect(out.first.heading, 45);
      expect(out.first.updatedAt, _t0);
      expect(out.first.placeName, 'Wheels Cafe');
      expect(out.first.carTitle, 'Honda Civic');
      expect(isLiveAt(out.first.updatedAt, _t0), isTrue);
    });

    test('someone not in the list: unchanged', () {
      final pins = [_pin('bob', at: _t0)];
      expect(identical(patchPins(pins, _ping('ali', at: _t0)), pins), isTrue);
    });
  });

  group('PinRefresher', () {
    late _Clock clock;
    late int fetches;
    Completer<void>? gate;
    late PinRefresher r;

    setUp(() {
      clock = _Clock();
      fetches = 0;
      gate = null;
      r = PinRefresher(
        fetch: () async {
          fetches++;
          final g = gate;
          if (g != null) await g.future;
        },
        clock: () => clock.now,
        timer: clock.timer,
      );
    });

    test('a burst of changes is one fetch, after the settle', () async {
      for (var i = 0; i < 10; i++) {
        r.request();
      }
      await clock.advance(const Duration(milliseconds: 599));
      expect(fetches, 0);
      await clock.advance(const Duration(milliseconds: 1));
      expect(fetches, 1);
    });

    test('at most one fetch per 10 s', () async {
      r.now();
      await clock.advance(const Duration(seconds: 2));
      r.request();
      await clock.advance(const Duration(seconds: 7));
      expect(fetches, 1, reason: '9 s after the first: still waiting');
      await clock.advance(const Duration(seconds: 1));
      expect(fetches, 2, reason: '10 s after the first');
    });

    test('a change every second for a minute: 6 or 7 fetches, not 60', () async {
      for (var s = 0; s < 60; s++) {
        r.request();
        await clock.advance(const Duration(seconds: 1));
      }
      expect(fetches, inInclusiveRange(6, 7));
    });

    test('a change during a fetch fetches once more after it', () async {
      gate = Completer<void>();
      r.now();
      expect(fetches, 1);
      r.request();
      r.request();
      await clock.advance(const Duration(seconds: 30));
      expect(fetches, 1, reason: 'never two at a time');
      gate!.complete();
      gate = null;
      await Future<void>.delayed(Duration.zero); // the fetch finishes
      await clock.advance(const Duration(seconds: 1));
      expect(fetches, 2);
    });

    test('a fetch that never comes back does not hold the others up', () async {
      gate = Completer<void>(); // never completes for this fetch
      final lost = gate!;
      r.now();
      expect(fetches, 1);
      await clock.advance(const Duration(seconds: 19));
      r.request();
      await clock.advance(const Duration(seconds: 5));
      expect(fetches, 1, reason: 'under 20 s it is still waited for');
      gate = null;
      await clock.advance(const Duration(seconds: 1));
      r.request();
      await clock.advance(const Duration(seconds: 1));
      expect(fetches, 2, reason: 'over 20 s: given up on, a new one goes');
      // The lost one finishing late starts nothing more.
      lost.complete();
      await clock.advance(const Duration(seconds: 30));
      expect(fetches, 2);
    });

    test('dispose cancels what is waiting', () async {
      r.request();
      r.dispose();
      await clock.advance(const Duration(seconds: 30));
      expect(fetches, 0);
    });
  });

  // Two minutes on a fake clock: me and five friends, all parked with the
  // app open. Counts my database writes and my visible_pins fetches, the
  // 0.3.52 way and the 0.3.53 way.
  group('two minutes, six phones standing still', () {
    const friends = ['f1', 'f2', 'f3', 'f4', 'f5'];
    // Each phone's first ping (and its 5 s check grid), in seconds.
    const starts = {'me': 0, 'f1': 3, 'f2': 7, 'f3': 11, 'f4': 17, 'f5': 23};
    const window = Duration(minutes: 2);

    /// When each phone writes in [window]: the first fix, then the heartbeat
    /// rule on its 5 s tick.
    Map<String, List<Duration>> writes(bool Function(Duration sinceLast) due) => {
          for (final e in starts.entries)
            e.key: () {
              final out = <Duration>[Duration(seconds: e.value)];
              for (var t = Duration(seconds: e.value) + kHeartbeatCheck; t < window; t += kHeartbeatCheck) {
                if (due(t - out.last)) out.add(t);
              }
              return out;
            }(),
        };

    test('0.3.52: a ping every 30 s and a fetch for every change', () {
      final w = writes((since) => since >= const Duration(seconds: 30));
      // Every write reaches me (my own row too); each one refetched after a
      // 600 ms debounce, merged only when two land within 600 ms.
      final events = [for (final l in w.values) ...l]..sort();
      var fetches = 1; // the first load
      Duration? lastEvent;
      for (final e in events) {
        if (lastEvent == null || e - lastEvent >= kPinFetchSettle) fetches++;
        lastEvent = e;
      }
      fetches += 1; // the one-minute tick (at 60 s)
      expect(w['me']!.length, 4);
      expect(events.length, 24);
      expect(fetches, 26);
    });

    test('0.3.53: a ping every 40 to 45 s, pins patched, fetches from the tick only', () async {
      final w = writes((since) => heartbeatDue(now: _t0.add(since), lastOk: _t0, lastTry: _t0));
      final clock = _Clock();
      var fetches = 0;
      final r = PinRefresher(fetch: () async => fetches++, clock: () => clock.now, timer: clock.timer);
      // The first load: every friend on the map, live from their previous
      // heartbeat 40 s before the first one in the window.
      r.now();
      await clock.advance(Duration.zero);
      var pins = [for (final f in friends) _pin(f, at: _t0.add(Duration(seconds: starts[f]! - 40)))];
      final events = [for (final e in w.entries) for (final t in e.value) (who: e.key, at: t)]..sort((a, b) => a.at.compareTo(b.at));
      var patches = 0;
      var nextTick = const Duration(minutes: 1);
      for (final e in events) {
        while (nextTick <= e.at) {
          await clock.advance(_t0.add(nextTick).difference(clock.now));
          r.request();
          nextTick += const Duration(minutes: 1);
        }
        await clock.advance(_t0.add(e.at).difference(clock.now));
        final c = _ping(e.who, at: _t0.add(e.at));
        final held = pins.where((p) => p.user.id == e.who).firstOrNull;
        switch (pinStep(c, me: 'me', held: held, now: clock.now)) {
          case PinStep.ignore:
            break;
          case PinStep.patch:
            pins = patchPins(pins, c);
            patches++;
          case PinStep.patchThenFetch:
            pins = patchPins(pins, c);
            patches++;
            r.request();
          case PinStep.fetch:
            r.request();
        }
      }
      await clock.advance(_t0.add(window).difference(clock.now));
      expect(w['me']!.length, 3);
      expect(events.length, 18);
      expect(patches, 15, reason: "every friend's heartbeat, straight from the payload");
      expect(fetches, 2, reason: 'the first load and the one-minute tick');
      // Every friend stayed live the whole time on my map.
      for (final p in pins) {
        expect(p.updatedAt.isAfter(_t0.add(window - kLiveWindow)), isTrue, reason: '${p.user.id} live at the end');
      }
    });
  });
}
