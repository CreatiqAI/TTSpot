import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Phone motion without a plugin: a tiny EventChannel backed by
/// SensorManager on Android and CMMotionManager on iOS (see MainActivity.kt
/// and AppDelegate.swift). Values are the accelerometer in g, including
/// gravity, at about 50 Hz while someone listens.
class Motion {
  static const _channel = EventChannel('my.ttspot.app/motion');
  static Stream<Accel>? _stream;

  /// Broadcast stream of accelerometer samples. Empty on platforms without
  /// the native side (web, desktop) so callers can subscribe blindly.
  static Stream<Accel> get accelerometer => _stream ??= _channel
      .receiveBroadcastStream()
      .map((e) {
        final l = (e as List).cast<num>();
        return Accel(l[0].toDouble(), l[1].toDouble(), l[2].toDouble());
      })
      .handleError((_) {}, test: (e) => e is MissingPluginException || e is PlatformException)
      .asBroadcastStream();
}

class Accel {
  const Accel(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
  double get magnitude => math.sqrt(x * x + y * y + z * z);
}

/// Counts shakes: a spike in acceleration well above gravity, then a rest.
/// [threshold] is in g (a firm shake peaks around 2.5–3 g; walking stays
/// under 1.5). Each shake fires [onShake] once, at most every [cooldown].
class ShakeDetector {
  ShakeDetector({required this.onShake, this.threshold = 2.4, this.cooldown = const Duration(milliseconds: 550)});
  final void Function() onShake;
  final double threshold;
  final Duration cooldown;
  StreamSubscription<Accel>? _sub;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void start() {
    _sub ??= Motion.accelerometer.listen((a) {
      if (a.magnitude < threshold) return;
      final now = DateTime.now();
      if (now.difference(_last) < cooldown) return;
      _last = now;
      onShake();
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}

/// Smoothed tilt of the phone as an offset in [-1, 1] (x: left/right,
/// y: towards/away), for parallax that follows the hand.
class TiltTracker {
  TiltTracker({this.smoothing = 0.12});
  final double smoothing;
  final _out = StreamController<Offset>.broadcast();
  StreamSubscription<Accel>? _sub;
  Offset _cur = Offset.zero;

  Stream<Offset> get stream => _out.stream;

  void start() {
    _sub ??= Motion.accelerometer.listen((a) {
      // Portrait, held upright: x is roll, (z - 0.6) is pitch away from the usual viewing angle.
      final target = Offset((-a.x).clamp(-1.0, 1.0), ((a.z - 0.55) * 1.6).clamp(-1.0, 1.0));
      _cur = Offset.lerp(_cur, target, smoothing)!;
      _out.add(_cur);
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    stop();
    _out.close();
  }
}

/// Escalating buzzes for a three-step reveal, on the haptics Flutter ships
/// with (no vibration plugin): one tap, a double, then a long heavy rumble.
abstract final class Buzz {
  static Future<void> step(int n) async {
    switch (n) {
      case 1:
        await HapticFeedback.mediumImpact();
      case 2:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 110));
        await HapticFeedback.heavyImpact();
      default:
        for (var i = 0; i < 5; i++) {
          await HapticFeedback.heavyImpact();
          await Future<void>.delayed(const Duration(milliseconds: 70));
        }
    }
  }

  /// Legendary: a long roll that tails off.
  static Future<void> rumble() async {
    for (var i = 0; i < 8; i++) {
      await (i < 5 ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact());
      await Future<void>.delayed(Duration(milliseconds: 60 + i * 20));
    }
  }
}
