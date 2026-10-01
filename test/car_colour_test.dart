import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/features/profile/domain/car_colour.dart';

/// "Colour on the map" from the photo when the recogniser doesn't say.
void main() {
  group('carColourBucket', () {
    test('paint colours', () {
      expect(carColourBucket(224, 0, 8), 'red'); // brand red
      expect(carColourBucket(160, 20, 30), 'red'); // dark red
      expect(carColourBucket(255, 122, 26), 'orange');
      expect(carColourBucket(245, 197, 24), 'yellow');
      expect(carColourBucket(29, 167, 80), 'green');
      expect(carColourBucket(43, 124, 255), 'blue');
      expect(carColourBucket(20, 40, 110), 'blue'); // navy
    });

    test('whites, silvers, greys and blacks', () {
      expect(carColourBucket(242, 242, 242), 'white');
      expect(carColourBucket(201, 204, 209), 'silver');
      expect(carColourBucket(138, 138, 138), 'grey');
      expect(carColourBucket(27, 27, 27), 'black');
      expect(carColourBucket(40, 10, 10), 'black'); // too dark to be red
    });
  });

  Uint8List image(int w, int h, (int, int, int) Function(int x, int y) at) {
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final (r, g, b) = at(x, y);
        final i = (y * w + x) * 4;
        out[i] = r;
        out[i + 1] = g;
        out[i + 2] = b;
        out[i + 3] = 255;
      }
    }
    return out;
  }

  group('dominantCarColour', () {
    test('a red car on grey tarmac under a blue sky is red', () {
      final img = image(40, 30, (x, y) {
        if (y < 10) return (90, 150, 230); // sky, above the car area
        if (y > 14 && y < 24 && x > 8 && x < 32) return (200, 16, 24); // the car
        return (110, 110, 112); // road
      });
      expect(dominantCarColour(img, 40, 30), 'red');
    });

    test('a white car on dark tarmac is white', () {
      final img = image(40, 30, (x, y) => y > 12 && y < 26 && x > 6 && x < 34 ? (238, 238, 240) : (60, 60, 62));
      expect(dominantCarColour(img, 40, 30), 'white');
    });

    test('a mixed scene with no clear winner is left unset', () {
      final palette = [(242, 242, 242), (27, 27, 27), (138, 138, 138), (201, 204, 209)];
      final img = image(40, 30, (x, y) => palette[(x + y) % 4]);
      expect(dominantCarColour(img, 40, 30), isNull);
    });

    test('bad input is left unset', () {
      expect(dominantCarColour(Uint8List(0), 0, 0), isNull);
      expect(dominantCarColour(Uint8List(10), 4, 4), isNull);
    });
  });
}
