import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
const kGold = Color(0xFFD4A017);

/// [glyph] replaces the white dot in the head (crown for official clubs, storefront for partner events).
void paintBalloon(Canvas c, Offset o, {double scale = 1, Color color = kEventRed, IconData? glyph}) {
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
  if (glyph == null) {
    c.drawCircle(head, 3.2, Paint()..color = Colors.white);
  } else {
    final tp = TextPainter(
      text: TextSpan(text: String.fromCharCode(glyph.codePoint), style: TextStyle(fontFamily: glyph.fontFamily, fontSize: 11, color: Colors.white, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, head - Offset(tp.width / 2, tp.height / 2));
  }
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

// ------------------------------------------------------------------ spots ---

/// One visual language for places: every kind has its own colour and a
/// simple silhouette, so a cafe never looks like a carpark even when the
/// badge is only 20 px wide. Partner shops (workshops, accessories…) share
/// the slate "tools" family.
enum SpotKind { cafe, mamak, carpark, route, circuit, mall, workshop, other }

SpotKind spotKindOf(String kind) => switch (kind) {
      'cafe' => SpotKind.cafe,
      'mamak' => SpotKind.mamak,
      'carpark' => SpotKind.carpark,
      'route' => SpotKind.route,
      'circuit' => SpotKind.circuit,
      'mall' => SpotKind.mall,
      'workshop' || 'tyres' || 'bodyshop' || 'audio' || 'accessories' || 'detailing' || 'carwash' => SpotKind.workshop,
      _ => SpotKind.other,
    };

Color spotKindColor(SpotKind k) => switch (k) {
      SpotKind.cafe => const Color(0xFFD97706), // amber: coffee
      SpotKind.mamak => const Color(0xFF0D9488), // teal: teh tarik
      SpotKind.carpark => const Color(0xFF2563EB), // blue: the P sign
      SpotKind.route => const Color(0xFF16A34A), // green: the open road
      SpotKind.circuit => const Color(0xFF101010), // ink: chequered flag
      SpotKind.mall => const Color(0xFFDB2777), // pink: shopping
      SpotKind.workshop => const Color(0xFF475569), // slate: tools
      SpotKind.other => kSpotGrey,
    };

String spotKindLabel(SpotKind k) => switch (k) {
      SpotKind.cafe => 'Café',
      SpotKind.mamak => 'Mamak',
      SpotKind.carpark => 'Carpark',
      SpotKind.route => 'Route',
      SpotKind.circuit => 'Circuit',
      SpotKind.mall => 'Mall',
      SpotKind.workshop => 'Workshop',
      SpotKind.other => 'Spot',
    };

/// Draws the kind's silhouette in white, centred on [c] and sized to fit a
/// badge of [side] px. Plain Canvas shapes, no image assets, so it is crisp
/// at any DPR and any scale.
void paintSpotSilhouette(Canvas canvas, SpotKind k, Offset c, double side) {
  final white = Paint()..color = Colors.white;
  final stroke = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = side * 0.09
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final u = side / 20; // 20-unit symbol space
  canvas.save();
  canvas.translate(c.dx - 10 * u, c.dy - 10 * u);
  canvas.scale(u);
  switch (k) {
    case SpotKind.cafe:
      // mug with a handle and a wisp of steam
      canvas.drawRRect(RRect.fromRectAndCorners(const Rect.fromLTWH(4.5, 8, 8.5, 7.5), bottomLeft: const Radius.circular(2.5), bottomRight: const Radius.circular(2.5)), white);
      canvas.drawArc(const Rect.fromLTWH(11.5, 9, 4.5, 4.5), -math.pi / 2, math.pi, false, stroke..strokeWidth = 1.5);
      canvas.drawLine(const Offset(7, 6.5), const Offset(7, 4.5), stroke..strokeWidth = 1.2);
      canvas.drawLine(const Offset(10.5, 6.5), const Offset(10.5, 4.5), stroke);
    case SpotKind.mamak:
      // teh tarik glass: tapered tumbler with a foam line
      final glass = Path()
        ..moveTo(5.5, 4.5)
        ..lineTo(14.5, 4.5)
        ..lineTo(13.2, 16)
        ..lineTo(6.8, 16)
        ..close();
      canvas.drawPath(glass, white);
      canvas.drawLine(const Offset(6.3, 7.8), const Offset(13.7, 7.8), Paint()..color = spotKindColor(k)..strokeWidth = 1.1);
    case SpotKind.carpark:
      // a bold P
      final p = TextPainter(
        text: const TextSpan(text: 'P', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, Offset(10 - p.width / 2, 10 - p.height / 2));
    case SpotKind.route:
      // winding road with a dashed centre line
      final road = Path()
        ..moveTo(4, 17)
        ..cubicTo(4, 10, 16, 12, 16, 3);
      canvas.drawPath(road, stroke..strokeWidth = 4.2);
      canvas.drawPath(road, Paint()..color = spotKindColor(k)..style = PaintingStyle.stroke..strokeWidth = 1.1..strokeCap = StrokeCap.round);
      // break the centre line into dashes by painting road-coloured gaps over it
      for (final t in const [0.2, 0.55, 0.85]) {
        final m = _pointOn(const Offset(4, 17), const Offset(4, 10), const Offset(16, 12), const Offset(16, 3), t);
        canvas.drawCircle(m, 1.5, white);
      }
    case SpotKind.circuit:
      // chequered flag on a pole
      canvas.drawLine(const Offset(5, 3.5), const Offset(5, 17), stroke..strokeWidth = 1.6);
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 4; col++) {
          if ((row + col).isEven) canvas.drawRect(Rect.fromLTWH(6 + col * 2.6, 3.5 + row * 2.6, 2.6, 2.6), white);
        }
      }
    case SpotKind.mall:
      // shopping bag
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(4.5, 8, 11, 9), const Radius.circular(1.6)), white);
      canvas.drawArc(const Rect.fromLTWH(7, 3.5, 6, 7), math.pi, math.pi, false, stroke..strokeWidth = 1.5);
    case SpotKind.workshop:
      // spanner: a rotated bar with an open jaw
      canvas.save();
      canvas.translate(10, 10);
      canvas.rotate(-math.pi / 4);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-1.7, -3, 3.4, 10.5), const Radius.circular(1.5)), white);
      canvas.drawCircle(const Offset(0, -4.5), 3.4, white);
      canvas.drawRect(const Rect.fromLTWH(-1.1, -8.5, 2.2, 3.6), Paint()..color = spotKindColor(k));
      canvas.restore();
    case SpotKind.other:
      // map pin
      final pin = Path()
        ..addArc(const Rect.fromLTWH(5, 3, 10, 10), math.pi * 0.85, math.pi * 1.3)
        ..lineTo(10, 17.5)
        ..close();
      canvas.drawPath(pin, white);
      canvas.drawCircle(const Offset(10, 8), 2, Paint()..color = spotKindColor(k));
  }
  canvas.restore();
}

Offset _pointOn(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final mt = 1 - t;
  return p0 * (mt * mt * mt) + p1 * (3 * mt * mt * t) + p2 * (3 * mt * t * t) + p3 * (t * t * t);
}

/// Spot badge: 24 × 24 logical px, centred: a rounded square in the kind's
/// colour with its silhouette; top spots get a small red star in the corner.
const badgeSize = Size(24, 24);
void paintSpotBadge(Canvas c, Offset o, {double scale = 1, bool recommended = false, SpotKind kind = SpotKind.other}) {
  c.save();
  c.translate(o.dx, o.dy);
  c.scale(scale);
  final rect = RRect.fromRectAndRadius(const Rect.fromLTWH(1.5, 1.5, 21, 21), const Radius.circular(7));
  c.drawRRect(rect.shift(const Offset(0, 1.5)), Paint()..color = Colors.black.withValues(alpha: 0.22)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
  c.drawRRect(rect, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);
  c.drawRRect(rect, Paint()..color = spotKindColor(kind));
  paintSpotSilhouette(c, kind, const Offset(12, 12), 19);
  if (recommended) paintStarBadge(c, const Offset(21, 3.5));
  c.restore();
}

/// Small red star on a white disc: "top spot", pinned to a badge corner.
void paintStarBadge(Canvas c, Offset centre, {double r = 5.2}) {
  c.drawCircle(centre, r + 1.4, Paint()..color = Colors.white);
  c.drawCircle(centre, r, Paint()..color = kEventRed);
  final tp = TextPainter(
    text: TextSpan(text: String.fromCharCode(AppIcons.starFill.codePoint), style: TextStyle(fontFamily: AppIcons.starFill.fontFamily, fontSize: r * 1.45, color: Colors.white, height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, centre - Offset(tp.width / 2, tp.height / 2));
}

/// Small dot for a person or a far-away place (legend + far zoom). [ring]
/// replaces the white ring, e.g. red for a top spot.
void paintDot(Canvas c, Offset centre, {double r = 5, required Color color, Color ring = Colors.white}) {
  c.drawCircle(centre, r + 2, Paint()..color = ring);
  c.drawCircle(centre, r, Paint()..color = color);
}

/// Renders the glyph markers (with an optional label chip when zoomed in).
class GlyphMarkerFactory {
  GlyphMarkerFactory({required this.devicePixelRatio});
  final double devicePixelRatio;
  final _cache = <String, MapPin>{};

  /// [scale] shrinks the shape when the map is zoomed out (Waze-style: full
  /// size up close, smaller mid-way, plain dots far out).
  Future<MapPin> balloon({required String key, Color color = kEventRed, String? label, String? sub, double scale = 1, IconData? glyph}) =>
      _build('b|$key|${color.toARGB32()}|$label|$sub|$scale|${glyph?.codePoint}', balloonSize * scale, Offset(13, 33) * scale, (c) => paintBalloon(c, Offset.zero, color: color, scale: scale, glyph: glyph), label, sub);

  Future<MapPin> flag({required String key, Color color = kEventRed, String? label, String? sub, double scale = 1}) =>
      _build('f|$key|${color.toARGB32()}|$label|$sub|$scale', flagSize * scale, Offset(8, 35) * scale, (c) => paintFlag(c, Offset.zero, color: color, scale: scale), label, sub);

  /// A place, in its kind's colour and silhouette. [label] / [sub] add the
  /// name chip when zoomed in; [scale] grows the badge with the zoom.
  Future<MapPin> spot({required String key, required bool recommended, SpotKind kind = SpotKind.other, String? label, String? sub, double scale = 1}) =>
      _build('s|$key|$recommended|${kind.index}|$label|$sub|$scale', badgeSize * scale, Offset(12, 12) * scale, (c) => paintSpotBadge(c, Offset.zero, recommended: recommended, kind: kind, scale: scale), label, sub);

  /// Far-zoom marker: a small colour-coded dot with a white ring, like Waze
  /// when you zoom out to the whole city. [ring] swaps the white ring (red = top spot).
  Future<MapPin> dot({required String key, required Color color, double r = 4.5, Color ring = Colors.white}) =>
      _build('d|$key|${color.toARGB32()}|$r|${ring.toARGB32()}', Size((r + 2) * 2, (r + 2) * 2), Offset(r + 2, r + 2), (c) => paintDot(c, Offset(r + 2, r + 2), r: r, color: color, ring: ring), null, null);

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
    final pin = MapPin(bytes!.buffer.asUint8List(), Offset((iconLeft + anchorPx.dx) / w, (pad + anchorPx.dy) / h), Size(w, h));
    return _cache[k] = pin;
  }

  static TextPainter _text(String s, double size, FontWeight weight, Color color) => TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: weight, color: color, height: 1.1)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  void dispose() => _cache.clear();
}
