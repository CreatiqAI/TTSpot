import 'package:car_meet/core/geo/latlng.dart';
import 'package:car_meet/features/events/application/on_my_way.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatEta', () {
    test('never says 0 min', () {
      expect(formatEta(Duration.zero), 'about 1 min');
      expect(formatEta(const Duration(seconds: 20)), 'about 1 min');
    });

    test('exact minutes under 15', () {
      expect(formatEta(const Duration(minutes: 8, seconds: 20)), 'about 8 min');
      expect(formatEta(const Duration(minutes: 14)), 'about 14 min');
    });

    test('5-minute steps from 15 up', () {
      expect(formatEta(const Duration(minutes: 23)), 'about 25 min');
      expect(formatEta(const Duration(minutes: 27)), 'about 25 min');
      expect(formatEta(const Duration(minutes: 58)), 'about 1 h');
    });

    test('hours', () {
      expect(formatEta(const Duration(minutes: 72)), 'about 1 h 10 min');
      expect(formatEta(const Duration(hours: 2)), 'about 2 h');
    });
  });

  group('straight-line fallback', () {
    const a = LatLng(3.1390, 101.6869); // KL city centre
    const b = LatLng(3.1390, 101.8484); // ~17.9 km due east

    test('35 km/h over the straight-line distance', () {
      final e = straightLineEstimate(a, b);
      expect(e.estimated, isTrue);
      expect(e.km, closeTo(17.9, 0.2));
      // 17.9 km at 35 km/h ≈ 30.7 min
      expect(e.duration.inMinutes, inInclusiveRange(30, 31));
    });

    test('message text', () {
      expect(onMyWayText(straightLineEstimate(a, b)), 'On my way · about 30 min (18 km)');
      expect(onMyWayText(const TripEstimate(duration: Duration(minutes: 25), km: 18.2)), 'On my way · about 25 min (18 km)');
      expect(onMyWayText(const TripEstimate(duration: Duration(minutes: 6), km: 3.24)), 'On my way · about 6 min (3.2 km)');
      expect(onMyWayText(const TripEstimate(duration: Duration(seconds: 40), km: 0.35)), 'On my way · about 1 min (350 m)');
    });

    test('within 200 m: almost there', () {
      expect(onMyWayText(straightLineEstimate(a, a)), 'On my way · almost there');
      expect(onMyWayText(const TripEstimate(duration: Duration(seconds: 30), km: 0.15)), 'On my way · almost there');
    });
  });

  group('parseMapboxRoute', () {
    test('first route, seconds and metres', () {
      final e = parseMapboxRoute('{"code":"Ok","routes":[{"duration":1510.4,"distance":18234.5},{"duration":1700,"distance":20000}]}');
      expect(e, isNotNull);
      expect(e!.estimated, isFalse);
      expect(e.duration, const Duration(seconds: 1510));
      expect(e.km, closeTo(18.23, 0.01));
    });

    test('no route, an error or junk gives null (so the fallback runs)', () {
      expect(parseMapboxRoute('{"code":"NoRoute","routes":[]}'), isNull);
      expect(parseMapboxRoute('{"code":"Ok","routes":[]}'), isNull);
      expect(parseMapboxRoute('{"message":"Not Authorized - Invalid Token"}'), isNull);
      expect(parseMapboxRoute('<html>'), isNull);
    });
  });

  group('window and throttle', () {
    final start = DateTime(2026, 10, 3, 21);
    final end = DateTime(2026, 10, 4, 1);

    test('from 3 h before the start until the end', () {
      expect(onMyWayWindowOpen(startsAt: start, closesAt: end, now: DateTime(2026, 10, 3, 17, 59)), isFalse);
      expect(onMyWayWindowOpen(startsAt: start, closesAt: end, now: DateTime(2026, 10, 3, 18)), isTrue);
      expect(onMyWayWindowOpen(startsAt: start, closesAt: end, now: DateTime(2026, 10, 3, 23)), isTrue);
      expect(onMyWayWindowOpen(startsAt: start, closesAt: end, now: end), isFalse);
    });

    test('once per 10 min per meet', () {
      final t = OnMyWayThrottle();
      final now = DateTime(2026, 10, 3, 19);
      expect(t.waitFor('m1', now), isNull);
      t.mark('m1', now);
      expect(t.waitFor('m1', now.add(const Duration(minutes: 4))), const Duration(minutes: 6));
      expect(t.waitFor('m2', now), isNull, reason: 'other meets are separate');
      expect(t.waitFor('m1', now.add(const Duration(minutes: 10))), isNull);
      t.clear('m1');
      expect(t.waitFor('m1', now), isNull, reason: 'Undo frees it up again');
    });
  });
}
