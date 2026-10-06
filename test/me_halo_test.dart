import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/features/map/presentation/widgets/car_marker.dart';
import 'package:car_meet/features/map/presentation/widgets/map_pins.dart';

/// My marker's glow must fade out inside its own bitmap (the map draws the
/// bitmap as is, so any alpha on its border shows as a straight cut) and be
/// round. Checked for the top-down car and the dot, day and night, with and
/// without a heading beam, at the emulator's and an iPhone's pixel ratio.
Future<(int, int, ByteData)> _decode(MapPin pin) async {
  final codec = await ui.instantiateImageCodec(pin.bytes);
  final img = (await codec.getNextFrame()).image;
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  return (img.width, img.height, data);
}

int _alpha(ByteData d, int w, int x, int y) => d.getUint8((y * w + x) * 4 + 3);

/// Alpha at a point in pixel space (pixel k covers k..k+1), interpolated.
double _alphaAt(ByteData d, int w, double x, double y) {
  final fx = x - 0.5, fy = y - 0.5;
  final x0 = fx.floor(), y0 = fy.floor();
  final tx = fx - x0, ty = fy - y0;
  double a(int x, int y) => _alpha(d, w, x, y).toDouble();
  return a(x0, y0) * (1 - tx) * (1 - ty) + a(x0 + 1, y0) * tx * (1 - ty) + a(x0, y0 + 1) * (1 - tx) * ty + a(x0 + 1, y0 + 1) * tx * ty;
}

int _maxBorderAlpha(int w, int h, ByteData d) {
  var m = 0;
  for (var x = 0; x < w; x++) {
    m = math.max(m, math.max(_alpha(d, w, x, 0), _alpha(d, w, x, h - 1)));
  }
  for (var y = 0; y < h; y++) {
    m = math.max(m, math.max(_alpha(d, w, 0, y), _alpha(d, w, w - 1, y)));
  }
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final dpr in [2.625, 3.0]) {
    for (final night in [false, true]) {
      final label = '${night ? 'night' : 'day'} @${dpr}x';
      CarMarkerFactory factory() => CarMarkerFactory(devicePixelRatio: dpr, pins: MapPinFactory(devicePixelRatio: dpr), night: night);

      test('car: glow ends inside the bitmap ($label)', () async {
        for (final heading in [null, 0.0, 90.0, 225.0]) {
          final (w, h, d) = await _decode(await factory().me(coverUrl: null, colorKey: 'red', headingDeg: heading));
          expect(_maxBorderAlpha(w, h, d), 0, reason: 'heading $heading');
        }
      });

      test('dot: no glow, its shadow ends inside the bitmap and it is round ($label)', () async {
        for (final scale in [0.8, 1.0, 1.2]) {
          final pin = await factory().meDot(scale: scale);
          final (w, h, d) = await _decode(pin);
          expect(_maxBorderAlpha(w, h, d), 0, reason: 'scale $scale');
          // Same alpha all the way round inside the white ring (the dot is
          // 16 px across at scale 1, the ring 3 px wide).
          final c = pin.size.width / 2 * dpr, r = (16 * scale / 2 + 1.5) * dpr;
          final samples = [
            for (var i = 0; i < 16; i++) _alphaAt(d, w, c + r * math.cos(i * math.pi / 8), c + r * math.sin(i * math.pi / 8)),
          ];
          expect(samples.reduce(math.max) - samples.reduce(math.min), lessThanOrEqualTo(3), reason: 'scale $scale: $samples');
          expect(samples.reduce(math.min), greaterThan(0), reason: 'the white ring reaches that far');
        }
      });
    }
  }
}
