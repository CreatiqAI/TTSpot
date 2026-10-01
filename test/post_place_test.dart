import 'package:car_meet/core/places/places_service.dart';
import 'package:car_meet/features/social/domain/club.dart';
import 'package:car_meet/features/social/domain/post_place.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // TTDI, Kuala Lumpur.
  const lat = 3.1390, lng = 101.6290;
  // ~0.0001 degrees is ~11 m here.
  PlaceDetails near(String name, double dLat, {String address = '', String? id, int? distanceM}) =>
      PlaceDetails(placeId: id ?? 'mbx:$name', name: name, address: address, lat: lat + dLat, lng: lng, distanceM: distanceM);
  Place spot(String id, String name, double dLat) => Place(id: id, name: name, kind: 'mamak', lat: lat + dLat, lng: lng, createdAt: DateTime(2026));

  group('areaFromAddress', () {
    test('Google style: house number, street, area, postcode city, state, country', () {
      expect(areaFromAddress('12, Jalan Datuk Sulaiman, Taman Tun Dr Ismail, 60000 Kuala Lumpur, Wilayah Persekutuan Kuala Lumpur, Malaysia'), 'Taman Tun Dr Ismail');
    });

    test('Mapbox style', () {
      expect(areaFromAddress('Jalan Burhanuddin Helmi, Taman Tun Dr Ismail, 60000 Kuala Lumpur, Kuala Lumpur, Malaysia'), 'Taman Tun Dr Ismail');
      expect(areaFromAddress('Persiaran Surian, Mutiara Damansara, 47810 Petaling Jaya, Selangor, Malaysia'), 'Mutiara Damansara');
    });

    test('no area: the city from "postcode city"', () {
      expect(areaFromAddress('Jalan Tun Razak, 50400 Kuala Lumpur, Malaysia'), 'Kuala Lumpur');
      expect(areaFromAddress('Lot 5, Jln. SS 2/24, 47300 Petaling Jaya, Selangor'), 'Petaling Jaya');
    });

    test('a state only when nothing else is left', () {
      expect(areaFromAddress('Jalan 1, Selangor, Malaysia'), 'Selangor');
    });

    test('nothing to say', () {
      expect(areaFromAddress(''), isNull);
      expect(areaFromAddress('Malaysia'), isNull);
      expect(areaFromAddress('No. 3, Jalan 5'), isNull);
    });
  });

  group('placeAt (Use my location)', () {
    test('a TT Spot right here wins over a closer named place', () {
      final p = placeAt(lat: lat, lng: lng, nearby: [near('Petronas', 0.0002)], spots: [spot('s1', 'Mamak Sri Melur', 0.0005)]);
      expect(p!.isSpot, isTrue);
      expect(p.spotId, 's1');
      expect(p.distanceM, lessThanOrEqualTo(kPlaceHereM));
    });

    test('else the closest named place within 80 m, with its address', () {
      final p = placeAt(lat: lat, lng: lng, nearby: [
        near('Far Cafe', 0.002, address: 'Jalan X, Taman Tun Dr Ismail'),
        near('Shell TTDI', 0.0003, address: 'Jalan Y, Taman Tun Dr Ismail', id: 'g1'),
      ], spots: [spot('s1', 'Some Spot', 0.01)]);
      expect(p!.isSpot, isFalse);
      expect(p.name, 'Shell TTDI');
      expect(p.address, contains('Jalan Y'));
      expect(p.key, 'g1');
      expect(p.approximate, isFalse);
    });

    test('uses the distance the lookup measured when it has one', () {
      final p = placeAt(lat: lat, lng: lng, nearby: [near('Condo', 0.0, distanceM: 200)]);
      expect(p!.approximate, isTrue); // 200 m away: not "here"
    });

    test('nothing named here: "Near <area>" on a ~1 km grid, never the exact spot', () {
      final p = placeAt(lat: 3.13912, lng: 101.62987, nearby: [near('Kedai', 0.003, address: 'Jalan Z, Taman Tun Dr Ismail, 60000 Kuala Lumpur')]);
      expect(p!.name, 'Near Taman Tun Dr Ismail');
      expect(p.approximate, isTrue);
      expect(p.lat, 3.14);
      expect(p.lng, 101.63);
      expect(p.address, isEmpty);
    });

    test('no address names an area: "Near" the closest place within 500 m', () {
      final p = placeAt(lat: lat, lng: lng, nearby: [near('Bengkel Ah Seng', 0.002)]);
      expect(p!.name, 'Near Bengkel Ah Seng');
      expect(placeAt(lat: lat, lng: lng, nearby: [near('Far away', 0.02)]), isNull);
    });

    test('nothing at all', () {
      expect(placeAt(lat: lat, lng: lng, nearby: const []), isNull);
    });
  });

  group('placesAround (the chips)', () {
    test('spots within 1 km first, then the rest, each nearest first', () {
      final chips = placesAround(lat: lat, lng: lng, nearby: [
        near('Cafe B', 0.002),
        near('Cafe A', 0.001),
      ], spots: [
        spot('s2', 'Far Spot', 0.05), // ~5.5 km: left out
        spot('s1', 'Near Spot', 0.004),
      ]);
      expect(chips.map((c) => c.name), ['Near Spot', 'Cafe A', 'Cafe B']);
      expect(chips.first.isSpot, isTrue);
      expect(chips.first.distanceM, isNotNull);
    });

    test('a search result that is one of our spots is listed once', () {
      final chips = placesAround(lat: lat, lng: lng, nearby: [near('Mamak Sri Melur TTDI', 0.0003)], spots: [spot('s1', 'Mamak Sri Melur', 0.0002)]);
      expect(chips, hasLength(1));
      expect(chips.single.isSpot, isTrue);
    });

    test('at most [max], no unnamed entries', () {
      final chips = placesAround(lat: lat, lng: lng, nearby: [for (var i = 0; i < 20; i++) near('Place $i', 0.0001 * i), near('  ', 0)], max: 10);
      expect(chips, hasLength(10));
      expect(chips.every((c) => c.name.trim().isNotEmpty), isTrue);
    });
  });

  test('PostPlace equality goes by the search id / spot id', () {
    final a = PostPlace.details(near('Shell', 0.001, id: 'g1'));
    final b = PostPlace.details(near('Shell (renamed)', 0.001, id: 'g1'));
    expect(a, b);
    expect(PostPlace.spot(spot('s1', 'X', 0)), isNot(a));
  });
}
