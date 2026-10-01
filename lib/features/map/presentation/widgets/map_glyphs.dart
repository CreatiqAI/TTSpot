import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import 'map_pins.dart';

/// Places and events on the home map are all teardrop pins: a round head in
/// the kind's colour on a point that sits on the spot, with a white icon
/// inside. The colour and the icon say what it is:
///   spot         = its kind's colour and silhouette (star = top spot, bookmark = saved)
///   partner shop = ink with a red outline and a storefront
///   meet         = red with a flag (gold + crown for official clubs, ink + storefront for partners)
///   TT session   = a pennant flag instead of the meet flag
/// Zoomed out, pins that would overlap merge into a round count bubble.
/// Painters are shared by the markers and the on-map legend. The balloon is
/// the older event pin, still used by the convoy map and the static previews.
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

// --------------------------------------------------------------- teardrop ---

/// Teardrop pin: 32 × 40 logical px at scale 1 (the head is 32 across, white
/// outline included), the point at [teardropTip] on the location.
const teardropSize = Size(32, 40);
const teardropTip = Offset(16, 40);
const _headCentre = Offset(16, 16);

/// Room a picked pin's halo needs around the teardrop, at scale 1.
const teardropHaloMargin = 11.0;

/// The fill: a circle of [r] around the head centre with straight sides
/// down to the point at [tipY]. The outline is a stroke around it.
Path _teardropPath(double r, double tipY) {
  final d = tipY - _headCentre.dy;
  final phi = math.acos(r / d); // tangent points, measured from straight down
  final head = Rect.fromCircle(center: _headCentre, radius: r);
  return Path()
    ..moveTo(_headCentre.dx, tipY)
    ..lineTo(_headCentre.dx + r * math.sin(phi), _headCentre.dy + r * math.cos(phi))
    ..arcTo(head, math.pi / 2 - phi, -(2 * math.pi - 2 * phi), false)
    ..close();
}

/// A teardrop pin: [color] head with a 2.5 px [outline] (white, red for
/// partner shops), a soft shadow and a white mark inside: the [kind]'s
/// silhouette or an icon [glyph]. [recommended] adds
/// the red star badge and [saved] the bookmark badge (the star moves left).
/// [selected] draws a soft halo of its colour around the head; the caller
/// leaves [teardropHaloMargin] of room for it.
void paintTeardrop(
  Canvas c,
  Offset o, {
  double scale = 1,
  Color color = kEventRed,
  Color outline = Colors.white,
  SpotKind? kind,
  IconData? glyph,
  bool recommended = false,
  bool saved = false,
  bool selected = false,
}) {
  c.save();
  c.translate(o.dx, o.dy);
  c.scale(scale);
  const outlineW = 2.5;
  final body = _teardropPath(16 - outlineW, teardropTip.dy - outlineW);
  if (selected) {
    c.drawCircle(_headCentre, 16 + teardropHaloMargin - 3, Paint()..color = color.withValues(alpha: 0.30)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }
  // Shadow: the outer shape (outline included), a little lower and blurred.
  c.drawPath(_teardropPath(16, teardropTip.dy).shift(const Offset(0, 1.5)), Paint()..color = Colors.black.withValues(alpha: 0.28)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2));
  c.drawPath(body, Paint()..color = outline..style = PaintingStyle.stroke..strokeWidth = outlineW * 2..strokeJoin = StrokeJoin.round);
  c.drawPath(body, Paint()..color = color);
  if (kind != null) {
    paintSpotSilhouette(c, kind, _headCentre, 19);
  } else if (glyph != null) {
    final tp = TextPainter(
      text: TextSpan(text: String.fromCharCode(glyph.codePoint), style: TextStyle(fontFamily: glyph.fontFamily, fontSize: 16, color: Colors.white, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, _headCentre - Offset(tp.width / 2, tp.height / 2));
  }
  if (recommended) paintStarBadge(c, saved ? const Offset(4.5, 4.5) : const Offset(27.5, 4.5));
  if (saved) paintSavedBadge(c, const Offset(27.5, 4.5));
  c.restore();
}

/// Count bubble: pins too close to tell apart when zoomed out, as one round
/// chip with the number. 33 px across at scale 1 (white outline included),
/// about as wide as a small teardrop.
const clusterRadius = 14.0;
void paintCluster(Canvas c, Offset centre, {required int count, double scale = 1, Color color = kInk}) {
  c.save();
  c.translate(centre.dx, centre.dy);
  c.scale(scale);
  const outlineW = 2.5;
  c.drawCircle(const Offset(0, 1.5), clusterRadius + outlineW, Paint()..color = Colors.black.withValues(alpha: 0.28)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2));
  c.drawCircle(Offset.zero, clusterRadius + outlineW, Paint()..color = Colors.white);
  c.drawCircle(Offset.zero, clusterRadius, Paint()..color = color);
  final tp = TextPainter(
    text: TextSpan(text: count > 99 ? '99+' : '$count', style: TextStyle(fontSize: count > 99 ? 10.5 : 14, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
  c.restore();
}

// ------------------------------------------------------------------ spots ---

/// One visual language for places: every kind has its own colour and a
/// simple silhouette, so a cafe never looks like a carpark even when the
/// pin is only 22 px wide. Partner shops (workshops, accessories…) share
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

/// Small white bookmark on an ink disc: "saved by me", pinned to a pin's corner.
void paintSavedBadge(Canvas c, Offset centre, {double r = 5.2}) {
  c.drawCircle(centre, r + 1.4, Paint()..color = Colors.white);
  c.drawCircle(centre, r, Paint()..color = kInk);
  final tp = TextPainter(
    text: TextSpan(text: String.fromCharCode(AppIcons.bookmarkSimpleFill.codePoint), style: TextStyle(fontFamily: AppIcons.bookmarkSimpleFill.fontFamily, fontSize: r * 1.4, color: Colors.white, height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, centre - Offset(tp.width / 2, tp.height / 2));
}

/// Small red star on a white disc: "top spot", pinned to a pin's corner.
void paintStarBadge(Canvas c, Offset centre, {double r = 5.2}) {
  c.drawCircle(centre, r + 1.4, Paint()..color = Colors.white);
  c.drawCircle(centre, r, Paint()..color = kEventRed);
  final tp = TextPainter(
    text: TextSpan(text: String.fromCharCode(AppIcons.starFill.codePoint), style: TextStyle(fontFamily: AppIcons.starFill.fontFamily, fontSize: r * 1.45, color: Colors.white, height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, centre - Offset(tp.width / 2, tp.height / 2));
}

/// Small dot for a person (the legend's people rows).
void paintDot(Canvas c, Offset centre, {double r = 5, required Color color, Color ring = Colors.white}) {
  c.drawCircle(centre, r + 2, Paint()..color = ring);
  c.drawCircle(centre, r, Paint()..color = color);
}

/// Renders the glyph markers (with an optional label chip when zoomed in).
class GlyphMarkerFactory {
  GlyphMarkerFactory({required this.devicePixelRatio});
  final double devicePixelRatio;
  final _cache = <String, MapPin>{};

  /// [scale] shrinks the shape when the map is zoomed out.
  Future<MapPin> balloon({required String key, Color color = kEventRed, String? label, String? sub, double scale = 1, IconData? glyph}) =>
      _build('b|$key|${color.toARGB32()}|$label|$sub|$scale|${glyph?.codePoint}', balloonSize * scale, Offset(13, 33) * scale, (c) => paintBalloon(c, Offset.zero, color: color, scale: scale, glyph: glyph), label, sub);

  /// A teardrop pin (see [paintTeardrop]), its point on the location.
  /// [label] / [sub] add the name chip under it when zoomed in; [scale] grows
  /// it with the zoom. The cache key is every visual input and nothing else,
  /// so pins that look the same share one bitmap and a new size or state
  /// never reuses an old one.
  Future<MapPin> teardrop({
    required Color color,
    Color outline = Colors.white,
    SpotKind? kind,
    IconData? glyph,
    bool recommended = false,
    bool saved = false,
    bool selected = false,
    String? label,
    String? sub,
    double scale = 1,
  }) {
    final m = selected ? teardropHaloMargin : 0.0;
    return _build(
      't|${color.toARGB32()}|${outline.toARGB32()}|${kind?.index}|${glyph?.codePoint}|$recommended|$saved|$selected|$label|$sub|$scale',
      Size(teardropSize.width + m * 2, teardropSize.height + m) * scale,
      (teardropTip + Offset(m, m)) * scale,
      (c) => paintTeardrop(c, Offset(m, m) * scale, scale: scale, color: color, outline: outline, kind: kind, glyph: glyph, recommended: recommended, saved: saved, selected: selected),
      label,
      sub,
    );
  }

  /// A count bubble (see [paintCluster]), centred on the group.
  Future<MapPin> cluster({required int count, Color color = kInk, double scale = 1}) {
    final r = (clusterRadius + 2.5) * scale;
    return _build('c|$count|${color.toARGB32()}|$scale', Size(r * 2, r * 2), Offset(r, r), (c) => paintCluster(c, Offset(r, r), count: count, scale: scale, color: color), null, null);
  }

  /// Bitmaps being painted right now: a second request for the same key
  /// (two redraws in a row, or the pre-warm) waits for the first paint
  /// instead of painting it again.
  final _painting = <String, Future<MapPin>>{};

  Future<MapPin> _build(String k, Size icon, Offset anchorPx, void Function(Canvas) paint, String? label, String? sub) {
    final cached = _cache[k];
    if (cached != null) return Future.value(cached);
    // A block body: `=> _painting.remove(k)` would hand whenComplete this very
    // future to wait on, and the first caller would wait forever.
    return _painting[k] ??= _paint(k, icon, anchorPx, paint, label, sub).whenComplete(() {
      _painting.remove(k);
    });
  }

  Future<MapPin> _paint(String k, Size icon, Offset anchorPx, void Function(Canvas) paint, String? label, String? sub) async {

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

  void dispose() {
    _cache.clear();
    _painting.clear();
  }
}
