import 'package:car_meet/features/events/application/live_activity.dart';
import 'package:car_meet/features/events/domain/event.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 10, 20);

Event _event(
  String id, {
  required Duration startsIn,
  Duration? length,
  EventType type = EventType.meet,
  bool cancelled = false,
  bool instant = false,
  String? clubTier,
}) {
  final starts = _now.add(startsIn);
  return Event(
    id: id,
    organizerId: 'host',
    title: 'Meet $id',
    type: type,
    startsAt: starts,
    endsAt: length == null ? null : starts.add(length),
    venueName: 'Venue $id',
    lat: 3.1,
    lng: 101.6,
    status: cancelled ? EventStatus.cancelled : EventStatus.active,
    attendeeCount: 3,
    createdAt: _now.subtract(const Duration(days: 3)),
    isInstant: instant,
    clubTier: clubTier,
  );
}

/// Records what the service asked the phone to do.
class _FakeChannel extends LiveActivityChannel {
  _FakeChannel({this.isSupported = true, Set<String>? running}) : running = running ?? {};
  final bool isSupported;
  final Set<String> running;
  final calls = <String>[];

  @override
  Future<bool> supported() async => isSupported;
  @override
  Future<Set<String>> active() async => {...running};
  @override
  Future<bool> start(Event e) async {
    calls.add('start ${e.id}');
    running.add(e.id);
    return true;
  }

  @override
  Future<void> end(String eventId) async {
    calls.add('end $eventId');
    running.remove(eventId);
  }

  @override
  Future<void> endAll() async {
    calls.add('endAll');
    running.clear();
  }
}

LiveActivityService _service(_FakeChannel ch, List<Event> mine, {bool enabled = true, bool ios = true, List<bool>? fetches}) =>
    LiveActivityService(
      enabled: () => enabled,
      loadMine: ({bool fresh = false}) async {
        fetches?.add(fresh);
        return mine;
      },
      channel: ch,
      platformSupported: ios,
      clock: () => _now,
    );

void main() {
  group('windows', () {
    test('ends at the meet end, else 3 h after the start', () {
      expect(liveActivityEndsAt(_event('a', startsIn: Duration.zero, length: const Duration(hours: 5))), _now.add(const Duration(hours: 5)));
      expect(liveActivityEndsAt(_event('a', startsIn: Duration.zero)), _now.add(const Duration(hours: 3)));
      // An end before the start is ignored.
      expect(liveActivityEndsAt(_event('a', startsIn: Duration.zero, length: const Duration(hours: -1))), _now.add(const Duration(hours: 3)));
    });

    test('opens 2 h before the start', () {
      expect(liveActivityWindowOpen(_event('a', startsIn: const Duration(hours: 2, minutes: 1)), _now), isFalse);
      expect(liveActivityWindowOpen(_event('a', startsIn: const Duration(hours: 2)), _now), isTrue);
      expect(liveActivityWindowOpen(_event('a', startsIn: const Duration(minutes: 5)), _now), isTrue);
    });

    test('stays open during the meet, closes at the end', () {
      expect(liveActivityWindowOpen(_event('a', startsIn: const Duration(hours: -2)), _now), isTrue);
      expect(liveActivityWindowOpen(_event('a', startsIn: const Duration(hours: -3)), _now), isFalse);
      expect(liveActivityWindowOpen(_event('a', startsIn: const Duration(hours: -1), length: const Duration(minutes: 59)), _now), isFalse);
    });

    test('never for a cancelled meet', () {
      expect(liveActivityWindowOpen(_event('a', startsIn: const Duration(minutes: 30), cancelled: true), _now), isFalse);
      expect(liveActivityAlive(_event('a', startsIn: const Duration(minutes: 30), cancelled: true), _now), isFalse);
    });

    test('type mark: TT for instant meets, Official for official clubs', () {
      expect(liveActivityType(_event('a', startsIn: Duration.zero, type: EventType.convoy)), 'convoy');
      expect(liveActivityType(_event('a', startsIn: Duration.zero, instant: true)), 'tt');
      expect(liveActivityType(_event('a', startsIn: Duration.zero, clubTier: 'official')), 'official');
    });
  });

  group('planLiveActivities', () {
    test('starts the soonest meet inside its window, only one', () {
      final plan = planLiveActivities(
        enabled: true,
        running: {},
        now: _now,
        mine: [
          _event('later', startsIn: const Duration(hours: 1, minutes: 30)),
          _event('soon', startsIn: const Duration(minutes: 20)),
          _event('tomorrow', startsIn: const Duration(days: 1)),
        ],
      );
      expect(plan.start.map((e) => e.id), ['soon']);
      expect(plan.end, isEmpty);
    });

    test('nothing in the window: nothing to do', () {
      final plan = planLiveActivities(enabled: true, running: {}, now: _now, mine: [_event('tomorrow', startsIn: const Duration(days: 1))]);
      expect(plan.isEmpty, isTrue);
    });

    test('keeps (refreshes) a running one that is still on, starts nothing else', () {
      final plan = planLiveActivities(
        enabled: true,
        running: {'a'},
        now: _now,
        mine: [_event('a', startsIn: const Duration(hours: 2, minutes: 40)), _event('b', startsIn: const Duration(minutes: 10))],
      );
      expect(plan.start.map((e) => e.id), ['a']);
      expect(plan.end, isEmpty);
    });

    test('ends stale ones: over, cancelled, left; then starts the next', () {
      final plan = planLiveActivities(
        enabled: true,
        running: {'over', 'cancelled', 'left'},
        now: _now,
        mine: [
          _event('over', startsIn: const Duration(hours: -4)),
          _event('cancelled', startsIn: const Duration(minutes: 30), cancelled: true),
          _event('next', startsIn: const Duration(hours: 1)),
        ],
      );
      expect(plan.end, {'over', 'cancelled', 'left'});
      expect(plan.start.map((e) => e.id), ['next']);
    });

    test('switch off: end everything, start nothing', () {
      final plan = planLiveActivities(enabled: false, running: {'a'}, now: _now, mine: [_event('a', startsIn: const Duration(minutes: 5))]);
      expect(plan.end, {'a'});
      expect(plan.start, isEmpty);
    });
  });

  group('LiveActivityService', () {
    test('sync starts the meet that is due and ends the finished one', () async {
      final ch = _FakeChannel(running: {'old'});
      await _service(ch, [_event('old', startsIn: const Duration(hours: -5)), _event('new', startsIn: const Duration(minutes: 45))]).sync();
      expect(ch.calls, ['end old', 'start new']);
    });

    test('sync with the switch off ends what runs and skips the fetch', () async {
      final ch = _FakeChannel(running: {'a'});
      final fetches = <bool>[];
      await _service(ch, [_event('a', startsIn: const Duration(minutes: 5))], enabled: false, fetches: fetches).sync();
      expect(ch.calls, ['end a']);
      expect(fetches, isEmpty);

      final idle = _FakeChannel();
      await _service(idle, [_event('a', startsIn: const Duration(minutes: 5))], enabled: false, fetches: fetches).sync();
      expect(idle.calls, isEmpty);
      expect(fetches, isEmpty);
    });

    test('no-op off iPhone and when the phone does not support it', () async {
      final android = _FakeChannel(running: {'x'});
      final s = _service(android, [_event('a', startsIn: const Duration(minutes: 5))], ios: false);
      await s.sync();
      await s.joined('a');
      await s.onMyWay(_event('a', startsIn: const Duration(minutes: 5)));
      await s.end('x');
      await s.endAll();
      expect(android.calls, isEmpty);

      final old = _FakeChannel(isSupported: false);
      final s2 = _service(old, [_event('a', startsIn: const Duration(minutes: 5))]);
      await s2.sync();
      await s2.joined('a');
      expect(old.calls, isEmpty);
    });

    test('joined: starts only inside the 2 h window, replacing another one', () async {
      final ch = _FakeChannel(running: {'other'});
      final mine = [_event('other', startsIn: const Duration(hours: 1)), _event('due', startsIn: const Duration(minutes: 30)), _event('far', startsIn: const Duration(hours: 5))];
      final fetches = <bool>[];
      final s = _service(ch, mine, fetches: fetches);
      await s.joined('far');
      expect(ch.calls, isEmpty);
      await s.joined('due');
      expect(ch.calls, ['end other', 'start due']);
      expect(fetches, everyElement(isTrue)); // a join always refetches
    });

    test('joined with the switch off does nothing', () async {
      final ch = _FakeChannel();
      await _service(ch, [_event('due', startsIn: const Duration(minutes: 30))], enabled: false).joined('due');
      expect(ch.calls, isEmpty);
    });

    test('on my way: starts even 3 h early, never after the end', () async {
      final ch = _FakeChannel();
      final s = _service(ch, const []);
      await s.onMyWay(_event('early', startsIn: const Duration(hours: 3)));
      expect(ch.calls, ['start early']);
      await s.onMyWay(_event('done', startsIn: const Duration(hours: -4)));
      expect(ch.calls, ['start early']);
    });

    test('an on-my-way activity survives the next sync', () async {
      final early = _event('early', startsIn: const Duration(hours: 2, minutes: 50));
      final ch = _FakeChannel();
      final s = _service(ch, [early]);
      await s.onMyWay(early);
      await s.sync();
      expect(ch.calls, ['start early', 'start early']); // the second one refreshes it
      expect(ch.running, {'early'});
    });

    test('leave ends it; endAll clears everything', () async {
      final ch = _FakeChannel(running: {'a', 'b'});
      final s = _service(ch, const []);
      await s.end('a');
      expect(ch.running, {'b'});
      await s.endAll();
      expect(ch.running, isEmpty);
    });

    test('a failing phone call never throws to the caller', () async {
      final s = LiveActivityService(
        enabled: () => true,
        loadMine: ({bool fresh = false}) async => throw StateError('offline'),
        channel: _FakeChannel(),
        platformSupported: true,
        clock: () => _now,
      );
      await s.sync();
      await s.joined('a');
    });
  });
}
