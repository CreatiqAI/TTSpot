import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/presentation/garage_setup_screen.dart';
import 'package:car_meet/features/profile/domain/car.dart';

/// "Building your garage" never flashes, never sticks and never fires twice:
/// it moves on at the cap when no toy comes, about 1.2 s after a toy arrives,
/// never before the minimum, and after a read that fails or a car that is gone.
void main() {
  final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

  Car car({String? toyUrl, String? toyStatus, List<String> photos = const []}) => Car(
        id: 'car-1',
        ownerId: 'me',
        make: 'Perodua',
        model: 'Myvi',
        photoUrls: photos,
        createdAt: DateTime(2026, 10, 1),
        toyUrl: toyUrl,
        toyStatus: toyStatus,
      );

  Future<List<DateTime>> pump(
    WidgetTester tester, {
    required Car start,
    required Future<Car?> Function(String id) read,
    Duration minTime = const Duration(milliseconds: 500),
    Duration cap = const Duration(seconds: 3),
    Duration poll = const Duration(milliseconds: 300),
    bool dark = false,
    double scale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    AppColors.dark = dark;
    addTearDown(() => AppColors.dark = false);
    final done = <DateTime>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.current,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: GarageSetupScreen(
        car: start,
        readCar: read,
        onDone: () => done.add(DateTime.now()),
        minTime: minTime,
        cap: cap,
        poll: poll,
        afterToy: const Duration(milliseconds: 1200),
        imageFor: (_) => MemoryImage(png),
      ),
    ));
    await tester.pump();
    return done;
  }

  Future<void> advance(WidgetTester tester, Duration d) async {
    var left = d;
    const step = Duration(milliseconds: 100);
    while (left > Duration.zero) {
      await tester.pump(left < step ? left : step);
      left -= step;
    }
  }

  for (final (dark, scale) in [(false, 1.0), (true, 1.3)]) {
    testWidgets('no toy: shows the car, lights the lines, continues at the cap (dark=$dark, x$scale)', (tester) async {
      var reads = 0;
      final done = await pump(tester, dark: dark, scale: scale, start: car(photos: ['https://x/photo.jpg']), read: (_) async {
        reads++;
        return car(photos: ['https://x/photo.jpg']);
      });
      expect(find.text('BUILDING YOUR GARAGE'), findsOneWidget);
      expect(find.text('Matching your car model'), findsOneWidget);
      expect(find.text('Painting it your colour'), findsOneWidget);
      expect(find.text('Wrapping your first blind box'), findsOneWidget);

      await advance(tester, const Duration(milliseconds: 2800));
      expect(done, isEmpty, reason: 'still waiting for the cap');
      expect(reads, greaterThanOrEqualTo(8), reason: 'polls every 300 ms');

      await advance(tester, const Duration(milliseconds: 400));
      expect(done, hasLength(1));
      await advance(tester, const Duration(seconds: 2));
      expect(done, hasLength(1), reason: 'fires once');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('toy arrives: reveals it and continues about 1.2 s after the reveal, before the cap', (tester) async {
    var reads = 0;
    final done = await pump(tester, cap: const Duration(seconds: 12), start: car(), read: (_) async {
      reads++;
      return reads >= 2 ? car(toyUrl: 'https://x/toy.png', toyStatus: 'ready') : car(toyStatus: 'pending');
    });
    await advance(tester, const Duration(milliseconds: 700)); // two polls → toy
    expect(done, isEmpty);
    await advance(tester, const Duration(milliseconds: 1500)); // 1.0 s reveal + 1.2 s hold = 2.2 s after arrival
    expect(done, isEmpty);
    await advance(tester, const Duration(milliseconds: 900));
    expect(done, hasLength(1));
    expect(reads, 2, reason: 'polling stops once the toy is here');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a toy already on the car still holds the minimum time', (tester) async {
    final done = await pump(tester, minTime: const Duration(seconds: 3), start: car(toyUrl: 'https://x/toy.png'), read: (_) async => null);
    await advance(tester, const Duration(milliseconds: 2500));
    expect(done, isEmpty, reason: 'the minimum is 3 s');
    await advance(tester, const Duration(milliseconds: 700));
    expect(done, hasLength(1));
  });

  testWidgets('reads that throw are ignored; the cap still ends the wait', (tester) async {
    final done = await pump(tester, start: car(), read: (_) async => throw Exception('offline'));
    await advance(tester, const Duration(milliseconds: 3200));
    expect(done, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the toy render failed: continues after the minimum, not the cap', (tester) async {
    final done = await pump(tester, minTime: const Duration(seconds: 1), cap: const Duration(seconds: 12), start: car(), read: (_) async => car(toyStatus: 'failed'));
    await advance(tester, const Duration(milliseconds: 1200));
    expect(done, hasLength(1));
  });

  testWidgets('the car row is gone: continues after the minimum', (tester) async {
    final done = await pump(tester, minTime: const Duration(seconds: 1), cap: const Duration(seconds: 12), start: car(), read: (_) async => null);
    await advance(tester, const Duration(milliseconds: 1200));
    expect(done, hasLength(1));
  });
}
