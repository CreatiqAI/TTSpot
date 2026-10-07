import 'package:car_meet/features/events/application/live_activity.dart';
import 'package:car_meet/features/events/domain/event.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 10, 20);

Event _event(String id, Duration startsIn) => Event(
      id: id,
      organizerId: 'host',
      title: 'Expo $id',
      type: EventType.meet,
      startsAt: _now.add(startsIn),
      venueName: 'MITEC',
      lat: 3.1,
      lng: 101.6,
      status: EventStatus.active,
      attendeeCount: 3,
      createdAt: _now.subtract(const Duration(days: 3)),
    );

class _Channel extends LiveActivityChannel {
  final starts = <String, String?>{};
  @override
  Future<bool> supported() async => true;
  @override
  Future<Set<String>> active() async => starts.keys.toSet();
  @override
  Future<bool> start(Event e, {String? badge}) async {
    starts[e.id] = badge;
    return true;
  }

  @override
  Future<void> end(String eventId) async => starts.remove(eventId);
  @override
  Future<void> endAll() async => starts.clear();
}

LiveActivityService _service(_Channel ch, List<Event> mine, Future<int?> Function(String) entry, {List<String>? asked}) => LiveActivityService(
      enabled: () => true,
      loadMine: ({bool fresh = false}) async => mine,
      loadEntryNo: (id) {
        asked?.add(id);
        return entry(id);
      },
      channel: ch,
      platformSupported: true,
      clock: () => _now,
    );

void main() {
  test('entry badge is zero-padded to 4', () {
    expect(liveActivityEntryBadge(7), '#0007');
    expect(liveActivityEntryBadge(427), '#0427');
    expect(liveActivityEntryBadge(12345), '#12345');
  });

  test('checked in: the activity carries my entry number', () async {
    final ch = _Channel();
    await _service(ch, [_event('a', const Duration(minutes: -30))], (_) async => 427).sync();
    expect(ch.starts, {'a': '#0427'});
  });

  test('not checked in, or the lookup fails: no badge, still starts', () async {
    final ch = _Channel();
    await _service(ch, [_event('a', const Duration(minutes: 30))], (_) async => null).sync();
    expect(ch.starts, {'a': null});

    final ch2 = _Channel();
    await _service(ch2, [_event('a', const Duration(minutes: 30))], (_) async => throw Exception('offline')).sync();
    expect(ch2.starts, {'a': null});
  });

  test('more than an hour before the start it does not ask', () async {
    final ch = _Channel();
    final asked = <String>[];
    await _service(ch, [_event('a', const Duration(minutes: 90))], (_) async => 1, asked: asked).sync();
    expect(ch.starts, {'a': null});
    expect(asked, isEmpty);
  });
}
