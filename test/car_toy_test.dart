import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/domain/car_toy.dart';
import 'package:flutter_test/flutter_test.dart';

const _cover = 'https://x.supabase.co/storage/v1/object/public/car-photos/u1/100_0.jpg';
const _newCover = 'https://x.supabase.co/storage/v1/object/public/car-photos/u1/200_0.jpg';
const _toy = 'https://x.supabase.co/storage/v1/object/public/car-photos/u1/toys/c1/1.png';

Car _car({
  String id = 'c1',
  String owner = 'u1',
  List<String> photos = const [_cover],
  String? toyUrl,
  String? toyStatus,
  String? toySource,
  String? color,
  String? toyColor,
}) =>
    Car(
      id: id,
      ownerId: owner,
      make: 'Perodua',
      model: 'Myvi',
      photoUrls: photos,
      createdAt: DateTime(2026, 9, 1),
      toyUrl: toyUrl,
      toyStatus: toyStatus,
      toySource: toySource,
      color: color,
      toyColor: toyColor,
    );

void main() {
  group('ToyStatus.parse', () {
    test('known values', () {
      expect(ToyStatus.parse('pending'), ToyStatus.pending);
      expect(ToyStatus.parse('ready'), ToyStatus.ready);
      expect(ToyStatus.parse('failed'), ToyStatus.failed);
    });
    test('null and junk read as none', () {
      expect(ToyStatus.parse(null), ToyStatus.none);
      expect(ToyStatus.parse(''), ToyStatus.none);
      expect(ToyStatus.parse('raw'), ToyStatus.none);
    });
    test('Car.fromMap carries the toy columns', () {
      final c = Car.fromMap({
        'id': 'c1',
        'owner_id': 'u1',
        'make': 'Perodua',
        'model': 'Myvi',
        'photo_urls': [_cover],
        'created_at': '2026-09-01T00:00:00Z',
        'toy_url': _toy,
        'toy_status': 'ready',
        'toy_source': _cover,
        'toy_color': 'red',
        'color': 'red',
      });
      expect(c.toy, ToyStatus.ready);
      expect(c.toyUrl, _toy);
      expect(c.toySource, _cover);
      expect(c.toyStale, isFalse);
      expect(c.toyColor, 'red');
      expect(c.toyPaintStale, isFalse);
    });
  });

  group('toyNeedsRequest', () {
    test('never asked → yes', () {
      expect(_car().toyNeedsRequest, isTrue);
    });
    test('no photo → no', () {
      expect(_car(photos: const []).toyNeedsRequest, isFalse);
    });
    test('pending → no', () {
      expect(_car(toyStatus: 'pending').toyNeedsRequest, isFalse);
      expect(_car(toyStatus: 'pending').toyPending, isTrue);
    });
    test('ready for this cover → no', () {
      expect(_car(toyStatus: 'ready', toyUrl: _toy, toySource: _cover).toyNeedsRequest, isFalse);
    });
    test('ready for an older cover → yes, and the old toy still shows', () {
      final c = _car(photos: const [_newCover], toyStatus: 'ready', toyUrl: _toy, toySource: _cover);
      expect(c.toyNeedsRequest, isTrue);
      expect(c.toyStale, isTrue);
      expect(c.toyToShow, _toy);
    });
    test('failed for this cover → no (Remake is the way out)', () {
      expect(_car(toyStatus: 'failed', toySource: _cover).toyNeedsRequest, isFalse);
    });
    test('failed, then a new cover → yes', () {
      expect(_car(photos: const [_newCover], toyStatus: 'failed', toySource: _cover).toyNeedsRequest, isTrue);
    });
    test('failed before any toy (no source yet) → yes, once a session', () {
      // toy_source is only written on success, so a first render that failed
      // (Kie busy, say) is tried again next session; the server's daily cap
      // and the watcher's tried-set keep that bounded.
      expect(_car(toyStatus: 'failed').toyNeedsRequest, isTrue);
    });
  });

  group('toyRequestPlan', () {
    test('only my cars that need one, in order, skipping tried', () {
      final cars = [
        _car(id: 'a'),
        _car(id: 'b', owner: 'u2'),
        _car(id: 'c', toyStatus: 'pending'),
        _car(id: 'd', toyStatus: 'ready', toyUrl: _toy, toySource: _cover),
        _car(id: 'e'),
      ];
      final plan = toyRequestPlan(cars, me: 'u1', tried: {toyTryKey(_car(id: 'e'))});
      expect(plan.map((c) => c.id), ['a']);
    });
    test('signed out → nothing', () {
      expect(toyRequestPlan([_car()], me: null, tried: {}), isEmpty);
    });
    test('a new cover is a new try key', () {
      expect(toyTryKey(_car()), isNot(toyTryKey(_car(photos: const [_newCover]))));
    });
  });
  group('paint (0110)', () {
    test('paint keys: the nine colours, anything else is "match the photo"', () {
      expect(paintKeyOf('Red'), 'red');
      expect(paintKeyOf(' silver '), 'silver');
      expect(paintKeyOf('auto'), isNull);
      expect(paintKeyOf(''), isNull);
      expect(paintKeyOf(null), isNull);
      expect(paintKeyOf('purple'), isNull);
    });
    test('ready in the picked paint → nothing to do', () {
      final c = _car(toyStatus: 'ready', toyUrl: _toy, toySource: _cover, color: 'red', toyColor: 'red');
      expect(c.toyNeedsRequest, isFalse);
      expect(c.toyPaintStale, isFalse);
      expect(c.toyRepainting, isFalse);
      expect(c.toyPaintWaiting, isFalse);
    });
    test('a new paint on a ready toy → ask (the cap held it back), the old toy still shows', () {
      final c = _car(toyStatus: 'ready', toyUrl: _toy, toySource: _cover, color: 'blue', toyColor: 'red');
      expect(c.toyNeedsRequest, isTrue);
      expect(c.toyPaintWaiting, isTrue);
      expect(c.toyRepainting, isFalse);
      expect(c.toyToShow, _toy);
    });
    test('repainting: pending with the old toy in another paint', () {
      final c = _car(toyStatus: 'pending', toyUrl: _toy, toySource: _cover, color: 'blue', toyColor: 'red');
      expect(c.toyRepainting, isTrue);
      expect(c.toyNeedsRequest, isFalse);
    });
    test('a repaint that failed is not asked again on its own (Remake / Try again)', () {
      final c = _car(toyStatus: 'failed', toyUrl: _toy, toySource: _cover, color: 'blue', toyColor: 'red');
      expect(c.toyNeedsRequest, isFalse);
      expect(c.toyPaintWaiting, isTrue);
    });
    test('no colour on either side (matched the photo) → done', () {
      expect(_car(toyStatus: 'ready', toyUrl: _toy, toySource: _cover).toyNeedsRequest, isFalse);
    });
    test('a new paint is a new try key', () {
      expect(toyTryKey(_car(color: 'red')), isNot(toyTryKey(_car(color: 'blue'))));
    });
    test('quota: left, capped, and the cap message', () {
      final q = ToyQuota.fromMap({'limit': 3, 'used': 3, 'left': 0, 'next_at': '2026-10-06T13:40:00+00:00', 'pending': false, 'enabled': true});
      expect(q.capped, isTrue);
      expect(q.left, 0);
      expect(q.nextAt!.isUtc, isFalse);
      expect(const ToyQuota(limit: 3, used: 1).left, 2);
      final msg = toyCapMessage(ToyQuota(limit: 3, used: 3, nextAt: DateTime(2026, 10, 6, 21, 40)), now: DateTime(2026, 10, 6, 20));
      expect(msg, "3 toy renders a day per car, and today's are used. The new paint goes on after 9:40 PM.");
      expect(formatToyTime(DateTime(2026, 10, 7, 0, 5), now: DateTime(2026, 10, 6, 20)), '12:05 AM tomorrow');
      expect(formatToyTime(DateTime(2026, 10, 6, 12, 30), now: DateTime(2026, 10, 6, 8)), '12:30 PM');
    });
  });
}
