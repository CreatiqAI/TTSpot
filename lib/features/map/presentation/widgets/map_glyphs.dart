import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/theme/app_icons.dart';
import 'map_pins.dart';

/// The three things people put on the map, each with its own small shape so
/// the map stays readable even when many sit close together:
///   balloon  = an event (meet, convoy, track day, official…)
///   flag     = a TT session (the feather flag outside a mamak)
///   badge    = a spot (rounded square; star = top spot)
/// Painters are shared by the markers and the on-map legend.
const kEventRed = Color(0xFFE00008);
const kInk = Color(0xFF101010);
const kSpotGrey = Color(0xFF4B4F58);

/// Balloon: 26 × 34 logical px, tip at (13, 33).
const balloonSize = Size(26, 34);
void paintBalloon(Canvas c, Offset o, {double scale = 1, Color color = kEventRed}) {
  c.save();
  c.translate(o.dx, o.dy);
  c.scale(scale);
  final head = const Offset(13, 12);
  const r = 9.5;
  final body = Path()
    ..addArc(Rect.fromCircle(center: head, radius: r), math.pi * 0.85, math.pi * 1.3)
    ..lineTo(13, 33)
    ..close();
  c.drawPath(body.shift(const Offset(0, 1.5)), Paint()..color = Colors.black.withValues(alpha: 0.22)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
  c.drawPath(body, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3.2..strokeJoin = StrokeJoin.round);
  c.drawPath(body, Paint()..color = color);
  c.drawCircle(head, 3.2, Paint()..color = Colors.white);
  c.restore();
}

/// Feather flag: 30 × 36 logical px, pole foot at (8, 35).
const flagSize = Size(30, 36);
void paintFlag(Canvas c, Offset o, {double scale = 1, Color color = kEventRed}) {
  c.save();
  c.translate(o.dx, o.dy);
  c.scale(scale);
  final sail = Path()
    ..moveTo(8, 3)
    ..cubicTo(21, 1, 29, 10, 24, 20)
    ..cubicTo(21, 25, 13, 26, 8, 27)
    ..close();
  c.drawPath(sail.shift(const Offset(0, 1.5)), Paint()..color = Colors.black.withValues(alpha: 0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
  final pole = Paint()..color = kInk..strokeWidth = 2.6..strokeCap = StrokeCap.round;
  c.drawLine(const Offset(8, 2), const Offset(8, 35), Paint()..color = Colors.white..strokeWidth = 5..strokeCap = StrokeCap.round);
  c.drawPath(sail, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3..strokeJoin = StrokeJoin.round);
  c.drawPath(sail, Paint()..color = color);
  c.drawLine(const Offset(8, 2), const Offset(8, 35), pole);
  c.restore();
}

/// Spot badge: 22 × 22 logical px, centred. Star for top spots.
const badgeSize = Size(22, 22);
void paintSpotBadge(Canvas c, Offset o, {double scale = 1, bool recommended = false}) {
  c.save();
  c.translate(o.dx, o.dy);
  c.scale(scale);
  final rect = RRect.fromRectAndRadius(const Rect.fromLTWH(1, 1, 20, 20), const Radius.circular(6.5));
  c.drawRRect(rect.shift(const Offset(0, 1.5)), Paint()..color = Colors.black.withValues(alpha: 0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
  c.drawRRect(rect, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);
  c.drawRRect(rect, Paint()..color = recommended ? kEventRed : kSpotGrey);
  final icon = recommended ? AppIcons.starFill : AppIcons.mapPinFill;
  final tp = TextPainter(
    text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontFamily: icon.fontFamily, fontSize: 12, color: Colors.white, height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, Offset(11 - tp.width / 2, 11 - tp.height / 2));
  c.restore();
}

/// Small dot for a person (legend + far zoom).
void paintDot(Canvas c, Offset centre, {double r = 5, required Color color}) {
  c.drawCircle(centre, r + 2, Paint()..color = Colors.white);
  c.drawCircle(centre, r, Paint()..color = color);
}

/// Renders the glyph markers (with an optional label chip when zoomed in).
class GlyphMarkerFactory {
  GlyphMarkerFactory({required this.devicePixelRatio});
  final double devicePixelRatio;
  final _cache = <String, MapPin>{};

  Future<MapPin> balloon({required String key, Color color = kEventRed, String? label, String? sub}) =>
      _build('b|$key|${color.toARGB32()}|$label|$sub', balloonSize, const Offset(13, 33), (c) => paintBalloon(c, Offset.zero, color: color), label, sub);

  Future<MapPin> flag({required String key, Color color = kEventRed, String? label, String? sub}) =>
      _build('f|$key|${color.toARGB32()}|$label|$sub', flagSize, const Offset(8, 35), (c) => paintFlag(c, Offset.zero, color: color), label, sub);

  Future<MapPin> spot({required String key, required bool recommended, String? label, String? sub}) =>
      _build('s|$key|$recommended|$label|$sub', badgeSize, const Offset(11, 11), (c) => paintSpotBadge(c, Offset.zero, recommended: recommended), label, sub);

  Future<MapPin> _build(String k, Size icon, Offset anchorPx, void Function(Canvas) paint, String? label, String? sub) async {
    final cached = _cache[k];
    if (cached != null) return cached;

    TextPainter? title, time;
    if (label != null && label.isNotEmpty) {
      title = _text(label.length > 16 ? '${label.substring(0, 15)}…' : label, 11, FontWeight.w700, Colors.white);
      if (sub != null && sub.isNotEmpty) time = _text(sub, 10.5, FontWeight.w500, const Color(0xFFB4BAC4));
    }
    const pad = 3.0, gap = 3.0;
    final chipW = title == null ? 0.0 : title.width + (time == null ? 0 : time.width + 5) + 14;
    final chipH = title == null ? 0.0 : math.max(title.height, time?.height ?? 0) + 8;
    final w = math.max(icon.width, chipW) + pad * 2;
    final h = icon.height + (title == null ? 0 : gap + chipH) + pad * 2;
    final iconLeft = (w - icon.width) / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    canvas.save();
    canvas.translate(iconLeft, pad);
    paint(canvas);
    canvas.restore();
    if (title != null) {
      final top = pad + icon.height + gap;
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH((w - chipW) / 2, top, chipW, chipH), const Radius.circular(7));
      canvas.drawRRect(rect, Paint()..color = const Color(0xF21C1F26));
      title.paint(canvas, Offset((w - chipW) / 2 + 7, top + 4));
      time?.paint(canvas, Offset((w - chipW) / 2 + 7 + title.width + 5, top + 4.5));
    }
    final picture = recorder.endRecording();
    final img = await picture.toImage((w * devicePixelRatio).ceil(), (h * devicePixelRatio).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    final pin = MapPin(
      BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), imagePixelRatio: devicePixelRatio),
      Offset((iconLeft + anchorPx.dx) / w, (pad + anchorPx.dy) / h),
    );
    return _cache[k] = pin;
  }

  static TextPainter _text(String s, double size, FontWeight weight, Color color) => TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: weight, color: color, height: 1.1)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  void dispose() => _cache.clear();
}
