import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/features/profile/domain/car_recognition.dart';
import 'package:car_meet/features/profile/domain/plate_geometry.dart';

/// Check the plate's box editing: every box stays inside the photo, never
/// shrinks below the minimum, and moves / resizes the way a finger expects.
void expectBox(PlateBox b, double x0, double y0, double x1, double y1) {
  expect(b.x0, closeTo(x0, 1e-9), reason: 'x0');
  expect(b.y0, closeTo(y0, 1e-9), reason: 'y0');
  expect(b.x1, closeTo(x1, 1e-9), reason: 'x1');
  expect(b.y1, closeTo(y1, 1e-9), reason: 'y1');
}

void expectInside(PlateBox b) {
  expect(b.x0, greaterThanOrEqualTo(0));
  expect(b.y0, greaterThanOrEqualTo(0));
  expect(b.x1, lessThanOrEqualTo(1 + 1e-9));
  expect(b.y1, lessThanOrEqualTo(1 + 1e-9));
  expect(b.x1, greaterThan(b.x0));
  expect(b.y1, greaterThan(b.y0));
}

void main() {
  const plate = PlateBox(0.4, 0.7, 0.6, 0.8);

  group('move', () {
    test('drags by the finger, keeping the size', () {
      expectBox(plate.moved(0.1, -0.2), 0.5, 0.5, 0.7, 0.6);
    });

    test('stops at every edge without shrinking', () {
      expectBox(plate.moved(5, 5), 0.8, 0.9, 1.0, 1.0);
      expectBox(plate.moved(-5, -5), 0.0, 0.0, 0.2, 0.1);
    });

    test('centredAt puts the box on a tap, clamped near an edge', () {
      expectBox(plate.centredAt(0.5, 0.5), 0.4, 0.45, 0.6, 0.55);
      expectBox(plate.centredAt(0.99, 0.01), 0.8, 0.0, 1.0, 0.1);
    });
  });

  group('resize', () {
    test('a corner moves, the opposite corner stays put', () {
      expectBox(plate.dragCorner(PlateCorner.bottomRight, 0.1, 0.05), 0.4, 0.7, 0.7, 0.85);
      expectBox(plate.dragCorner(PlateCorner.topLeft, -0.1, -0.1), 0.3, 0.6, 0.6, 0.8);
      expectBox(plate.dragCorner(PlateCorner.topRight, 0.05, -0.05), 0.4, 0.65, 0.65, 0.8);
      expectBox(plate.dragCorner(PlateCorner.bottomLeft, -0.05, 0.05), 0.35, 0.7, 0.6, 0.85);
    });

    test('a corner dragged past its opposite stops at the minimum size', () {
      final b = plate.dragCorner(PlateCorner.bottomRight, -1, -1);
      expect(b.x0, closeTo(0.4, 1e-9));
      expect(b.y0, closeTo(0.7, 1e-9));
      expect(b.width, closeTo(kMinPlateW, 1e-9));
      expect(b.height, closeTo(kMinPlateH, 1e-9));
    });

    test('a corner cannot leave the photo', () {
      expectBox(plate.dragCorner(PlateCorner.bottomRight, 3, 3), 0.4, 0.7, 1.0, 1.0);
      expectBox(plate.dragCorner(PlateCorner.topLeft, -3, -3), 0.0, 0.0, 0.6, 0.8);
    });

    test('pinch scales about the centre', () {
      expectBox(plate.scaled(2), 0.3, 0.65, 0.7, 0.85);
      expectBox(plate.scaled(0.5), 0.45, 0.725, 0.55, 0.775);
    });

    test('pinch never goes below the minimum or past the photo', () {
      final tiny = plate.scaled(0.001);
      expect(tiny.width, closeTo(kMinPlateW, 1e-9));
      expect(tiny.height, closeTo(kMinPlateH, 1e-9));
      expect(tiny.cx, closeTo(plate.cx, 1e-9));
      final huge = plate.scaled(100);
      expectBox(huge, 0, 0, 1, 1);
      expectInside(plate.scaled(double.nan));
    });

    test('a box near an edge stays inside when it grows', () {
      const edge = PlateBox(0.85, 0.9, 0.95, 0.98);
      final b = edge.scaled(3);
      expectInside(b);
      expect(b.width, closeTo(0.3, 1e-9));
    });
  });

  group('normalized', () {
    test('swapped corners are put in order', () {
      expectBox(const PlateBox(0.6, 0.8, 0.4, 0.7).normalized(), 0.4, 0.7, 0.6, 0.8);
    });

    test('a sliver grows to the minimum around its centre', () {
      final b = const PlateBox(0.5, 0.5, 0.5, 0.5).normalized();
      expect(b.width, closeTo(kMinPlateW, 1e-9));
      expect(b.height, closeTo(kMinPlateH, 1e-9));
      expect(b.cx, closeTo(0.5, 1e-9));
      expect(b.cy, closeTo(0.5, 1e-9));
    });

    test('out-of-range corners end up inside', () {
      expectInside(const PlateBox(-0.2, 0.9, 0.3, 1.4).normalized());
    });
  });

  group('recogniser box', () {
    test('padded a quarter of its width and a third of its height', () {
      final b = blurBoxFromDetection(const PlateBox(0.4, 0.7, 0.6, 0.8));
      expectBox(b, 0.35, 0.665, 0.65, 0.835);
    });

    test('padding stops at the photo edge', () {
      final b = blurBoxFromDetection(const PlateBox(0.0, 0.9, 0.2, 1.0));
      expect(b.x0, 0);
      expect(b.y1, closeTo(1, 1e-9));
      expectInside(b);
    });
  });

  group('default and next box', () {
    test('the default sits low in the middle, plate-shaped', () {
      final b = defaultPlateBox(aspect: 4 / 3);
      expect(b.cx, closeTo(0.5, 1e-9));
      expect(b.cy, closeTo(0.72, 1e-9));
      // 4:1 in pixels on a 4:3 photo.
      expect((b.width * 4) / (b.height * 3), closeTo(4, 1e-6));
      expectInside(defaultPlateBox(aspect: 0.5));
      expectInside(defaultPlateBox(aspect: 3));
      expectInside(defaultPlateBox(aspect: double.nan));
    });

    test('Add another blur never lands on a box already there', () {
      final boxes = <PlateBox>[defaultPlateBox(aspect: 4 / 3)];
      for (var i = 0; i < 3; i++) {
        final next = nextPlateBox(boxes, aspect: 4 / 3);
        expectInside(next);
        for (final b in boxes) {
          expect(next.overlaps(b), isFalse, reason: 'box ${boxes.length} overlaps');
        }
        boxes.add(next);
      }
      expect(boxes.length, kMaxPlateBoxes);
    });

    test('the next box is sized like the last one and goes where asked', () {
      const first = PlateBox(0.1, 0.1, 0.2, 0.15);
      final next = nextPlateBox([first], aspect: 4 / 3, cx: 0.7, cy: 0.3);
      expect(next.width, closeTo(first.width, 1e-9));
      expect(next.height, closeTo(first.height, 1e-9));
      expect(next.cx, closeTo(0.7, 1e-9));
      expect(next.cy, closeTo(0.3, 1e-9));
    });

    test('with nothing there yet it is the default box', () {
      final b = nextPlateBox(const [], aspect: 4 / 3);
      final d = defaultPlateBox(aspect: 4 / 3);
      expectBox(b, d.x0, d.y0, d.x1, d.y1);
    });
  });

  test('contains and overlaps', () {
    expect(plate.contains(0.5, 0.75), isTrue);
    expect(plate.contains(0.65, 0.75), isFalse);
    expect(plate.contains(0.65, 0.75, slopX: 0.06), isTrue);
    expect(plate.overlaps(const PlateBox(0.55, 0.75, 0.9, 0.9)), isTrue);
    expect(plate.overlaps(const PlateBox(0.6, 0.7, 0.8, 0.8)), isFalse); // touching edges only
  });
}
