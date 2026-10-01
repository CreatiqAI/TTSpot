import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/utils/plate_blur.dart';

/// "Hide my number plate": the box must come out unreadable (a flat smear,
/// no sharp black/white edges left) while the rest of the photo keeps its
/// detail, and the result is a PNG no bigger than maxSide.
Future<Uint8List> _stripes(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final white = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
  final black = ui.Paint()..color = const ui.Color(0xFF000000);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), white);
  // 4 px vertical stripes everywhere, like plate characters.
  for (var x = 0; x < w; x += 8) {
    canvas.drawRect(ui.Rect.fromLTWH(x.toDouble(), 0, 4, h.toDouble()), black);
  }
  final img = await recorder.endRecording().toImage(w, h);
  final png = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  return png.buffer.asUint8List();
}

Future<(int, int, ByteData)> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final img = (await codec.getNextFrame()).image;
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  return (img.width, img.height, data);
}

/// Biggest jump in red between neighbouring pixels along row [y], x0..x1.
int _maxStep(ByteData d, int w, int y, int x0, int x1) {
  var best = 0;
  for (var x = x0; x < x1 - 1; x++) {
    final a = d.getUint8((y * w + x) * 4), b = d.getUint8((y * w + x + 1) * 4);
    if ((a - b).abs() > best) best = (a - b).abs();
  }
  return best;
}

void main() {
  test('the plate box is smeared, the rest is untouched', () async {
    final src = await _stripes(800, 600);
    // Plate across the middle: x 0.4–0.6, y 0.45–0.55.
    final out = await blurPlate(src, x0: 0.4, y0: 0.45, x1: 0.6, y1: 0.55);
    expect(imageContentType(out), 'image/png');
    final (w, h, d) = await _decode(out);
    expect((w, h), (800, 600));
    // Inside the box: no stripe survives.
    expect(_maxStep(d, w, 300, 340, 460), lessThan(40));
    // Far from the box: full contrast stripes.
    expect(_maxStep(d, w, 50, 20, 200), greaterThan(200));
  });

  test('several boxes (front and rear plate) are each smeared, exactly where given', () async {
    final src = await _stripes(800, 600);
    final out = await blurRegions(src, [
      (x0: 0.1, y0: 0.1, x1: 0.3, y1: 0.2),
      (x0: 0.6, y0: 0.7, x1: 0.9, y1: 0.8),
    ]);
    final (w, h, d) = await _decode(out);
    expect((w, h), (800, 600));
    expect(_maxStep(d, w, 90, 100, 220), lessThan(40)); // inside box 1
    expect(_maxStep(d, w, 450, 500, 700), lessThan(40)); // inside box 2
    // No padding: just outside a box the stripes are sharp again.
    expect(_maxStep(d, w, 300, 100, 220), greaterThan(200));
    expect(_maxStep(d, w, 90, 260, 400), greaterThan(200));
  });

  test('sigma follows the box height, with a floor', () {
    expect(plateBlurSigma(100), 60);
    expect(plateBlurSigma(4), 10);
    expect(plateBlurSigma(4, min: 2), closeTo(2.4, 1e-9));
  });

  test('big photos are capped at maxSide', () async {
    final src = await _stripes(2000, 1000);
    final out = await blurPlate(src, x0: 0.1, y0: 0.1, x1: 0.2, y1: 0.2, maxSide: 1280);
    final (w, h, _) = await _decode(out);
    expect((w, h), (1280, 640));
  });
}
