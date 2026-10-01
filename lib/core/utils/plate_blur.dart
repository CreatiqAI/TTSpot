import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A box to blur, as fractions (0–1) of the image's width and height.
typedef BlurRect = ({double x0, double y0, double x1, double y1});

/// How hard a box [heightPx] tall gets blurred. Characters are roughly 70%
/// of a plate's height, so this leaves a flat smear rather than soft letters.
/// Shared with the live preview in Check the plate, so what you see there is
/// what goes up.
double plateBlurSigma(double heightPx, {double min = 10}) => math.max(min, heightPx * 0.6);

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
}) {
  return _render(bytes, maxSide, (w, h) {
    // Pad the box: the model's corners are approximate, and a plate frame
    // often pokes out.
    final bw = (x1 - x0).abs() * w;
    final bh = (y1 - y0).abs() * h;
    final padX = math.max(6.0, bw * 0.25);
    final padY = math.max(6.0, bh * 0.35);
    return [
      ui.Rect.fromLTRB(
        math.min(x0, x1) * w - padX,
        math.min(y0, y1) * h - padY,
        math.max(x0, x1) * w + padX,
        math.max(y0, y1) * h + padY,
      ),
    ];
  });
}

/// Like [blurPlate] for any number of boxes (front and rear plate, say),
/// each blurred exactly as given: no padding, because these come from Check
/// the plate where the member sees the box they get.
Future<Uint8List> blurRegions(Uint8List bytes, List<BlurRect> boxes, {int maxSide = 1280}) {
  return _render(bytes, maxSide, (w, h) => [
        for (final b in boxes)
          ui.Rect.fromLTRB(math.min(b.x0, b.x1) * w, math.min(b.y0, b.y1) * h, math.max(b.x0, b.x1) * w, math.max(b.y0, b.y1) * h),
      ]);
}

/// Width and height of an encoded photo, as it draws (EXIF rotation applied).
Future<(int, int)> imageSizeOf(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    final size = (frame.image.width, frame.image.height);
    frame.image.dispose();
    return size;
  } finally {
    codec.dispose();
  }
}

/// Draws [bytes] at most [maxSide] on its longest side with every rect from
/// [rectsFor] (pixels of the output) blurred, and encodes it as PNG.
Future<Uint8List> _render(Uint8List bytes, int maxSide, List<ui.Rect> Function(int w, int h) rectsFor) async {
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

    for (final r in rectsFor(w, h)) {
      final rect = r.intersect(full); // keep it inside the image
      if (rect.isEmpty || rect.width <= 0 || rect.height <= 0) continue;
      final sigma = plateBlurSigma(rect.height);
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
