import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A rendered marker plus its anchor (fraction of the image).
class MapPin {
  const MapPin(this.descriptor, this.anchor);
  final BitmapDescriptor descriptor;
  final Offset anchor;
}

/// Renders the non-event pins on the map with Canvas so they look the same on
/// every device: friend avatars, place history chips, moment bubbles.
/// Results are cached per key; images are cached per URL.
class MapPinFactory {
  MapPinFactory({required this.devicePixelRatio});
  final double devicePixelRatio;

  final _cache = <String, MapPin>{};
  final _images = <String, ui.Image?>{};

  // ------------------------------------------------------------- friends ---

  /// Round avatar with a coloured ring, a small status dot, and a name chip.
  Future<MapPin> avatar({
    required String key,
    required String? imageUrl,
    required String name,
    required Color ring,
    bool dimmed = false,
  }) async {
    final k = 'a|$key|$imageUrl|$name|${ring.toARGB32()}|$dimmed';
    final cached = _cache[k];
    if (cached != null) return cached;

    final image = imageUrl == null ? null : await _image(imageUrl, targetWidth: 160);
    const size = 52.0, border = 3.0, tail = 8.0, gap = 3.0;
    final label = _text(_short(name, 14), 11.5, FontWeight.w700, Colors.white);
    final chipW = label.width + 16, chipH = label.height + 8;
    final totalW = math.max(size + border * 2, chipW) + 4;
    final totalH = size + border * 2 + tail + gap + chipH + 2;
    final cx = totalW / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    final ringPaint = Paint()..color = dimmed ? ring.withValues(alpha: 0.55) : ring;
    final centre = Offset(cx, 1 + border + size / 2);
    canvas.drawCircle(centre, size / 2 + border, ringPaint);
    // tail
    final tailTop = centre.dy + size / 2 + border - 2;
    canvas.drawPath(
      Path()
        ..moveTo(cx - 7, tailTop)
        ..lineTo(cx + 7, tailTop)
        ..lineTo(cx, tailTop + tail + 1)
        ..close(),
      ringPaint,
    );
    // avatar
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: centre, radius: size / 2)));
    if (image != null) {
      _drawCover(canvas, image, Rect.fromCircle(center: centre, radius: size / 2), dimmed: dimmed);
    } else {
      canvas.drawCircle(centre, size / 2, Paint()..color = const Color(0xFF2A2F3A));
      final initial = _text(name.isEmpty ? '?' : name[0].toUpperCase(), 22, FontWeight.w700, Colors.white);
      initial.paint(canvas, centre - Offset(initial.width / 2, initial.height / 2));
    }
    canvas.restore();
    // status dot
    final dot = Offset(centre.dx + size / 2 - 5, centre.dy + size / 2 - 5);
    canvas.drawCircle(dot, 7, Paint()..color = const Color(0xFF151820));
    canvas.drawCircle(dot, 5, Paint()..color = dimmed ? const Color(0xFF8A919E) : const Color(0xFF22C55E));
    // name chip
    final chipTop = tailTop + tail + gap;
    _chip(canvas, Rect.fromLTWH(cx - chipW / 2, chipTop, chipW, chipH), label);

    final pin = await _finish(recorder, totalW, totalH, anchorY: (tailTop + tail) / totalH);
    return _cache[k] = pin;
  }

  // -------------------------------------------------------------- places ---

  /// Rounded chip: [art] + "12 meets" with a small tail. Bigger for busier places.
  Future<MapPin> placeChip({required String key, required String art, required String text, required int weight}) async {
    final k = 'p|$key|$art|$text|$weight';
    final cached = _cache[k];
    if (cached != null) return cached;

    final scale = weight >= 10 ? 1.25 : weight >= 4 ? 1.1 : 1.0;
    final artImg = await _asset(art);
    final artSize = 20.0 * scale;
    final label = _text(text, 12 * scale, FontWeight.w700, Colors.white);
    const padH = 10.0, padV = 6.0, tail = 7.0;
    final chipW = artSize + 6 + label.width + padH * 2;
    final chipH = math.max(artSize, label.height) + padV * 2;
    final totalW = chipW + 4, totalH = chipH + tail + 3;
    final cx = totalW / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    final rect = Rect.fromLTWH(2, 1, chipW, chipH);
    final bg = Paint()..color = const Color(0xF2F5A524);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(chipH / 2)), bg);
    canvas.drawPath(
      Path()
        ..moveTo(cx - 6, rect.bottom - 1)
        ..lineTo(cx + 6, rect.bottom - 1)
        ..lineTo(cx, rect.bottom + tail)
        ..close(),
      bg,
    );
    if (artImg != null) {
      _drawCover(canvas, artImg, Rect.fromLTWH(rect.left + padH, rect.center.dy - artSize / 2, artSize, artSize));
    }
    label.paint(canvas, Offset(rect.left + padH + artSize + 6, rect.center.dy - label.height / 2));

    final pin = await _finish(recorder, totalW, totalH, anchorY: (rect.bottom + tail) / totalH);
    return _cache[k] = pin;
  }

  // --------------------------------------------------------------- spots ---

  /// Rounded photo card (cover or kind art) with a coloured border and a chip
  /// underneath: "Genting Sempah · 12". Recommended spots get a star.
  Future<MapPin> spot({
    required String key,
    required String? imageUrl,
    required String art,
    required String title,
    required String count,
    bool recommended = false,
  }) async {
    final k = 's|$key|$imageUrl|$title|$count|$recommended';
    final cached = _cache[k];
    if (cached != null) return cached;

    final image = imageUrl == null ? null : await _image(imageUrl, targetWidth: 200);
    final artImg = image == null ? await _asset(art) : null;
    const card = 56.0, radius = 14.0, border = 3.0, tail = 8.0, gap = 4.0;
    final titleP = _text(_short(title, 16), 11.5, FontWeight.w700, Colors.white);
    final countP = _text(count, 11, FontWeight.w500, const Color(0xFFB4BAC4));
    final chipW = titleP.width + 5 + countP.width + 16;
    final chipH = math.max(titleP.height, countP.height) + 10;
    final outer = card + border * 2;
    final totalW = math.max(outer, chipW) + 4;
    final totalH = outer + tail + gap + chipH + 2;
    final cx = totalW / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    final borderPaint = Paint()..color = recommended ? const Color(0xFFF5A524) : const Color(0xFF8A919E);
    final outerRect = RRect.fromRectAndRadius(Rect.fromLTWH(cx - outer / 2, 1, outer, outer), const Radius.circular(radius + border));
    canvas.drawRRect(outerRect, borderPaint);
    final tailTop = 1 + outer - 1;
    canvas.drawPath(
      Path()
        ..moveTo(cx - 7, tailTop)
        ..lineTo(cx + 7, tailTop)
        ..lineTo(cx, tailTop + tail + 1)
        ..close(),
      borderPaint,
    );
    final cardRect = Rect.fromLTWH(cx - card / 2, 1 + border, card, card);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(cardRect, const Radius.circular(radius)));
    if (image != null) {
      _drawCover(canvas, image, cardRect);
    } else {
      canvas.drawRect(cardRect, Paint()..color = const Color(0xFF1C1F26));
      if (artImg != null) {
        _drawCover(canvas, artImg, Rect.fromCenter(center: cardRect.center, width: 34, height: 34));
      }
    }
    canvas.restore();
    if (recommended) {
      // small star badge, top-right
      final c = Offset(cardRect.right - 2, cardRect.top + 2);
      canvas.drawCircle(c, 9, Paint()..color = const Color(0xFF151820));
      canvas.drawCircle(c, 7, Paint()..color = const Color(0xFFF5A524));
      final star = _text('★', 9, FontWeight.w700, Colors.black);
      star.paint(canvas, c - Offset(star.width / 2, star.height / 2));
    }
    final chipTop = tailTop + tail + gap;
    final chipRect = RRect.fromRectAndRadius(Rect.fromLTWH(cx - chipW / 2, chipTop, chipW, chipH), const Radius.circular(8));
    canvas.drawRRect(chipRect, Paint()..color = const Color(0xF21C1F26));
    canvas.drawRRect(chipRect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.10));
    titleP.paint(canvas, Offset(cx - chipW / 2 + 8, chipTop + 5));
    countP.paint(canvas, Offset(cx - chipW / 2 + 8 + titleP.width + 5, chipTop + 5.5));

    final pin = await _finish(recorder, totalW, totalH, anchorY: (tailTop + tail) / totalH);
    return _cache[k] = pin;
  }

  // ------------------------------------------------------------- moments ---

  /// Small round photo bubble with a white ring (24 h moments).
  Future<MapPin> moment({required String key, required String imageUrl}) async {
    final k = 'm|$key';
    final cached = _cache[k];
    if (cached != null) return cached;

    final image = await _image(imageUrl, targetWidth: 120);
    const size = 40.0, ring = 2.5, tail = 6.0;
    final totalW = size + ring * 2 + 4, totalH = size + ring * 2 + tail + 3;
    final centre = Offset(totalW / 2, 1 + ring + size / 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    final white = Paint()..color = Colors.white;
    canvas.drawCircle(centre, size / 2 + ring, white);
    canvas.drawPath(
      Path()
        ..moveTo(centre.dx - 5, centre.dy + size / 2 + ring - 2)
        ..lineTo(centre.dx + 5, centre.dy + size / 2 + ring - 2)
        ..lineTo(centre.dx, centre.dy + size / 2 + ring + tail)
        ..close(),
      white,
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: centre, radius: size / 2)));
    if (image != null) {
      _drawCover(canvas, image, Rect.fromCircle(center: centre, radius: size / 2));
    } else {
      canvas.drawCircle(centre, size / 2, Paint()..color = const Color(0xFF2A2F3A));
    }
    canvas.restore();

    final pin = await _finish(recorder, totalW, totalH, anchorY: (centre.dy + size / 2 + ring + tail) / totalH);
    return _cache[k] = pin;
  }

  // ------------------------------------------------------------- helpers ---

  static String _short(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

  static TextPainter _text(String text, double size, FontWeight weight, Color color) => TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontSize: size, fontWeight: weight, color: color, height: 1.1)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  static void _chip(Canvas canvas, Rect rect, TextPainter label) {
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(rr, Paint()..color = const Color(0xF21C1F26));
    canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.10));
    label.paint(canvas, Offset(rect.left + 8, rect.top + 4));
  }

  static void _drawCover(Canvas canvas, ui.Image image, Rect dst, {bool dimmed = false}) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final scale = math.max(dst.width / iw, dst.height / ih);
    final sw = dst.width / scale, sh = dst.height / scale;
    final src = Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh);
    final paint = Paint()..filterQuality = FilterQuality.high;
    if (dimmed) paint.colorFilter = const ColorFilter.mode(Color(0x77000000), BlendMode.srcATop);
    canvas.drawImageRect(image, src, dst, paint);
  }

  Future<MapPin> _finish(ui.PictureRecorder recorder, double w, double h, {required double anchorY}) async {
    final picture = recorder.endRecording();
    final img = await picture.toImage((w * devicePixelRatio).ceil(), (h * devicePixelRatio).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return MapPin(BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), imagePixelRatio: devicePixelRatio), Offset(0.5, anchorY));
  }

  final _assets = <String, ui.Image?>{};

  /// A bundled PNG (assets/art/…) decoded once, ~64 px tall at this DPR.
  Future<ui.Image?> _asset(String path) async {
    if (_assets.containsKey(path)) return _assets[path];
    ui.Image? img;
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: (64 * devicePixelRatio).round());
      img = (await codec.getNextFrame()).image;
    } catch (_) {
      img = null;
    }
    _assets[path] = img;
    return img;
  }

  Future<ui.Image?> _image(String url, {required int targetWidth}) async {
    if (_images.containsKey(url)) return _images[url];
    ui.Image? img;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode == 200) {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in res) {
          builder.add(chunk);
        }
        final codec = await ui.instantiateImageCodec(builder.takeBytes(), targetWidth: (targetWidth * devicePixelRatio).round());
        img = (await codec.getNextFrame()).image;
      }
      client.close();
    } catch (_) {
      img = null;
    }
    _images[url] = img;
    return img;
  }

  void dispose() {
    for (final img in _images.values) {
      img?.dispose();
    }
    for (final img in _assets.values) {
      img?.dispose();
    }
    _assets.clear();
    _images.clear();
    _cache.clear();
  }
}
