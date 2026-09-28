import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Re-encodes a photo with the number plate hidden: the box (fractions 0–1 of
/// the image, padded a little) is heavily blurred so nothing stays readable.
///
/// Pure dart:ui, so the output is PNG (the only format the engine encodes).
/// The longest side is capped at [maxSide] to keep that PNG well under the
/// bucket's 5 MB limit.
Future<Uint8List> blurPlate(
  Uint8List bytes, {
  required double x0,
  required double y0,
  required double x1,
  required double y1,
  int maxSide = 1280,
}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  final src = frame.image;
  try {
    final scale = math.min(1.0, maxSide / math.max(src.width, src.height));
    final w = math.max(1, (src.width * scale).round());
    final h = math.max(1, (src.height * scale).round());
    final srcRect = ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble());
    final full = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(src, srcRect, full, ui.Paint()..filterQuality = ui.FilterQuality.medium);

    // Pad the box: the model's corners are approximate, and a plate frame
    // often pokes out. Then keep it inside the image.
    final bw = (x1 - x0).abs() * w;
    final bh = (y1 - y0).abs() * h;
    final padX = math.max(6.0, bw * 0.25);
    final padY = math.max(6.0, bh * 0.35);
    final rect = ui.Rect.fromLTRB(
      math.min(x0, x1) * w - padX,
      math.min(y0, y1) * h - padY,
      math.max(x0, x1) * w + padX,
      math.max(y0, y1) * h + padY,
    ).intersect(full);

    if (!rect.isEmpty) {
      // Sigma relative to the plate's height: characters are roughly 70% of
      // it, so this leaves a flat smear rather than soft letters.
      final sigma = math.max(10.0, rect.height * 0.6);
      canvas.save();
      canvas.clipRect(rect);
      canvas.saveLayer(rect, ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.clamp));
      canvas.drawImageRect(src, srcRect, full, ui.Paint());
      canvas.restore();
      canvas.restore();
    }

    final picture = recorder.endRecording();
    final out = await picture.toImage(w, h);
    picture.dispose();
    try {
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode the blurred photo');
      return data.buffer.asUint8List();
    } finally {
      out.dispose();
    }
  } finally {
    src.dispose();
  }
}

/// Content type from the magic bytes: image_picker gives JPEG almost always,
/// [blurPlate] gives PNG.
String imageContentType(Uint8List bytes) {
  if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'image/png';
  if (bytes.length >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 && bytes[8] == 0x57 && bytes[9] == 0x45) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
