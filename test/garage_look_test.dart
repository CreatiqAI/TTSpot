import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/domain/garage_look.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_body.dart';
import 'package:flutter_test/flutter_test.dart';

const _cover = 'https://x.supabase.co/storage/v1/object/public/car-photos/u1/100_0.jpg';
const _cut = 'https://x.supabase.co/storage/v1/object/public/car-photos/u1/100_0_cut.png';

Car _car({
  String id = 'c1',
  List<String> photos = const [_cover],
  String? cutoutUrl,
  String? cutoutSource,
  String style = 'auto',
  String? portrait,
  bool isDefault = false,
  DateTime? created,
}) =>
    Car(
      id: id,
      ownerId: 'u1',
      make: 'Perodua',
      model: 'Myvi',
      photoUrls: photos,
      createdAt: created ?? DateTime(2026, 9, 1),
      cutoutUrl: cutoutUrl,
      cutoutSource: cutoutSource,
      garageStyle: style,
      portraitUrl: portrait,
      isDefault: isDefault,
    );

/// A clean side shot of one car: what the bay wants.
const _good = CutoutReport(
  status: CutoutStatus.ok,
  areaRatio: 0.38,
  edgeLeft: 0,
  edgeRight: 0,
  edgeBottom: 0.04,
  subjects: 1,
  width: 1180,
  height: 560,
);

CutoutReport _with({
  CutoutStatus? status,
  double? areaRatio,
  double? edgeLeft,
  double? edgeRight,
  double? edgeBottom,
  double? edgeTop,
  int? subjects,
  double? secondRatio,
  int? width,
  int? height,
}) =>
    CutoutReport(
      status: status ?? _good.status,
      areaRatio: areaRatio ?? _good.areaRatio,
      edgeLeft: edgeLeft ?? _good.edgeLeft,
      edgeRight: edgeRight ?? _good.edgeRight,
      edgeBottom: edgeBottom ?? _good.edgeBottom,
      edgeTop: edgeTop ?? _good.edgeTop,
      subjects: subjects ?? _good.subjects,
      secondRatio: secondRatio ?? _good.secondRatio,
      width: width ?? _good.width,
      height: height ?? _good.height,
    );

void main() {
  group('CutoutGate', () {
    test('a whole car alone in the photo goes to the bay', () {
      expect(CutoutGate.check(_good), isNull);
      expect(CutoutGate.passes(_good), isTrue);
    });

    test('anything but ok goes to the card', () {
      expect(CutoutGate.check(_with(status: CutoutStatus.noSubject)), CutoutReject.noSubject);
      expect(CutoutGate.check(_with(status: CutoutStatus.ok, subjects: 0)), CutoutReject.noSubject);
      for (final s in [CutoutStatus.unsupported, CutoutStatus.notReady, CutoutStatus.error]) {
        expect(CutoutGate.check(_with(status: s)), CutoutReject.failed, reason: s.name);
      }
    });

    test('a far-away car or a close-up is the card', () {
      expect(CutoutGate.check(_with(areaRatio: 0.03)), CutoutReject.tooSmall);
      expect(CutoutGate.check(_with(areaRatio: 0.95)), CutoutReject.tooBig);
      expect(CutoutGate.check(_with(areaRatio: CutoutGate.minArea)), isNull);
    });

    test('a car cut off at the left, right or bottom is the card', () {
      expect(CutoutGate.check(_with(edgeLeft: 0.3)), CutoutReject.croppedSide);
      expect(CutoutGate.check(_with(edgeRight: 0.12)), CutoutReject.croppedSide);
      expect(CutoutGate.check(_with(edgeBottom: 0.5)), CutoutReject.croppedBottom);
    });

    test('a mirror tip at the side or tyres on the bottom edge are fine, and so is the top', () {
      expect(CutoutGate.check(_with(edgeLeft: 0.05)), isNull);
      expect(CutoutGate.check(_with(edgeBottom: 0.18)), isNull);
      expect(CutoutGate.check(_with(edgeTop: 0.6)), isNull);
    });

    test('a second big subject makes it busy; a small one is ignored', () {
      expect(CutoutGate.check(_with(subjects: 2, secondRatio: 0.6)), CutoutReject.crowded);
      expect(CutoutGate.check(_with(subjects: 3, secondRatio: 0.1)), isNull);
    });

    test('a subject taller than wide is not a car shot', () {
      expect(CutoutGate.check(_with(width: 500, height: 900)), CutoutReject.notCarShaped);
    });

    test('a tiny crop would look soft', () {
      expect(CutoutGate.check(_with(width: 300, height: 150)), CutoutReject.lowResolution);
    });

    test('reads the native report', () {
      final r = CutoutReport.fromMap({
        'status': 'ok',
        'areaRatio': 0.4,
        'edgeLeft': 0,
        'edgeRight': 0.01,
        'edgeTop': 0,
        'edgeBottom': 0.02,
        'subjects': 2,
        'secondRatio': 0.05,
        'width': 1200,
        'height': 600,
      });
      expect(r.status, CutoutStatus.ok);
      expect(r.aspect, 2);
      expect(CutoutGate.passes(r), isTrue);
      expect(CutoutReport.fromMap({'status': 'not_ready'}).status, CutoutStatus.notReady);
      expect(CutoutReport.fromMap({'status': 'no_subject'}).status, CutoutStatus.noSubject);
      expect(CutoutReport.fromMap({'status': 'unsupported'}).status, CutoutStatus.unsupported);
      expect(CutoutReport.fromMap(const {}).status, CutoutStatus.error);
    });
  });

  group('bay or card, per car', () {
    test('a cut-out made from the current cover stands in the bay', () {
      expect(garageLookFor(_car(cutoutUrl: _cut, cutoutSource: _cover)), GarageLook.cutout);
    });

    test('no cut-out yet, or one that failed the gate, is the card', () {
      expect(garageLookFor(_car()), GarageLook.card);
      expect(garageLookFor(_car(cutoutSource: _cover)), GarageLook.card);
    });

    test('a cut-out of an older cover is stale: card', () {
      expect(garageLookFor(_car(cutoutUrl: _cut, cutoutSource: 'https://x/old.jpg')), GarageLook.card);
    });

    test('the member forcing the card wins', () {
      expect(garageLookFor(_car(cutoutUrl: _cut, cutoutSource: _cover, style: 'card')), GarageLook.card);
    });

    test('no photos: card (the AI portrait is never cut out)', () {
      expect(garageLookFor(_car(photos: const [], portrait: 'https://x/p.png', cutoutUrl: _cut, cutoutSource: _cover)), GarageLook.card);
    });

    test('the owner cuts a car that has no attempt for its cover', () {
      expect(needsCutout(_car()), isTrue);
      expect(needsCutout(_car(cutoutUrl: _cut, cutoutSource: 'https://x/old.jpg')), isTrue);
      expect(needsCutout(_car(cutoutUrl: _cut, cutoutSource: _cover)), isFalse);
      expect(needsCutout(_car(cutoutSource: _cover)), isFalse, reason: 'failed the gate for this cover: no retry');
      expect(needsCutout(_car(style: 'card')), isFalse);
      expect(needsCutout(_car(photos: const [])), isFalse);
    });

    test('the cut-out sits next to its photo', () {
      expect(cutoutPath('u1/100_0.jpg'), 'u1/100_0_cut.png');
      expect(cutoutPath('u1/test-myvi.jpg'), 'u1/test-myvi_cut.png');
      expect(cutoutPath('u1/noext'), 'u1/noext_cut.png');
    });

    test('garage view setting', () {
      expect(GarageView.parse(null), GarageView.bay);
      expect(GarageView.parse('bay'), GarageView.bay);
      expect(GarageView.parse('cards'), GarageView.cards);
      expect(GarageView.parse('junk'), GarageView.bay);
    });
  });

  group('garage order', () {
    test('bays keep the order cars were parked; the garage opens on today\'s car', () {
      final a = _car(id: 'a', created: DateTime(2026, 1, 1));
      final b = _car(id: 'b', created: DateTime(2026, 3, 1), isDefault: true);
      final c = _car(id: 'c', created: DateTime(2026, 2, 1));
      final ordered = garageOrder([b, c, a]);
      expect(ordered.map((x) => x.id), ['a', 'c', 'b']);
      expect(todaysCar(ordered)?.id, 'b');
      expect(todaysCar([a, c])?.id, 'a');
      expect(todaysCar(const []), isNull);
    });
  });
}
