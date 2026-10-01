import 'package:flutter/animation.dart';
import 'package:flutter/services.dart';

/// The garage's swipe: a page position that follows the finger (with a soft
/// pull at either end), then settles on a whole page with a flick or past
/// half-way. Shared by the bay and the card deck so both feel the same.
class GaragePager {
  GaragePager({required TickerProvider vsync, required int index})
      : position = AnimationController.unbounded(vsync: vsync, value: index.toDouble()),
        target = index;

  /// The page position: 1.5 is half-way between the second and third car.
  final AnimationController position;
  int count = 1;
  int _settled = 0;

  /// The page it is on or heading to.
  int target;

  static const _settle = Duration(milliseconds: 520);
  static const _curve = Cubic(0.3, 0.7, 0.2, 1);

  int get page => position.value.round().clamp(0, count - 1);

  void dragStart() {
    position.stop();
    _settled = page;
  }

  /// [pages]: how far the finger moved, in page widths (positive = towards the next car).
  void dragUpdate(double pages) {
    final v = position.value + pages;
    final max = (count - 1).toDouble();
    // Past the first or last car the bay pulls back.
    position.value = v < 0 || v > max ? position.value + pages * 0.3 : v;
  }

  /// [velocity] in page widths per second. Returns the page it settles on.
  int dragEnd(double velocity) {
    final v = position.value;
    int target;
    if (velocity > 0.6) {
      target = v.floor() + 1;
    } else if (velocity < -0.6) {
      target = v.ceil() - 1;
    } else {
      target = v.round();
    }
    target = target.clamp(0, count - 1);
    // One flick moves one car at most.
    target = target.clamp(_settled - 1, _settled + 1).clamp(0, count - 1);
    animateTo(target);
    return target;
  }

  void animateTo(int page) {
    target = page;
    if ((position.value - page).abs() < 0.001) return;
    position.animateTo(page.toDouble(), duration: _settle, curve: _curve);
  }

  void jumpTo(int page) {
    target = page;
    position.value = page.toDouble();
  }

  void dispose() => position.dispose();
}

/// The tick under the thumb when the garage moves to another car.
void garageSwipeHaptic() => HapticFeedback.selectionClick();
