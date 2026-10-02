import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'map_pins.dart';

/// Colours a garage car can be, and how they paint on the map.
const kCarColors = <String, Color>{
  'red': Color(0xFFE00008),
  'black': Color(0xFF1B1B1B),
  'white': Color(0xFFF2F2F2),
  'grey': Color(0xFF8A8A8A),
  'silver': Color(0xFFC9CCD1),
  'blue': Color(0xFF2B7CFF),
  'yellow': Color(0xFFF5C518),
  'green': Color(0xFF1DA750),
  'orange': Color(0xFFFF7A1A),
};

const kCarColorLabels = <String, String>{
  'red': 'Red', 'black': 'Black', 'white': 'White', 'grey': 'Grey', 'silver': 'Silver',
  'blue': 'Blue', 'yellow': 'Yellow', 'green': 'Green', 'orange': 'Orange',
};

Color carColor(String? key) => kCarColors[key] ?? const Color(0xFFB0B4BC);

/// Draws a top-down car (hood, glass, roof, wheels, lights) at [size] px,
/// rotated to [headingDeg] (0 = north), centred on [centre].
void paintCar(Canvas canvas, {required Offset centre, required double size, required Color color, double headingDeg = 0, bool dim = false}) {
  final s = size / 110; // symbol space is 60 x 110
  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  canvas.rotate(headingDeg * math.pi / 180);
  canvas.scale(s);
  canvas.translate(-30, -55);

  final body = dim ? Color.lerp(color, const Color(0xFF9A9A9A), 0.5)! : color;
  final glass = const Color(0xFF1D2430).withValues(alpha: dim ? 0.6 : 0.92);
  final light = body.computeLuminance() > 0.5;
  final highlight = Colors.white.withValues(alpha: light ? 0.35 : 0.18);
  final shade = Colors.black.withValues(alpha: light ? 0.10 : 0.18);
  final edge = Paint()
    ..color = light ? const Color(0xFF6E6E6E) : Colors.black.withValues(alpha: 0.35)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;

  // shadow
  canvas.drawOval(Rect.fromCenter(center: const Offset(30, 100), width: 40, height: 10), Paint()..color = Colors.black.withValues(alpha: 0.16));
  // wheels
  final tyre = Paint()..color = const Color(0xFF1A1A1A);
  for (final r in const [Rect.fromLTWH(2, 22, 9, 18), Rect.fromLTWH(49, 22, 9, 18), Rect.fromLTWH(2, 70, 9, 18), Rect.fromLTWH(49, 70, 9, 18)]) {
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), tyre);
  }
  // body
  final bodyPath = Path()
    ..moveTo(14, 6)
    ..quadraticBezierTo(30, 0, 46, 6)
    ..lineTo(52, 20)
    ..quadraticBezierTo(55, 28, 54, 48)
    ..lineTo(54, 82)
    ..quadraticBezierTo(54, 96, 46, 100)
    ..lineTo(14, 100)
    ..quadraticBezierTo(6, 96, 6, 82)
    ..lineTo(6, 48)
    ..quadraticBezierTo(5, 28, 8, 20)
    ..close();
  canvas.drawPath(bodyPath, Paint()..color = body);
  canvas.drawPath(bodyPath, edge);
  // hood highlight
  canvas.drawPath(Path()..moveTo(14, 6)..quadraticBezierTo(30, 0, 46, 6)..lineTo(52, 20)..lineTo(8, 20)..close(), Paint()..color = highlight);
  // mirrors
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(1, 33, 7, 4), const Radius.circular(2)), Paint()..color = body);
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(52, 33, 7, 4), const Radius.circular(2)), Paint()..color = body);
  // windscreen
  canvas.drawPath(Path()..moveTo(12, 38)..quadraticBezierTo(30, 30, 48, 38)..lineTo(46, 26)..quadraticBezierTo(30, 21, 14, 26)..close(), Paint()..color = glass);
  // roof
  canvas.drawRect(const Rect.fromLTWH(12, 40, 36, 26), Paint()..color = body);
  canvas.drawRect(const Rect.fromLTWH(14, 42, 32, 22), Paint()..color = highlight);
  // side windows
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(8, 42, 4, 22), const Radius.circular(1.5)), Paint()..color = glass);
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(48, 42, 4, 22), const Radius.circular(1.5)), Paint()..color = glass);
  // rear glass
  canvas.drawPath(Path()..moveTo(13, 68)..quadraticBezierTo(30, 74, 47, 68)..lineTo(46, 80)..quadraticBezierTo(30, 84, 14, 80)..close(), Paint()..color = glass);
  // lights
  final head = Paint()..color = const Color(0xFFFFF6C8);
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(9, 8, 10, 4), const Radius.circular(2)), head);
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(41, 8, 10, 4), const Radius.circular(2)), head);
  final tail = Paint()..color = const Color(0xFFFF3B3B);
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(9, 94, 11, 3.5), const Radius.circular(1.5)), tail);
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(40, 94, 11, 3.5), const Radius.circular(1.5)), tail);
  // hood line
  canvas.drawLine(const Offset(30, 8), const Offset(30, 22), Paint()..color = shade..strokeWidth = 1.2);
  canvas.restore();
}

/// Renders car markers for the map. Cached per key.
class CarMarkerFactory {
  CarMarkerFactory({required this.devicePixelRatio, required this.pins, this.night = false});
  final double devicePixelRatio;
  final MapPinFactory pins;
  /// The map is in its night style: my halo is painted for a dark map.
  final bool night;
  final _cache = <String, MapPin>{};

  /// A friend (or me, or a nearby stranger) as their car with a name chip.
  /// [face] draws a small avatar bubble; strangers pass null.
  Future<MapPin> car({
    required String key,
    required String colorKey,
    required String name,
    String? status,
    Color statusColor = const Color(0xFF22C55E),
    double headingDeg = 0,
    String? faceUrl,
    bool showFace = true,
    bool dim = false,
    bool me = false,
    Color? relation,
  }) async {
    final k = 'car|$key|$colorKey|$name|$status|${headingDeg.round()}|$faceUrl|$showFace|$dim|$me|${relation?.toARGB32()}';
    final cached = _cache[k];
    if (cached != null) return cached;

    final face = showFace && faceUrl != null ? await pins.image(faceUrl, targetWidth: 96) : null;
    const carSize = 58.0, faceSize = 22.0, gap = 2.0;
    final label = pins.text(name.length > 14 ? '${name.substring(0, 13)}…' : name, 11, FontWeight.w800, me ? Colors.white : const Color(0xFF101010));
    final st = status == null ? null : pins.text(status, 10.5, FontWeight.w700, statusColor);
    final chipW = label.width + (st == null ? 0 : st.width + 5) + 16 + (relation != null && !me ? 11 : 0);
    final chipH = label.height + 7;
    final totalW = math.max(carSize + 16, chipW) + 4;
    final totalH = carSize + gap + chipH + 8;
    final cx = totalW / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    final carCentre = Offset(cx, 4 + carSize / 2);
    paintCar(canvas, centre: carCentre, size: carSize, color: carColor(colorKey), headingDeg: headingDeg, dim: dim);

    if (showFace) {
      final fc = Offset(cx + carSize / 2 - 6, 4 + 8);
      canvas.drawCircle(fc, faceSize / 2 + 3.5, Paint()..color = relation ?? Colors.white);
      canvas.drawCircle(fc, faceSize / 2 + 1.5, Paint()..color = Colors.white);
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: fc, radius: faceSize / 2)));
      if (face != null) {
        pins.drawCover(canvas, face, Rect.fromCircle(center: fc, radius: faceSize / 2));
      } else {
        canvas.drawCircle(fc, faceSize / 2, Paint()..color = const Color(0xFF2A2F3A));
        final initial = pins.text(name.isEmpty ? '?' : name[0].toUpperCase(), 11, FontWeight.w800, Colors.white);
        initial.paint(canvas, fc - Offset(initial.width / 2, initial.height / 2));
      }
      canvas.restore();
    }

    // name chip
    final chipTop = 4 + carSize + gap;
    final rect = Rect.fromLTWH(cx - chipW / 2, chipTop, chipW, chipH);
    canvas.drawRRect(RRect.fromRectAndRadius(rect.shift(const Offset(0, 1.5)), const Radius.circular(8)), Paint()..color = Colors.black.withValues(alpha: 0.18));
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), Paint()..color = me ? const Color(0xFF101010) : (dim ? const Color(0xFFF2F2F2) : Colors.white));
    var x = rect.left + 8;
    if (relation != null && !me) {
      canvas.drawCircle(Offset(x + 3, rect.center.dy), 3.5, Paint()..color = relation);
      x += 11;
    }
    label.paint(canvas, Offset(x, rect.top + 3.5));
    x += label.width + 5;
    st?.paint(canvas, Offset(x, rect.top + 4));

    final pin = await pins.finish(recorder, totalW, totalH, anchorY: carCentre.dy / totalH);
    return _cache[k] = pin;
  }

  /// A person as their car's portrait: a rounded-square badge with the cover
  /// photo inside, a 3 px ring in the relationship colour, a small chevron on
  /// the ring pointing where they are heading, and a name chip underneath.
  /// Falls back to [car] when there is no photo (callers check [coverUrl]).
  /// The anchor is the badge centre, like the top-down car.
  Future<MapPin> badge({
    required String key,
    required String coverUrl,
    required String name,
    required Color ring,
    String? status,
    Color statusColor = const Color(0xFF22C55E),
    double? headingDeg,
    bool dim = false,
    bool me = false,
  }) async {
    final h = headingDeg == null ? null : ((headingDeg % 360) / 10).round() * 10;
    final k = 'badge|$key|$coverUrl|$name|$status|${statusColor.toARGB32()}|$h|$dim|$me|${ring.toARGB32()}';
    final cached = _cache[k];
    if (cached != null) return cached;

    final image = await pins.image(coverUrl, targetWidth: 160);
    const side = 44.0, ringW = 3.0, radius = 12.0, gap = 4.0;
    final label = pins.text(name.length > 14 ? '${name.substring(0, 13)}…' : name, 11, FontWeight.w800, me ? Colors.white : const Color(0xFF101010));
    final st = status == null ? null : pins.text(status, 10.5, FontWeight.w700, statusColor);
    final chipW = label.width + (st == null ? 0 : st.width + 5) + 16;
    final chipH = label.height + 7;
    final outer = side + ringW * 2;
    // My halo needs room to fade out inside the bitmap; friends have none.
    final haloR = outer / 2 + 6;
    final pad = me ? (haloReach(haloR) - outer / 2 + 1).ceilToDouble() : 12.0;
    final totalW = math.max(outer + pad * 2, chipW + 4);
    final totalH = pad + outer + gap + chipH + 6;
    final cx = totalW / 2;
    final centre = Offset(cx, pad + outer / 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    final ringPaint = Paint()..color = dim ? Color.lerp(ring, const Color(0xFFBFC3CA), 0.5)! : ring;
    if (me) paintHalo(canvas, centre, haloR, night: night);
    if (headingDeg != null) paintHeadingCone(canvas, centre, headingDeg, length: outer / 2 + 12, color: ringPaint.color);
    // shadow + ring
    final outerRect = RRect.fromRectAndRadius(Rect.fromCenter(center: centre, width: outer, height: outer), const Radius.circular(radius + ringW));
    canvas.drawRRect(outerRect.shift(const Offset(0, 2)), Paint()..color = Colors.black.withValues(alpha: 0.28)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawRRect(outerRect, ringPaint);
    // cover
    final inner = Rect.fromCenter(center: centre, width: side, height: side);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(inner, const Radius.circular(radius)));
    if (image != null) {
      pins.drawCover(canvas, image, inner, dimmed: dim);
    } else {
      canvas.drawRect(inner, Paint()..color = const Color(0xFF2A2F3A));
    }
    canvas.restore();
    // heading chevron on the ring
    if (headingDeg != null) {
      final a = headingDeg * math.pi / 180;
      final dir = Offset(math.sin(a), -math.cos(a));
      // where the heading ray leaves the rounded square (a circle is close enough at this size)
      final tip = centre + dir * (outer / 2 + 5);
      final base = centre + dir * (outer / 2 - 3);
      final side2 = Offset(-dir.dy, dir.dx) * 5.5;
      final chevron = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(base.dx + side2.dx, base.dy + side2.dy)
        ..lineTo(base.dx - side2.dx, base.dy - side2.dy)
        ..close();
      canvas.drawPath(chevron, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeJoin = StrokeJoin.round);
      canvas.drawPath(chevron, ringPaint);
    }
    // name chip
    final chipTop = pad + outer + gap;
    final rect = Rect.fromLTWH(cx - chipW / 2, chipTop, chipW, chipH);
    canvas.drawRRect(RRect.fromRectAndRadius(rect.shift(const Offset(0, 1.5)), const Radius.circular(8)), Paint()..color = Colors.black.withValues(alpha: 0.18));
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), Paint()..color = me ? const Color(0xFF101010) : (dim ? const Color(0xFFF2F2F2) : Colors.white));
    label.paint(canvas, Offset(rect.left + 8, rect.top + 3.5));
    st?.paint(canvas, Offset(rect.left + 8 + label.width + 5, rect.top + 4));

    final pin = await pins.finish(recorder, totalW, totalH, anchorY: centre.dy / totalH);
    return _cache[k] = pin;
  }

  /// Me, up close: my car's portrait badge when it has a photo, else the
  /// top-down car, both over a soft red halo and (when known) a heading cone,
  /// so I am the one thing on the map that cannot be mistaken for anyone else.
  Future<MapPin> me({required String? coverUrl, required String colorKey, double? headingDeg}) async {
    if (coverUrl != null) {
      return badge(key: 'me', coverUrl: coverUrl, name: 'Me', ring: kRelationMe, status: 'now', headingDeg: headingDeg, me: true);
    }
    final h = headingDeg == null ? null : ((headingDeg % 360) / 10).round() * 10;
    final k = 'mecar|$colorKey|$h';
    final cached = _cache[k];
    if (cached != null) return cached;
    const carSize = 58.0, gap = 2.0, haloR = carSize / 2 + 4;
    // Room for the halo to fade out inside the bitmap (see [haloReach]).
    final pad = (haloReach(haloR) - carSize / 2 + 1).ceilToDouble();
    final label = pins.text('Me', 11, FontWeight.w800, Colors.white);
    final st = pins.text('now', 10.5, FontWeight.w700, const Color(0xFF22C55E));
    final chipW = label.width + st.width + 5 + 16;
    final chipH = label.height + 7;
    final totalW = carSize + pad * 2;
    final totalH = pad + carSize + gap + chipH + 8;
    final cx = totalW / 2;
    final centre = Offset(cx, pad + carSize / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    paintHalo(canvas, centre, haloR, night: night);
    if (headingDeg != null) paintHeadingCone(canvas, centre, headingDeg, length: carSize / 2 + 14, color: kRelationMe);
    paintCar(canvas, centre: centre, size: carSize, color: carColor(colorKey), headingDeg: headingDeg ?? 0);
    final chipTop = pad + carSize + gap;
    final rect = Rect.fromLTWH(cx - chipW / 2, chipTop, chipW, chipH);
    canvas.drawRRect(RRect.fromRectAndRadius(rect.shift(const Offset(0, 1.5)), const Radius.circular(8)), Paint()..color = Colors.black.withValues(alpha: 0.18));
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), Paint()..color = const Color(0xFF101010));
    label.paint(canvas, Offset(rect.left + 8, rect.top + 3.5));
    st.paint(canvas, Offset(rect.left + 8 + label.width + 5, rect.top + 4));
    final pin = await pins.finish(recorder, totalW, totalH, anchorY: centre.dy / totalH);
    return _cache[k] = pin;
  }

  /// Me, zoomed out: a red dot with a white ring on a soft halo, plus a
  /// heading chevron when known. Always findable, whatever the zoom.
  Future<MapPin> meDot({double? headingDeg, double scale = 1}) async {
    final h = headingDeg == null ? null : ((headingDeg % 360) / 15).round() * 15;
    final size = 18.0 * scale.clamp(0.8, 1.2);
    // Keyed by the size drawn, not the scale asked for: every scale past the
    // clamp shares one bitmap.
    final k = 'medot|$h|${size.toStringAsFixed(2)}';
    final cached = _cache[k];
    if (cached != null) return cached;
    final haloR = size / 2 + 8;
    // Room for the halo to fade out inside the bitmap (see [haloReach]).
    final pad = (haloReach(haloR) - size / 2 + 1).ceilToDouble();
    final total = size + pad * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    final c = Offset(total / 2, total / 2);
    paintHalo(canvas, c, haloR, night: night);
    if (headingDeg != null) paintHeadingCone(canvas, c, headingDeg, length: size / 2 + 12, color: kRelationMe);
    canvas.drawCircle(c.translate(0, 1), size / 2 + 1, Paint()..color = Colors.black.withValues(alpha: 0.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawCircle(c, size / 2 + 2.5, Paint()..color = Colors.white);
    canvas.drawCircle(c, size / 2, Paint()..color = kRelationMe);
    final pin = await pins.finish(recorder, total, total, anchorY: 0.5);
    return _cache[k] = pin;
  }

  /// Far-zoom marker: a small dot in the relationship colour with a white ring.
  Future<MapPin> dot({required String key, required Color color, bool me = false, double scale = 1}) async {
    final k = 'dot|$key|${color.toARGB32()}|$me|$scale';
    final cached = _cache[k];
    if (cached != null) return cached;
    final size = (me ? 18.0 : 14.0) * scale;
    const pad = 4.0;
    final total = size + pad * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    final c = Offset(total / 2, total / 2);
    canvas.drawCircle(c.translate(0, 1), size / 2 + 1, Paint()..color = Colors.black.withValues(alpha: 0.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawCircle(c, size / 2 + 2, Paint()..color = Colors.white);
    canvas.drawCircle(c, size / 2, Paint()..color = color);
    final pin = await pins.finish(recorder, total, total, anchorY: 0.5);
    return _cache[k] = pin;
  }
}

/// Colours you can give a friend on the map, in rainbow order. Twelve that
/// stay apart from each other on both the day and the night map and under a
/// white ring (no white, black or grey: grey is a nearby stranger). The keys
/// are stored in `friend_tags.color` (the database check lists the same
/// twelve); the first seven are the original ones and must never change.
const kTagColors = <String, Color>{
  'red': Color(0xFFE00008),
  'orange': Color(0xFFFF7A1A),
  'yellow': Color(0xFFF5C518),
  'lime': Color(0xFF84CC16),
  'green': Color(0xFF1DA750),
  'teal': Color(0xFF0D9488),
  'sky': Color(0xFF0EA5E9),
  'blue': Color(0xFF2B7CFF),
  'indigo': Color(0xFF4F46E5),
  'purple': Color(0xFFA855F7),
  'pink': Color(0xFFEC4899),
  'brown': Color(0xFF92582A),
};

/// Names for [kTagColors] (tooltips and the key).
const kTagColorLabels = <String, String>{
  'red': 'Red', 'orange': 'Orange', 'yellow': 'Yellow', 'lime': 'Lime',
  'green': 'Green', 'teal': 'Teal', 'sky': 'Sky', 'blue': 'Blue',
  'indigo': 'Indigo', 'purple': 'Purple', 'pink': 'Pink', 'brown': 'Brown',
};

/// The colour a person's pin and dot use: my tag for them, else their
/// relationship's (clubmate purple, friend blue, nearby stranger grey).
Color personColor({String? tag, bool viaClub = false, bool stranger = false}) {
  if (stranger) return kRelationStranger;
  return kTagColors[tag] ?? (viaClub ? kRelationClub : kRelationFriend);
}

/// Default colour per relationship, when no tag is set.
const kRelationFriend = Color(0xFF2B7CFF);
const kRelationClub = Color(0xFFA855F7);
const kRelationStranger = Color(0xFF8A8A8A);
const kRelationMe = Color(0xFFE00008);

/// Convenience for the map: how to describe freshness on the chip.
String freshnessLabel(DateTime updatedAt) {
  final d = DateTime.now().difference(updatedAt);
  if (d < const Duration(minutes: 20)) return 'now';
  if (d < const Duration(hours: 1)) return '${d.inMinutes}m';
  if (d < const Duration(hours: 24)) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// How far [paintHalo] reaches from its centre for a halo of radius [r]: the
/// glow is fully transparent there. A bitmap that draws a halo keeps at least
/// this much room (plus a pixel) around the centre, so the glow fades out
/// inside the image instead of being cut off square at its edge.
double haloReach(double r) => r * 1.6;

/// Soft red glow under my marker, so the eye lands on me first. It reaches
/// zero at exactly [haloReach] (a blur mask filter has no hard edge, so it
/// always spilled past the bitmap and was clipped).
///
/// Two layers, both easing to nothing with zero slope at the rim: a wash
/// that evens out the map under it, then the red. A thin red tint alone
/// takes its look from what lies under it (pink on pale land, grey-mauve
/// on a road, brown on a park) and fades out fast, so on the map it read as
/// a box between the nearest road and park edge instead of a circle. The
/// wash is near-white by day and a deep rose at [night] (white would read
/// as fog on the dark map).
void paintHalo(Canvas canvas, Offset centre, double r, {Color color = kRelationMe, bool night = false}) {
  final reach = haloReach(r);
  _softDisc(canvas, centre, reach, night ? const Color(0xFFFF787D) : const Color(0xFFFFF2F2), alpha: night ? 0.60 : 0.85, fadeFrom: night ? 0.42 : 0.45);
  _softDisc(canvas, centre, reach, color, alpha: 0.40, fadeFrom: night ? 0.25 : 0.30, fadeTo: 0.95);
}

/// A disc of [color] at [alpha] out to [fadeFrom] x [reach], then a
/// smoothstep down to fully transparent at [fadeTo] x [reach]: no plateau
/// edge, no kink, nothing left at the rim.
void _softDisc(Canvas canvas, Offset centre, double reach, Color color, {required double alpha, required double fadeFrom, double fadeTo = 1.0}) {
  const steps = 10;
  final stops = <double>[0.0];
  final colors = <Color>[color.withValues(alpha: alpha)];
  for (var i = 0; i <= steps; i++) {
    final u = i / steps;
    stops.add(fadeFrom + (fadeTo - fadeFrom) * u);
    colors.add(color.withValues(alpha: alpha * (1 - u * u * (3 - 2 * u))));
  }
  if (fadeTo < 1) {
    stops.add(1.0);
    colors.add(color.withValues(alpha: 0));
  }
  canvas.drawCircle(centre, reach, Paint()..shader = ui.Gradient.radial(centre, reach, colors, stops));
}

/// Translucent beam from [centre] along [headingDeg] (0 = north), like the
/// phone's own blue-dot beam. Drawn under the marker. It fades with distance
/// and its sides are feathered by a sweep mask, so it has no straight edge.
void paintHeadingCone(Canvas canvas, Offset centre, double headingDeg, {required double length, required Color color}) {
  const half = 38 * math.pi / 180;
  final box = Rect.fromCircle(center: Offset.zero, radius: length);
  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  // Point the beam at local angle pi, so its sweep never wraps through 0.
  canvas.rotate(headingDeg * math.pi / 180 + math.pi / 2);
  canvas.saveLayer(box, Paint());
  canvas.drawPath(
    Path()
      ..moveTo(0, 0)
      ..arcTo(box, math.pi - half, half * 2, false)
      ..close(),
    Paint()..shader = ui.Gradient.radial(Offset.zero, length, [color.withValues(alpha: 0.7), color.withValues(alpha: 0.45), color.withValues(alpha: 0.0)], const [0.0, 0.6, 1.0]),
  );
  canvas.drawRect(
    box,
    Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = ui.Gradient.sweep(
        Offset.zero,
        const [Color(0x00000000), Color(0xCC000000), Color(0xFF000000), Color(0xCC000000), Color(0x00000000)],
        const [0.0, 0.3, 0.5, 0.7, 1.0],
        TileMode.clamp,
        math.pi - half,
        math.pi + half,
      ),
  );
  canvas.restore();
  canvas.restore();
}
