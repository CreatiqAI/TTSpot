import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

// Stills from a playing video, for the poster a chat bubble, a moment or a
// post shows before the video loads. Put the VideoPlayer inside a
// RepaintBoundary with a GlobalKey and grab it once a frame is on screen.

/// The video frame on screen inside the RepaintBoundary at [frameKey] as a
/// JPEG (long side ~720 px), or null when the capture comes back blank (some
/// phones can't read the video surface).
Future<Uint8List?> grabVideoFrame(GlobalKey frameKey) async {
  try {
    final boundary = frameKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize) return null;
    final longest = math.max(boundary.size.width, boundary.size.height);
    if (longest <= 0) return null;
    final img = await boundary.toImage(pixelRatio: 720 / longest);
    try {
      final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null || isBlankFrame(raw)) return null;
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return null;
      return await FlutterImageCompress.compressWithList(png.buffer.asUint8List(), minWidth: img.width, minHeight: img.height, quality: 80, format: CompressFormat.jpeg);
    } finally {
      img.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// Nearly every sampled pixel black or see-through: the capture missed the video.
bool isBlankFrame(ByteData rgba) {
  final n = rgba.lengthInBytes ~/ 4;
  if (n == 0) return true;
  final step = math.max(1, n ~/ 2000);
  var lit = 0, seen = 0;
  for (var i = 0; i < n; i += step) {
    final o = i * 4;
    seen++;
    if (rgba.getUint8(o + 3) > 0 && rgba.getUint8(o) + rgba.getUint8(o + 1) + rgba.getUint8(o + 2) > 36) lit++;
  }
  return lit < seen * 0.02;
}

/// A dark card with a play mark, [aspect] wide over high, as a JPEG: the
/// poster when no frame could be grabbed, so a grid never shows a blank tile.
Future<Uint8List> placeholderVideoPoster({double aspect = 9 / 16}) async {
  final a = aspect.isFinite && aspect > 0 ? aspect.clamp(0.5, 2.0) : 9 / 16;
  final w = a >= 1 ? 1280.0 : 720.0;
  final h = (w / a).roundToDouble();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), const [Color(0xFF2A2F3A), Color(0xFF0F1115)]));
  final c = Offset(w / 2, h / 2);
  canvas.drawCircle(c, 96, Paint()..color = Colors.white.withValues(alpha: 0.18));
  canvas.drawPath(Path()..moveTo(c.dx - 28, c.dy - 44)..lineTo(c.dx + 44, c.dy)..lineTo(c.dx - 28, c.dy + 44)..close(), Paint()..color = Colors.white);
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  try {
    final png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    try {
      return await FlutterImageCompress.compressWithList(png, minWidth: img.width, minHeight: img.height, quality: 80, format: CompressFormat.jpeg);
    } catch (_) {
      return png;
    }
  } finally {
    img.dispose();
  }
}
