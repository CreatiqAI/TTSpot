import 'dart:math' as math;

import 'car_recognition.dart';

// The blur boxes in Check the plate. Everything is in fractions (0–1) of the
// photo's width and height, so a box means the same on a 96 px thumbnail, the
// zoomed editor and the 1280 px upload. Pure Dart: test/plate_geometry_test.

/// Smallest box you can shrink a blur to.
const kMinPlateW = 0.03;
const kMinPlateH = 0.02;

/// Most blurs on one photo (front and rear plate, a second car…).
const kMaxPlateBoxes = 4;

enum PlateCorner { topLeft, topRight, bottomLeft, bottomRight }

extension PlateBoxGeometry on PlateBox {
  double get width => (x1 - x0).abs();
  double get height => (y1 - y0).abs();
  double get cx => (x0 + x1) / 2;
  double get cy => (y0 + y1) / 2;

  /// Corners in order (x0 ≤ x1, y0 ≤ y1), inside the photo, at least the
  /// minimum size.
  PlateBox normalized() {
    final w = math.min(1.0, math.max(kMinPlateW, width));
    final h = math.min(1.0, math.max(kMinPlateH, height));
    return _fit(cx, cy, w, h);
  }

  /// Dragged by (dx, dy), same size, stopped at the photo's edges.
  PlateBox moved(double dx, double dy) {
    final b = normalized();
    final x0 = _clamp(b.x0 + dx, 0, 1 - b.width);
    final y0 = _clamp(b.y0 + dy, 0, 1 - b.height);
    return PlateBox(x0, y0, x0 + b.width, y0 + b.height);
  }

  /// The same box centred on (fx, fy), as far as the photo's edges allow.
  PlateBox centredAt(double fx, double fy) => moved(fx - cx, fy - cy);

  /// Pinched by [scale] about its centre, between the minimum and the photo.
  PlateBox scaled(double scale) {
    final b = normalized();
    final s = scale.isFinite && scale > 0 ? scale : 1.0;
    return _fit(b.cx, b.cy, _clamp(b.width * s, kMinPlateW, 1), _clamp(b.height * s, kMinPlateH, 1));
  }

  /// One corner pulled by (dx, dy) while the opposite corner stays put.
  /// Never smaller than the minimum, never outside the photo.
  PlateBox dragCorner(PlateCorner corner, double dx, double dy) {
    final b = normalized();
    var x0 = b.x0, y0 = b.y0, x1 = b.x1, y1 = b.y1;
    final left = corner == PlateCorner.topLeft || corner == PlateCorner.bottomLeft;
    final top = corner == PlateCorner.topLeft || corner == PlateCorner.topRight;
    if (left) {
      x0 = _clamp(x0 + dx, 0, x1 - kMinPlateW);
    } else {
      x1 = _clamp(x1 + dx, x0 + kMinPlateW, 1);
    }
    if (top) {
      y0 = _clamp(y0 + dy, 0, y1 - kMinPlateH);
    } else {
      y1 = _clamp(y1 + dy, y0 + kMinPlateH, 1);
    }
    return PlateBox(x0, y0, x1, y1);
  }

  /// Whether the two boxes cover any of the same photo.
  bool overlaps(PlateBox o) => x0 < o.x1 && o.x0 < x1 && y0 < o.y1 && o.y0 < y1;

  /// Whether (fx, fy) is on the box, with [slopX] / [slopY] extra around it
  /// (a finger is bigger than a small box).
  bool contains(double fx, double fy, {double slopX = 0, double slopY = 0}) =>
      fx >= x0 - slopX && fx <= x1 + slopX && fy >= y0 - slopY && fy <= y1 + slopY;
}

/// The recogniser's box as the box that gets blurred. Its corners are
/// approximate and a plate frame often pokes out, so it grows a quarter of
/// its width and a third of its height on every side (the padding the blur
/// used to add on its own). Check the plate shows exactly this box.
PlateBox blurBoxFromDetection(PlateBox found) {
  final b = PlateBox(math.min(found.x0, found.x1), math.min(found.y0, found.y1), math.max(found.x0, found.x1), math.max(found.y0, found.y1));
  final padX = math.max(0.005, b.width * 0.25);
  final padY = math.max(0.007, b.height * 0.35);
  return PlateBox(_clamp(b.x0 - padX, 0, 1), _clamp(b.y0 - padY, 0, 1), _clamp(b.x1 + padX, 0, 1), _clamp(b.y1 + padY, 0, 1)).normalized();
}

/// Where a plate usually sits when nothing found it: low in the middle of a
/// car photo, about a quarter of the width, plate-shaped (4:1) on a photo of
/// [aspect] (width / height).
PlateBox defaultPlateBox({required double aspect}) {
  final a = aspect.isFinite && aspect > 0 ? aspect : 4 / 3;
  const w = 0.24;
  final h = _clamp(w * a / 4, 0.04, 0.2);
  return _fit(0.5, 0.72, w, h);
}

/// "Add another blur": a plate-sized box centred on ([cx], [cy]) (the middle
/// of what is on screen) or the usual plate spot, moved down (then from the
/// top) until it is clear of the boxes already there. Sized like the last box
/// when there is one, so a second plate starts out like the first.
PlateBox nextPlateBox(List<PlateBox> existing, {required double aspect, double? cx, double? cy}) {
  final base = existing.isEmpty ? defaultPlateBox(aspect: aspect) : existing.last.normalized();
  final start = defaultPlateBox(aspect: aspect);
  var box = _fit(cx ?? start.cx, cy ?? start.cy, base.width, base.height);
  if (existing.isEmpty) return box;
  final step = box.height * 1.4;
  var y = box.cy;
  for (var i = 0; i < 24 && existing.any(box.overlaps); i++) {
    y += step;
    if (y + box.height / 2 > 1) y = box.height / 2; // off the bottom: carry on from the top
    box = _fit(box.cx, y, box.width, box.height);
  }
  return box;
}

/// A [w] × [h] box centred on (cx, cy), pushed inside the photo.
PlateBox _fit(double cx, double cy, double w, double h) {
  final ww = _clamp(w, 0, 1);
  final hh = _clamp(h, 0, 1);
  final x0 = _clamp(cx - ww / 2, 0, 1 - ww);
  final y0 = _clamp(cy - hh / 2, 0, 1 - hh);
  return PlateBox(x0, y0, x0 + ww, y0 + hh);
}

/// [num.clamp] that doesn't throw when the bounds cross (a box as big as the
/// photo): the lower bound wins.
double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? math.max(lo, hi) : v);
