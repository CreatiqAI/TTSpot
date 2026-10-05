import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_images.dart';
import 'package:car_meet/features/profile/presentation/widgets/toy_car_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ToyCarImage's three states: the toy, the "building" fallback, the plain
// fallback (cut-out, photo, body art), each in the same fixed 16:9 box.

const _base = 'https://x.supabase.co/storage/v1/object/public/car-photos/u1';

Car _car({String? toyUrl, String? toyStatus, List<String> photos = const ['$_base/a.jpg'], String? cutoutUrl, String? cutoutSource, String? bodyStyle = 'hatchback'}) => Car(
      id: 'a',
      ownerId: 'u1',
      make: 'Perodua',
      model: 'Myvi',
      photoUrls: photos,
      createdAt: DateTime(2026, 9, 1),
      bodyStyle: bodyStyle,
      toyUrl: toyUrl,
      toyStatus: toyStatus,
      cutoutUrl: cutoutUrl,
      cutoutSource: cutoutSource,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: Center(child: child))));
  await tester.pump(const Duration(milliseconds: 50));
}

/// The source of the one picture shown.
ImageProvider _shown(WidgetTester tester) {
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  expect(images, hasLength(1));
  var p = images.single.image;
  if (p is ResizeImage) p = p.imageProvider;
  return p;
}

void main() {
  setUp(() {
    // No network in tests: every URL is a bundled picture.
    garageImageFor = (url) => url.endsWith('_toy.png')
        ? const AssetImage('assets/cars/sedan.png')
        : url.endsWith('_cut.png')
            ? const AssetImage('assets/cars/coupe.png')
            : const AssetImage('assets/portrait_samples/showroom.webp');
  });

  testWidgets('a car with a toy shows the toy, in a 16:9 box of the given width', (tester) async {
    final car = _car(toyUrl: '$_base/a_toy.png', toyStatus: 'ready');
    expect(ToyCarImage.stateFor(car, mine: true), 'toy');
    await _pump(tester, ToyCarImage(car: car, width: 300, mine: true));
    expect(tester.getSize(find.byType(ToyCarImage)), const Size(300, 300 * 9 / 16));
    expect(_shown(tester), const AssetImage('assets/cars/sedan.png'));
    expect(find.text('Building your toy car…'), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending: the cut-out (or photo) with the building caption; the box does not change', (tester) async {
    final cut = _car(toyStatus: 'pending', cutoutUrl: '$_base/a_cut.png', cutoutSource: '$_base/a.jpg');
    expect(ToyCarImage.stateFor(cut, mine: false), 'pending');
    await _pump(tester, ToyCarImage(car: cut, width: 300));
    expect(tester.getSize(find.byType(ToyCarImage)), const Size(300, 300 * 9 / 16));
    expect(_shown(tester), const AssetImage('assets/cars/coupe.png'));
    expect(find.text('Building your toy car…'), findsOneWidget);

    // No cut-out: the photo in its frame.
    final photo = _car(toyStatus: 'pending');
    await _pump(tester, ToyCarImage(car: photo, width: 300));
    expect(_shown(tester), const AssetImage('assets/portrait_samples/showroom.webp'));
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.text('Building your toy car…'), findsOneWidget);

    // The owner's own car that was never asked for counts as on its way;
    // a visitor sees the plain fallback.
    final fresh = _car();
    expect(ToyCarImage.stateFor(fresh, mine: true), 'pending');
    expect(ToyCarImage.stateFor(fresh, mine: false), 'fallback');

    // Thumbnails skip the caption.
    await _pump(tester, ToyCarImage(car: photo, width: 64, caption: false));
    expect(find.text('Building your toy car…'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed or no toy: cut-out, then photo, then the body-type art, no caption', (tester) async {
    final failed = _car(toyStatus: 'failed', cutoutUrl: '$_base/a_cut.png', cutoutSource: '$_base/a.jpg');
    expect(ToyCarImage.stateFor(failed, mine: true), 'fallback');
    await _pump(tester, ToyCarImage(car: failed, width: 300, mine: true));
    expect(_shown(tester), const AssetImage('assets/cars/coupe.png'));
    expect(find.text('Building your toy car…'), findsNothing);

    await _pump(tester, ToyCarImage(car: _car(toyStatus: 'failed'), width: 300, mine: true));
    expect(_shown(tester), const AssetImage('assets/portrait_samples/showroom.webp'));

    await _pump(tester, ToyCarImage(car: _car(toyStatus: 'failed', photos: const [], bodyStyle: 'coupe'), width: 300, mine: true));
    expect(_shown(tester), const AssetImage('assets/cars/coupe.png'));
    expect(tester.getSize(find.byType(ToyCarImage)), const Size(300, 300 * 9 / 16));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
