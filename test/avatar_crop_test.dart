import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/core/widgets/avatar_crop_screen.dart';

/// The round profile-photo crop: the photo always covers the circle (min
/// zoom), pinch / drag / double-tap move it, and "Use photo" saves a
/// 512 x 512 square of exactly the circle's bounding square. No overflow at
/// 360 px with text at 1.0 and 1.3.
void main() {
  const red = Color(0xFFE00008);

  Future<Uint8List> solidPng(WidgetTester t, int w, int h) async => (await t.runAsync(() async {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = red);
    final img = await rec.endRecording().toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
  }))!;

  group('geometry', () {
    const wide = Size(800, 400);
    const tall = Size(400, 900);

    test('min zoom: the photo just covers the circle', () {
      expect(AvatarCrop.minScale(wide, 300), 300 / 400);
      expect(AvatarCrop.minScale(tall, 300), 300 / 400);
      // The short side fills the circle exactly; the long side overhangs.
      final s = AvatarCrop.minScale(wide, 300);
      expect(wide.height * s, 300);
      expect(wide.width * s, greaterThan(300));
    });

    test('the circle square stays covered however far it is dragged', () {
      final s = AvatarCrop.minScale(wide, 300);
      expect(AvatarCrop.clamp(const Offset(500, 500), wide, s, 300), Offset.zero);
      final far = AvatarCrop.clamp(const Offset(-5000, -5000), wide, s, 300);
      expect(far.dx, 300 - wide.width * s);
      expect(far.dy, 0);
    });

    test('source rect: centred square of the short side at min zoom', () {
      final s = AvatarCrop.minScale(wide, 300);
      final src = AvatarCrop.sourceRect(AvatarCrop.centred(wide, s, 300), s, 300, wide);
      expect(src, const Rect.fromLTWH(200, 0, 400, 400));
      // Zoomed 2x on the centre: half the side.
      final s2 = s * 2;
      final src2 = AvatarCrop.sourceRect(AvatarCrop.centred(wide, s2, 300), s2, 300, wide);
      expect(src2.width, closeTo(200, 0.001));
      expect(src2.center.dx, closeTo(400, 0.001));
      expect(src2.center.dy, closeTo(200, 0.001));
    });

    testWidgets('render: a 512 x 512 square with no empty corners', (t) async {
      final bytes = await solidPng(t, 800, 400);
      final pixels = await t.runAsync(() async {
        final codec = await ui.instantiateImageCodec(bytes);
        final img = (await codec.getNextFrame()).image;
        final out = await AvatarCrop.render(img, const Rect.fromLTWH(200, 0, 400, 400));
        final w = out.width, h = out.height;
        final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        out.dispose();
        return (w: w, h: h, rgba: data!.buffer.asUint8List());
      });
      expect(pixels!.w, AvatarCrop.outputSide);
      expect(pixels.h, AvatarCrop.outputSide);
      int alphaAt(int x, int y) => pixels.rgba[(y * pixels.w + x) * 4 + 3];
      for (final p in [(0, 0), (511, 0), (0, 511), (511, 511), (256, 256)]) {
        expect(alphaAt(p.$1, p.$2), 255, reason: 'pixel $p must be photo, not empty');
      }
    });
  });

  group('screen', () {
    late List<({int w, int h})> encoded;
    Uint8List? result;

    Future<AvatarCropScreenState> open(WidgetTester t, {double scale = 1.0, bool dark = true, int w = 800, int h = 400}) async {
      t.view.physicalSize = const Size(360 * 2, 740 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      encoded = [];
      result = null;
      final bytes = await solidPng(t, w, h);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.current,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<Uint8List>(
                    MaterialPageRoute(
                      builder: (_) => AvatarCropScreen(
                        bytes: bytes,
                        dark: dark,
                        encoder: (img) async {
                          encoded.add((w: img.width, h: img.height));
                          return Uint8List.fromList([1, 2, 3]);
                        },
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      // Not pumpAndSettle: the spinner turns until the photo is decoded.
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      // Decoding the photo is real async work.
      for (var i = 0; i < 20 && t.state<AvatarCropScreenState>(find.byType(AvatarCropScreen)).sourceRect == null; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump();
      }
      return t.state<AvatarCropScreenState>(find.byType(AvatarCropScreen));
    }

    for (final scale in [1.0, 1.3]) {
      testWidgets('opens at min zoom, centred, no overflow (text $scale)', (t) async {
        final st = await open(t, scale: scale);
        expect(st.zoom, closeTo(1, 1e-9));
        expect(st.sourceRect, const Rect.fromLTWH(200, 0, 400, 400));
        expect(find.text('Use photo'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('pinching out stops at min zoom; drags stop at the edges; double-tap resets', (t) async {
      final st = await open(t);
      final area = find.byKey(const ValueKey('avatar-crop-area'));
      final c = t.getCenter(area);

      // Zoom out: fingers move together. Never below "covers the circle".
      var a = await t.startGesture(c + const Offset(-80, 0), pointer: 1);
      var b = await t.startGesture(c + const Offset(80, 0), pointer: 2);
      await t.pump();
      await a.moveTo(c + const Offset(-20, 0));
      await b.moveTo(c + const Offset(20, 0));
      await t.pump();
      await a.up();
      await b.up();
      await t.pump();
      expect(st.zoom, closeTo(1, 1e-9));

      // Drag far right: the photo's left edge stops at the circle's.
      await t.dragFrom(c, const Offset(600, 0));
      await t.pump();
      expect(st.sourceRect!.left, closeTo(0, 1e-6));
      await t.dragFrom(c, const Offset(-2000, 0));
      await t.pump();
      expect(st.sourceRect!.right, closeTo(800, 1e-6));

      // Zoom in.
      a = await t.startGesture(c + const Offset(-20, 0), pointer: 3);
      b = await t.startGesture(c + const Offset(20, 0), pointer: 4);
      await t.pump();
      await a.moveTo(c + const Offset(-100, 0));
      await b.moveTo(c + const Offset(100, 0));
      await t.pump();
      await a.up();
      await b.up();
      await t.pumpAndSettle();
      expect(st.zoom, greaterThan(1.5));
      final r = st.sourceRect!;
      expect(r.left >= 0 && r.top >= 0 && r.right <= 800 && r.bottom <= 400, isTrue);

      // Double-tap: back to min zoom, centred.
      await t.tapAt(c);
      await t.pump(const Duration(milliseconds: 50));
      await t.tapAt(c);
      await t.pumpAndSettle();
      expect(st.zoom, closeTo(1, 1e-9));
      expect(st.sourceRect, const Rect.fromLTWH(200, 0, 400, 400));
    });

    testWidgets('Use photo returns the encoded 512 px square; Cancel returns nothing', (t) async {
      await open(t, dark: false, w: 400, h: 900);
      await t.runAsync(() async {
        await t.tap(find.text('Use photo'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
      expect(encoded, [(w: AvatarCrop.outputSide, h: AvatarCrop.outputSide)]);
      expect(result, [1, 2, 3]);
      expect(find.byType(AvatarCropScreen), findsNothing);

      await t.tap(find.text('open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(result, isNull);
      expect(encoded, hasLength(1));
    });
  });
}
