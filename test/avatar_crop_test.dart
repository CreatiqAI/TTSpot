import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/core/widgets/avatar_crop_screen.dart';

/// The round profile-photo crop: photos open covering the circle; a wide or
/// tall picture on a plain background (a logo) opens fitted inside it. Any
/// zoom can go out until the whole picture fits in the circle, and the space
/// around it is the picture's own edge colour, on screen and in the saved
/// 512 x 512 square. Pinch / drag / double-tap. No overflow at 360 px with
/// text at 1.0 and 1.3.
void main() {
  const red = Color(0xFFE00008);
  const logoBg = Color(0xFF1E3A8A); // a navy logo background

  /// [paint] draws on a w x h canvas; returns PNG bytes.
  Future<Uint8List> png(WidgetTester t, int w, int h, void Function(Canvas c, Size s) paint) async => (await t.runAsync(() async {
        final rec = ui.PictureRecorder();
        paint(Canvas(rec), Size(w.toDouble(), h.toDouble()));
        final img = await rec.endRecording().toImage(w, h);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        img.dispose();
        return data!.buffer.asUint8List();
      }))!;

  /// A "photo": colour changes all along every edge.
  void photo(Canvas c, Size s) {
    for (var x = 0; x < s.width; x += 20) {
      c.drawRect(Rect.fromLTWH(x.toDouble(), 0, 20, s.height), Paint()..color = HSVColor.fromAHSV(1, (x * 7) % 360, 0.8, 0.9).toColor());
    }
  }

  /// A wide logo: plain navy background, white word in the middle.
  void logo(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = logoBg);
    c.drawRect(Rect.fromCenter(center: s.center(Offset.zero), width: s.width * 0.8, height: s.height * 0.4), Paint()..color = Colors.white);
  }

  Uint8List rgbaOf(int w, int h, Color Function(int x, int y) at) {
    final b = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final c = at(x, y);
        final i = (y * w + x) * 4;
        b[i] = (c.r * 255).round();
        b[i + 1] = (c.g * 255).round();
        b[i + 2] = (c.b * 255).round();
        b[i + 3] = (c.a * 255).round();
      }
    }
    return b;
  }

  group('geometry', () {
    const wide = Size(800, 400);
    const tall = Size(400, 900);

    test('cover: the short side fills the circle; min: the whole picture fits inside the circle', () {
      expect(AvatarCrop.coverScale(wide, 300), 300 / 400);
      expect(AvatarCrop.coverScale(tall, 300), 300 / 400);
      final m = AvatarCrop.minScale(wide, 300);
      // Its diagonal is the circle's diameter: no corner is cut.
      expect(math.sqrt(math.pow(wide.width * m, 2) + math.pow(wide.height * m, 2)), closeTo(300, 1e-9));
      expect(m, lessThan(300 / 800));
    });

    test('opens covering for photos and near-square pictures, fitted for a wide or tall logo', () {
      expect(AvatarCrop.initialScale(wide, 300, plainEdges: false), AvatarCrop.coverScale(wide, 300));
      expect(AvatarCrop.initialScale(const Size(500, 450), 300, plainEdges: true), AvatarCrop.coverScale(const Size(500, 450), 300));
      expect(AvatarCrop.initialScale(wide, 300, plainEdges: true), AvatarCrop.minScale(wide, 300));
      expect(AvatarCrop.initialScale(tall, 300, plainEdges: true), AvatarCrop.minScale(tall, 300));
    });

    test('drag: covering axes never show an edge, smaller axes stay inside the square', () {
      final s = AvatarCrop.coverScale(wide, 300);
      expect(AvatarCrop.clamp(const Offset(500, 500), wide, s, 300), Offset.zero);
      final far = AvatarCrop.clamp(const Offset(-5000, -5000), wide, s, 300);
      expect(far.dx, 300 - wide.width * s);
      expect(far.dy, 0);
      final m = AvatarCrop.minScale(wide, 300);
      final c = AvatarCrop.clamp(const Offset(5000, 5000), wide, m, 300);
      expect(c.dx, closeTo(300 - wide.width * m, 1e-9));
      expect(c.dy, closeTo(300 - wide.height * m, 1e-9));
      expect(AvatarCrop.clamp(const Offset(-5000, -5000), wide, m, 300), Offset.zero);
    });

    test('source rect: centred square of the short side at cover; the whole picture when fitted', () {
      final s = AvatarCrop.coverScale(wide, 300);
      expect(AvatarCrop.sourceRect(AvatarCrop.centred(wide, s, 300), s, 300, wide), const Rect.fromLTWH(200, 0, 400, 400));
      final s2 = s * 2;
      final src2 = AvatarCrop.sourceRect(AvatarCrop.centred(wide, s2, 300), s2, 300, wide);
      expect(src2.width, closeTo(200, 0.001));
      expect(src2.center, within(distance: 0.001, from: const Offset(400, 200)));
      final m = AvatarCrop.minScale(wide, 300);
      expect(AvatarCrop.sourceRect(AvatarCrop.centred(wide, m, 300), m, 300, wide), const Rect.fromLTWH(0, 0, 800, 400));
    });

    test('edge colour: the most common edge colour; plain for a logo, not for a photo', () {
      final solid = AvatarCrop.edgeColour(rgbaOf(40, 20, (_, _) => red), 40, 20);
      expect(solid.fill, red);
      expect(solid.plain, isTrue);

      // Navy edge with a white word touching the bottom edge in a few spots: still navy, still plain.
      final lg = AvatarCrop.edgeColour(rgbaOf(60, 20, (x, y) => (x > 20 && x < 26) || (y > 5 && y < 15 && x > 5 && x < 55) ? Colors.white : logoBg), 60, 20);
      expect(lg.fill, logoBg);
      expect(lg.plain, isTrue);

      final ph = AvatarCrop.edgeColour(rgbaOf(60, 30, (x, _) => HSVColor.fromAHSV(1, (x * 12) % 360, 0.8, 0.9).toColor()), 60, 30);
      expect(ph.plain, isFalse);

      // See-through edges read as white.
      final clear = AvatarCrop.edgeColour(rgbaOf(20, 20, (_, _) => const Color(0x00000000)), 20, 20);
      expect(clear.fill, const Color(0xFFFFFFFF));
    });

    testWidgets('render: 512 x 512, the edge colour around a fitted picture, the picture in the middle', (t) async {
      final bytes = await png(t, 800, 400, (c, s) => c.drawRect(Offset.zero & s, Paint()..color = red));
      final out = await t.runAsync(() async {
        final codec = await ui.instantiateImageCodec(bytes);
        final img = (await codec.getNextFrame()).image;
        final m = AvatarCrop.minScale(const Size(800, 400), 300);
        final sq = await AvatarCrop.render(img, offset: AvatarCrop.centred(const Size(800, 400), m, 300), scale: m, d: 300, fill: logoBg);
        final data = await sq.toByteData(format: ui.ImageByteFormat.rawRgba);
        final w = sq.width, h = sq.height;
        img.dispose();
        sq.dispose();
        return (w: w, h: h, rgba: data!.buffer.asUint8List());
      });
      expect(out!.w, AvatarCrop.outputSide);
      expect(out.h, AvatarCrop.outputSide);
      Color at(int x, int y) {
        final i = (y * out.w + x) * 4;
        return Color.fromARGB(out.rgba[i + 3], out.rgba[i], out.rgba[i + 1], out.rgba[i + 2]);
      }

      for (final p in [(0, 0), (511, 0), (0, 511), (511, 511), (256, 20)]) {
        expect(at(p.$1, p.$2), logoBg, reason: 'pixel $p is the fill');
      }
      expect(at(256, 256), red);
      expect(at(30, 256), red, reason: 'the picture reaches near the sides');
    });
  });

  group('screen', () {
    late List<({int w, int h})> encoded;
    Uint8List? result;

    Future<AvatarCropScreenState> open(WidgetTester t, {double scale = 1.0, bool dark = true, int w = 800, int h = 400, void Function(Canvas, Size)? draw}) async {
      t.view.physicalSize = const Size(360 * 2, 740 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      encoded = [];
      result = null;
      final bytes = await png(t, w, h, draw ?? photo);
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
      for (var i = 0; i < 40 && t.state<AvatarCropScreenState>(find.byType(AvatarCropScreen)).sourceRect == null; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump();
      }
      return t.state<AvatarCropScreenState>(find.byType(AvatarCropScreen));
    }

    for (final scale in [1.0, 1.3]) {
      testWidgets('a photo opens covering the circle, centred, no overflow (text $scale)', (t) async {
        final st = await open(t, scale: scale);
        expect(st.zoom, closeTo(1, 1e-9));
        expect(st.sourceRect, const Rect.fromLTWH(200, 0, 400, 400));
        expect(find.text('Use photo'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('a wide logo opens fitted inside the circle on its own background (text $scale)', (t) async {
        final st = await open(t, scale: scale, draw: logo);
        expect(st.fill, logoBg);
        expect(st.zoom, lessThan(0.5));
        expect(st.sourceRect, const Rect.fromLTWH(0, 0, 800, 400));
        final fill = t.widget<DecoratedBox>(find.byKey(const ValueKey('avatar-crop-fill')));
        expect((fill.decoration as BoxDecoration).color, logoBg);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('pinching out stops when the whole photo fits; drags stop at the edges; double-tap resets', (t) async {
      final st = await open(t);
      final area = find.byKey(const ValueKey('avatar-crop-area'));
      final c = t.getCenter(area);
      final minZoom = AvatarCrop.minScale(const Size(800, 400), 1) / AvatarCrop.coverScale(const Size(800, 400), 1);

      // Drag far right at cover: the photo's left edge stops at the circle's.
      await t.dragFrom(c, const Offset(600, 0));
      await t.pump();
      expect(st.sourceRect!.left, closeTo(0, 1e-6));
      await t.dragFrom(c, const Offset(-2000, 0));
      await t.pump();
      expect(st.sourceRect!.right, closeTo(800, 1e-6));

      // Zoom out hard: stops with the whole photo inside the circle.
      var a = await t.startGesture(c + const Offset(-150, 0), pointer: 1);
      var b = await t.startGesture(c + const Offset(150, 0), pointer: 2);
      await t.pump();
      await a.moveTo(c + const Offset(-5, 0));
      await b.moveTo(c + const Offset(5, 0));
      await t.pump();
      await a.up();
      await b.up();
      await t.pump();
      expect(st.zoom, closeTo(minZoom, 1e-9));
      expect(st.sourceRect, const Rect.fromLTWH(0, 0, 800, 400));

      // Zoom in.
      a = await t.startGesture(c + const Offset(-10, 0), pointer: 3);
      b = await t.startGesture(c + const Offset(10, 0), pointer: 4);
      await t.pump();
      for (var dx = 20.0; dx <= 160; dx += 20) {
        await a.moveTo(c + Offset(-dx, 0));
        await b.moveTo(c + Offset(dx, 0));
        await t.pump();
      }
      await a.up();
      await b.up();
      await t.pumpAndSettle();
      expect(st.zoom, greaterThan(1.5));
      final r = st.sourceRect!;
      expect(r.left >= 0 && r.top >= 0 && r.right <= 800 && r.bottom <= 400, isTrue);

      // Double-tap: back to where it opened.
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
