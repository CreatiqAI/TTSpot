import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Soft light trails: two or three thin streaks, brand red and cool white,
/// crossing a band diagonally, heavily blurred and dim. The one motion
/// background the owner kept (dots and stars were rejected). Put it in a
/// band of its own, never behind text or fields: it is colour, not content.
///
/// Cheap by design: one [CustomPainter] under a [RepaintBoundary], blur from
/// a [ui.MaskFilter] on the stroke (no saveLayer, no BackdropFilter), one
/// [AnimationController] that follows [TickerMode] (so it pauses when its
/// route is not on top) and stands still when the system asks for no motion
/// ([MediaQuery.disableAnimations]).
class LightTrails extends StatefulWidget {
  const LightTrails({super.key, this.opacity = 0.34, this.tilt = -12, this.blur = 6, this.streaks = _defaultStreaks});

  /// Overall strength; the mockup sits at 0.34.
  final double opacity;
  /// Band rotation in degrees (negative = rising to the right).
  final double tilt;
  /// Blur radius in logical pixels.
  final double blur;
  final List<LightStreak> streaks;

  static const _defaultStreaks = [
    LightStreak(y: 0.18, duration: Duration(milliseconds: 4500), red: true),
    LightStreak(y: 0.50, duration: Duration(milliseconds: 3400), delay: Duration(seconds: 1), red: false),
    LightStreak(y: 0.82, duration: Duration(milliseconds: 5500), delay: Duration(seconds: 2), red: true),
  ];

  @override
  State<LightTrails> createState() => _LightTrailsState();
}

/// One streak: where it sits in the band (0..1 of the height), how long one
/// crossing takes, and when it first sets off.
class LightStreak {
  const LightStreak({required this.y, required this.duration, this.delay = Duration.zero, required this.red});
  final double y;
  final Duration duration;
  final Duration delay;
  final bool red;
}

class _LightTrailsState extends State<LightTrails> with SingleTickerProviderStateMixin {
  // One long clock; every streak derives its own phase from it, so a single
  // ticker drives the whole band.
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60));

  @override
  void initState() {
    super.initState();
    _clock.repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _clock.isAnimating) {
      // A fixed frame with every streak somewhere in view.
      _clock.stop();
      _clock.value = 0.35;
    } else if (!still && !_clock.isAnimating) {
      _clock.repeat();
    }
    return RepaintBoundary(
      child: ClipRect(
        child: CustomPaint(
          painter: _TrailsPainter(clock: _clock, opacity: widget.opacity, tilt: widget.tilt, blur: widget.blur, streaks: widget.streaks),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _TrailsPainter extends CustomPainter {
  _TrailsPainter({required this.clock, required this.opacity, required this.tilt, required this.blur, required this.streaks}) : super(repaint: clock);
  final AnimationController clock;
  final double opacity;
  final double tilt;
  final double blur;
  final List<LightStreak> streaks;

  static const _red = AppColors.brand;
  static const _redTip = Color(0xFFFF8A8E);
  static const _cool = Color(0xFF9DB8FF);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final seconds = clock.value * 60;
    // The band is wider than the box (-30 % each side) and tilted, so the
    // streaks enter and leave past the edges.
    final bandW = size.width * 1.6;
    final left = -size.width * 0.3;
    final streakLen = bandW * 0.45;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(tilt * math.pi / 180);
    canvas.translate(-size.width / 2, -size.height / 2);
    final paint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, blur);
    for (final s in streaks) {
      final t = seconds - s.delay.inMilliseconds / 1000;
      if (t < 0) continue;
      // CSS: translateX(-120 %) → translateX(420 %) of the streak's own width.
      final phase = (t / (s.duration.inMilliseconds / 1000)) % 1;
      final x0 = left + streakLen * (-1.2 + 5.4 * phase);
      final y = size.height * s.y;
      final tail = s.red ? _red : _cool;
      final tip = s.red ? _redTip : Colors.white;
      paint.shader = ui.Gradient.linear(
        Offset(x0, y),
        Offset(x0 + streakLen, y),
        [tail.withValues(alpha: 0), tail.withValues(alpha: opacity), tip.withValues(alpha: opacity)],
        const [0, 0.6, 1],
      );
      canvas.drawLine(Offset(x0, y), Offset(x0 + streakLen, y), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrailsPainter old) =>
      old.clock != clock || old.opacity != opacity || old.tilt != tilt || old.blur != blur || old.streaks != streaks;
}
