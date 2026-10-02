import 'dart:typed_data';

// Colour on the map, when the recogniser doesn't say: the dominant paint
// colour of a car photo, mapped to one of the nine map colours (kCarColors:
// red, black, white, grey, silver, blue, yellow, green, orange). Pure Dart:
// test/car_colour_test.

/// The map colour nearest to one pixel.
String carColourBucket(int r, int g, int b) {
  final max = [r, g, b].reduce((a, c) => a > c ? a : c);
  final min = [r, g, b].reduce((a, c) => a < c ? a : c);
  final v = max / 255;
  final delta = max - min;
  final s = max == 0 ? 0.0 : delta / max;
  if (v < 0.2) return 'black';
  if (s < 0.2 || delta < 28) {
    if (v > 0.86) return 'white';
    if (v > 0.62) return 'silver';
    if (v > 0.33) return 'grey';
    return 'black';
  }
  double h;
  if (max == r) {
    h = 60 * (((g - b) / delta) % 6);
  } else if (max == g) {
    h = 60 * ((b - r) / delta + 2);
  } else {
    h = 60 * ((r - g) / delta + 4);
  }
  if (h < 0) h += 360;
  if (h < 14 || h >= 330) return 'red';
  if (h < 40) return 'orange';
  if (h < 68) return 'yellow';
  if (h < 165) return 'green';
  if (h < 265) return 'blue';
  return h < 300 ? 'blue' : 'red'; // purples: nearest of the two
}

const _chromatic = {'red', 'orange', 'yellow', 'green', 'blue'};

/// The car's colour in an RGBA image [width] × [height]: the pixels where a
/// car usually is (the middle, lower half) sorted into map colours. A
/// coloured paint wins when it covers a fair part of that area (roads,
/// tyres, glass and shadows are grey or black); otherwise the commonest of
/// white / silver / grey / black when it clearly leads. Null when unsure.
String? dominantCarColour(Uint8List rgba, int width, int height) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) return null;
  final counts = <String, int>{};
  var total = 0;
  final x0 = (width * 0.15).floor(), x1 = (width * 0.85).ceil();
  final y0 = (height * 0.35).floor(), y1 = (height * 0.85).ceil();
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = (y * width + x) * 4;
      if (rgba[i + 3] < 128) continue; // transparent
      final c = carColourBucket(rgba[i], rgba[i + 1], rgba[i + 2]);
      counts[c] = (counts[c] ?? 0) + 1;
      total++;
    }
  }
  if (total == 0) return null;
  String? best(bool Function(String) where) {
    String? top;
    var n = 0;
    counts.forEach((k, v) {
      if (where(k) && v > n) {
        top = k;
        n = v;
      }
    });
    return top;
  }

  final paint = best(_chromatic.contains);
  if (paint != null && counts[paint]! / total >= 0.2) return paint;
  final plain = best((k) => !_chromatic.contains(k));
  if (plain != null && counts[plain]! / total >= 0.35) return plain;
  return null;
}
