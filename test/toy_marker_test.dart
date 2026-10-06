import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/features/map/presentation/widgets/car_marker.dart';
import 'package:car_meet/features/map/presentation/widgets/map_pins.dart';

/// The toy car on the map, Waze style: the render stands over a small
/// navigation arrow in the person's colour that points where they head
/// (a dot when the heading is unknown), mirrored to face east, no ring.

/// A stand-in render, [w] x [h]: red on its left half only (so a mirror
/// shows), or nothing at all ([blank]: only the arrow / dot paints opaque).
Future<ui.Image> _render({int w = 160, int h = 88, bool blank = false}) {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  if (!blank) c.drawRect(Rect.fromLTWH(0, 0, w / 2, h.toDouble()), Paint()..color = const Color(0xFFFF0000));
  return rec.endRecording().toImage(w, h);
}

class _Bitmap {
  _Bitmap(this.pin, this.w, this.h, this.data, this.dpr);
  final MapPin pin;
  final int w, h;
  final ByteData data;
  final double dpr;

  /// The anchor (where the person is), in logical px.
  Offset get anchor => Offset(pin.anchor.dx * pin.size.width, pin.anchor.dy * pin.size.height);

  /// RGBA at a logical point.
  (int, int, int, int) at(Offset p) {
    final x = (p.dx * dpr).floor().clamp(0, w - 1), y = (p.dy * dpr).floor().clamp(0, h - 1);
    final i = (y * w + x) * 4;
    return (data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2), data.getUint8(i + 3));
  }

  int maxBorderAlpha() {
    var m = 0;
    int a(int x, int y) => data.getUint8((y * w + x) * 4 + 3);
    for (var x = 0; x < w; x++) {
      m = math.max(m, math.max(a(x, 0), a(x, h - 1)));
    }
    for (var y = 0; y < h; y++) {
      m = math.max(m, math.max(a(0, y), a(w - 1, y)));
    }
    return m;
  }

  /// The box of opaque pixels (alpha > 200) inside [window] (logical px).
  Rect opaqueBox(Rect window) {
    var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
    for (var y = (window.top * dpr).floor(); y < (window.bottom * dpr).ceil(); y++) {
      for (var x = (window.left * dpr).floor(); x < (window.right * dpr).ceil(); x++) {
        if (x < 0 || y < 0 || x >= w || y >= h) continue;
        if (data.getUint8((y * w + x) * 4 + 3) > 200) {
          l = math.min(l, x / dpr);
          t = math.min(t, y / dpr);
          r = math.max(r, (x + 1) / dpr);
          b = math.max(b, (y + 1) / dpr);
        }
      }
    }
    return Rect.fromLTRB(l, t, r, b);
  }
}

Future<_Bitmap> _draw(ui.Image toy, {double? heading, Color color = kRelationFriend, bool me = false, bool dim = false, bool night = false, double dpr = 3}) async {
  final f = CarMarkerFactory(devicePixelRatio: dpr, pins: MapPinFactory(devicePixelRatio: dpr), night: night);
  final pin = await f.toyFromImage(toy, name: me ? 'Me' : 'Ali', color: color, status: 'now', headingDeg: heading, me: me, dim: dim);
  final codec = await ui.instantiateImageCodec(pin.bytes);
  final img = (await codec.getNextFrame()).image;
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  return _Bitmap(pin, img.width, img.height, data, dpr);
}

Offset _dir(double deg) => Offset(math.sin(deg * math.pi / 180), -math.cos(deg * math.pi / 180));

void _expectColour((int, int, int, int) px, Color c, {String? reason}) {
  final (r, g, b, a) = px;
  expect(a, greaterThan(240), reason: reason);
  expect((r - (c.r * 255).round()).abs(), lessThan(14), reason: '$reason red $px');
  expect((g - (c.g * 255).round()).abs(), lessThan(14), reason: '$reason green $px');
  expect((b - (c.b * 255).round()).abs(), lessThan(14), reason: '$reason blue $px');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('toyPose', () {
    test('no heading (null, NaN, or Android\'s exact 0): a dot, the render as drawn', () {
      for (final h in [null, double.nan, double.infinity, 0.0]) {
        final p = toyPose(h);
        expect(p.arrowDeg, isNull, reason: '$h');
        expect(p.east, isFalse, reason: '$h');
      }
    });

    test('a heading: the arrow in 10° steps; mirrored only while heading east', () {
      final cases = <double, (int, bool)>{
        90: (90, true),
        45: (50, true),
        20: (20, true),
        160: (160, true),
        12: (10, false), // near north: as drawn
        175: (180, false), // near south
        180: (180, false),
        270: (270, false),
        300: (300, false),
        355: (0, false), // rounds to north
        -90: (270, false),
        450: (90, true),
      };
      cases.forEach((h, want) {
        final p = toyPose(h);
        expect(p.arrowDeg, want.$1, reason: 'heading $h');
        expect(p.east, want.$2, reason: 'heading $h');
      });
    });
  });

  group('toy pin', () {
    test('a heading draws an arrow in their colour pointing that way; none draws a dot', () async {
      final blank = await _render(blank: true);
      for (final heading in [90.0, 200.0, 315.0]) {
        final pin = await _draw(blank, heading: heading);
        final d = _dir(heading);
        _expectColour(pin.at(pin.anchor), kRelationFriend, reason: 'the middle, heading $heading');
        _expectColour(pin.at(pin.anchor + d * 7), kRelationFriend, reason: 'towards the tip, heading $heading');
        // Behind the notch there is nothing opaque (a dot's white ring would be).
        expect(pin.at(pin.anchor - d * 7).$4, lessThan(160), reason: 'behind the tail, heading $heading');
      }
      final dot = await _draw(blank);
      _expectColour(dot.at(dot.anchor), kRelationFriend, reason: 'dot middle');
      for (final a in [0.0, 90.0, 180.0, 270.0]) {
        final (r, g, b, alpha) = dot.at(dot.anchor + _dir(a) * 6.6);
        expect(alpha > 240 && r > 235 && g > 235 && b > 235, isTrue, reason: 'white ring at $a°: ${(r, g, b, alpha)}');
        expect(dot.at(dot.anchor + _dir(a) * 9.5).$4, lessThan(160), reason: 'small: nothing opaque past 9.5 px');
      }
    });

    test('me: a red arrow; strangers and last seen: the colour washed out', () async {
      final blank = await _render(blank: true);
      final me = await _draw(blank, heading: 90, color: kRelationMe, me: true);
      _expectColour(me.at(me.anchor + const Offset(5, 0)), kRelationMe, reason: 'my arrow');
      final seen = await _draw(blank, heading: 90, dim: true);
      final (r, g, b, _) = seen.at(seen.anchor + const Offset(5, 0));
      final washed = Color.lerp(kRelationFriend, const Color(0xFFBFC3CA), 0.5)!;
      _expectColour((r, g, b, 255), washed, reason: 'seen arrow');
    });

    test('the arrow is small but readable: about 20 x 22 px with its white edge', () async {
      final blank = await _render(blank: true);
      final pin = await _draw(blank, heading: 90);
      final a = pin.anchor;
      // Above the chip, around the anchor.
      final box = pin.opaqueBox(Rect.fromLTRB(a.dx - 16, a.dy - 16, a.dx + 16, a.dy + 13));
      expect(box.width, inInclusiveRange(18, 23), reason: 'tip to tail $box');
      expect(box.height, inInclusiveRange(17, 22), reason: 'wing to wing $box');
      expect(box.right - a.dx, greaterThan(a.dx - box.left), reason: 'the tip side reaches further');
    });

    test('mirrored to face east, as drawn otherwise; the wheels stand just above the arrow', () async {
      final toy = await _render(); // red on its left half
      const carH = kToyCarWidth * 88 / 160;
      for (final (heading, east) in [(90.0, true), (60.0, true), (270.0, false), (null, false), (180.0, false)]) {
        final pin = await _draw(toy, heading: heading);
        final mid = pin.anchor.dy - kToyWheelLift - carH / 2;
        final left = pin.at(Offset(pin.anchor.dx - kToyCarWidth / 4, mid));
        final right = pin.at(Offset(pin.anchor.dx + kToyCarWidth / 4, mid));
        final redLeft = left.$4 > 200 && left.$1 > 200 && left.$2 < 60;
        final redRight = right.$4 > 200 && right.$1 > 200 && right.$2 < 60;
        expect(redRight, east, reason: 'heading $heading: red on the right = mirrored');
        expect(redLeft, !east, reason: 'heading $heading');
        // The render's bottom edge sits kToyWheelLift above the anchor.
        final under = pin.at(Offset(pin.anchor.dx + (east ? 20 : -20), pin.anchor.dy - kToyWheelLift + 1));
        final inside = pin.at(Offset(pin.anchor.dx + (east ? 20 : -20), pin.anchor.dy - kToyWheelLift - 1));
        expect(inside.$1 > 200 && inside.$2 < 60, isTrue, reason: 'heading $heading: the render reaches down to the wheels line');
        expect(under.$1 > 200 && under.$2 < 60 && under.$4 > 200, isFalse, reason: 'heading $heading: and no further');
      }
    });

    test('no ring: nothing but the soft contact shadow round the anchor beside the arrow', () async {
      final blank = await _render(blank: true);
      final pin = await _draw(blank, heading: 90);
      // Where the old ring's ends were (about 29 px either side), nothing.
      for (final dx in [-29.0, -24.0, 24.0, 29.0]) {
        expect(pin.at(pin.anchor + Offset(dx, 0)).$4, lessThan(20), reason: 'dx $dx');
      }
    });

    for (final dpr in [2.625, 3.0]) {
      for (final night in [false, true]) {
        test('my halo fades out inside the bitmap (${night ? 'night' : 'day'} @${dpr}x)', () async {
          final toy = await _render();
          for (final heading in [null, 0.0, 90.0, 225.0]) {
            final pin = await _draw(toy, heading: heading, color: kRelationMe, me: true, night: night, dpr: dpr);
            expect(pin.maxBorderAlpha(), 0, reason: 'heading $heading');
          }
        });
      }
    }
  });
}
