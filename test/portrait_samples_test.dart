import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/points/application/points_providers.dart';
import 'package:car_meet/features/profile/application/portrait_providers.dart';
import 'package:car_meet/features/profile/application/portrait_share.dart';
import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/domain/portrait_style.dart';
import 'package:car_meet/features/profile/presentation/widgets/portrait_sample_preview.dart';
import 'package:car_meet/features/profile/presentation/widgets/portrait_style_sheet.dart';

final _car = Car(
  id: 'car-1',
  ownerId: 'me',
  make: 'Porsche',
  model: '718 Cayman GT4',
  photoUrls: const ['https://example.com/a.jpg'],
  createdAt: DateTime(2026),
);

Future<ui.Image> _solid(int w, int h, ui.Color color, {ui.Rect? spot, ui.Color? spotColor}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = color);
  if (spot != null) canvas.drawRect(spot, ui.Paint()..color = spotColor!);
  return recorder.endRecording().toImage(w, h);
}

Future<(int, int, int)> _rgb(ui.Image img, int x, int y) async {
  final d = (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  final i = (y * img.width + x) * 4;
  return (d.getUint8(i), d.getUint8(i + 1), d.getUint8(i + 2));
}

/// Phone-sized surface at 1.3x text, so wrapping is exercised. The test
/// font draws every glyph a full em wide (wider than real fonts), so fitting
/// here means fitting on the phone.
Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.current,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: child,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('every style ships a sample, small enough for the app bundle', () {
    for (final s in kPortraitStyles) {
      final f = File(s.sampleAsset);
      expect(f.existsSync(), isTrue, reason: '${s.id} has no sample at ${s.sampleAsset}');
      expect(f.lengthSync(), lessThanOrEqualTo(200 * 1024), reason: '${s.id} sample is too big');
    }
  });

  test('the shared copy gets a small logo bottom right, the rest untouched', () async {
    const grey = ui.Color(0xFF3C3C3C);
    final photo = await _solid(800, 600, grey);
    // A "logo" file with wide transparent margins and a white mark inside.
    final logo = await _solid(200, 150, const ui.Color(0x00000000), spot: const ui.Rect.fromLTWH(50, 45, 100, 60), spotColor: const ui.Color(0xFFFFFFFF));
    final out = await watermarkPortrait(photo, logo);
    expect((out.width, out.height), (800, 600));
    // Logo: 12% of 800 = 96 px wide, 3.5% margin (28 px), so centred near (724, 543).
    final (r, g, b) = await _rgb(out, 724, 543);
    expect(r, greaterThan(200), reason: 'the mark shows, mostly opaque');
    expect(r, lessThan(250), reason: 'but a little see-through');
    expect((g, b), (r, r));
    expect(await _rgb(out, 10, 10), (0x3C, 0x3C, 0x3C), reason: 'the picture itself stays as it was');
    expect(await _rgb(out, 400, 300), (0x3C, 0x3C, 0x3C));
    // The mark is small: nothing left of 12% + margin from the right edge.
    expect(await _rgb(out, 800 - 28 - 96 - 20, 543), (0x3C, 0x3C, 0x3C));
    photo.dispose();
    logo.dispose();
    out.dispose();
  });

  testWidgets('picker: all 8 styles with their samples, nothing overflows at 1.3x', (tester) async {
    await _pump(tester, Scaffold(body: PortraitStylePicker(car: _car, cost: 300)));
    expect(find.text('Paint your 718 Cayman GT4'), findsOneWidget);
    expect(find.byType(PortraitStyleTile), findsNWidgets(8));
    for (final s in kPortraitStyles) {
      expect(find.text(s.name), findsOneWidget);
      // The whole line, never cut short.
      final text = tester.widget<Text>(find.text(s.description));
      expect(text.maxLines, isNull);
    }
    final images = tester.widgetList<Image>(find.byType(Image)).map((i) => (i.image is ResizeImage ? (i.image as ResizeImage).imageProvider : i.image) as AssetImage).map((a) => a.assetName);
    expect(images.toSet(), kPortraitStyles.map((s) => s.sampleAsset).toSet());
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview: big sample, swipe through the styles, real price, Back closes', (tester) async {
    bool? result = true;
    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => result = await showPortraitSamplePreview(context, car: _car, cost: 300, initial: 1),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('open'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('NIGHT CITY'), findsOneWidget);
    expect(find.text('2 / 8'), findsOneWidget);
    expect(find.textContaining('Sample: Porsche 911', findRichText: true), findsWidgets);
    expect(find.text('Paint my 718 Cayman GT4 · 300 points'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // A short swipe left: the next style (the page is 390 wide).
    await tester.fling(find.byType(PageView), const Offset(-200, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('GOLDEN HOUR'), findsOneWidget);
    expect(find.text('3 / 8'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(PortraitSamplePreview), findsNothing);
    // The open call started in the real-async zone; let its continuation run.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(result, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview says free when portraits cost nothing', (tester) async {
    await _pump(tester, PortraitSamplePreview(car: _car, cost: 0, initial: 0, page: ValueNotifier(0)));
    expect(find.text('SHOWROOM'), findsOneWidget);
    expect(find.text('Paint my 718 Cayman GT4 · free'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the style sheet opens at 85 % with the page peeking above, and a swipe down closes it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340); // a 393 x 851 phone
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portraitSettingsProvider.overrideWith((ref) async => (enabled: true, cost: 300)),
        pointsBalanceProvider.overrideWith((ref) async => 1000),
      ],
      child: MaterialApp(
        theme: AppTheme.current,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(child: TextButton(onPressed: () => showPortraitStyleSheet(context, ref, _car), child: const Text('open'))),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Paint your 718 Cayman GT4'), findsOneWidget);

    const screen = 851.0;
    final sheet = tester.getRect(find.byType(PortraitStylePicker));
    // The page shows above the sheet (and its drag handle): about 15 % of the screen.
    expect(sheet.top, greaterThan(screen * 0.12));
    expect(sheet.top, lessThan(screen * 0.2));
    expect(tester.takeException(), isNull);

    // A swipe down on the styles (scrolled to the top) drags the sheet away.
    await tester.fling(find.byType(PortraitStyleTile).first, const Offset(0, 600), 2000);
    await tester.pumpAndSettle();
    expect(find.byType(PortraitStylePicker), findsNothing);
  });
}
