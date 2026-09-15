import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
  CarMarkerFactory({required this.devicePixelRatio, required this.pins});
  final double devicePixelRatio;
  final MapPinFactory pins;
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
  }) async {
    final k = 'car|$key|$colorKey|$name|$status|${headingDeg.round()}|$faceUrl|$showFace|$dim|$me';
    final cached = _cache[k];
    if (cached != null) return cached;

    final face = showFace && faceUrl != null ? await pins.image(faceUrl, targetWidth: 96) : null;
    const carSize = 58.0, faceSize = 22.0, gap = 2.0;
    final label = pins.text(name.length > 14 ? '${name.substring(0, 13)}…' : name, 11, FontWeight.w800, me ? Colors.white : const Color(0xFF101010));
    final st = status == null ? null : pins.text(status, 10.5, FontWeight.w700, statusColor);
    final chipW = label.width + (st == null ? 0 : st.width + 5) + 16;
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
      canvas.drawCircle(fc, faceSize / 2 + 2, Paint()..color = Colors.white);
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
    label.paint(canvas, Offset(x, rect.top + 3.5));
    x += label.width + 5;
    st?.paint(canvas, Offset(x, rect.top + 4));

    final pin = await pins.finish(recorder, totalW, totalH, anchorY: carCentre.dy / totalH);
    return _cache[k] = pin;
  }
}

/// Convenience for the map: how to describe freshness on the chip.
String freshnessLabel(DateTime updatedAt) {
  final d = DateTime.now().difference(updatedAt);
  if (d < const Duration(minutes: 20)) return 'now';
  if (d < const Duration(hours: 1)) return '${d.inMinutes}m';
  if (d < const Duration(hours: 24)) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// A circle with the radar look, used for live meets and the nearby ring.
Circle radarCircle({required String id, required LatLng at, required double radiusM, required double t, Color color = const Color(0xFFE00008)}) {
  // t 0..1: ring grows and fades out.
  return Circle(
    circleId: CircleId(id),
    center: at,
    radius: radiusM * (0.15 + 0.85 * t),
    strokeWidth: 2,
    strokeColor: color.withValues(alpha: (1 - t) * 0.8),
    fillColor: color.withValues(alpha: (1 - t) * 0.18),
    zIndex: 1,
  );
}
