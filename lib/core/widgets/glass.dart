import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Frosted glass surface: blurs what is behind it, tints it white (or ink),
/// adds a hairline edge and a soft top highlight. Use for floating chrome —
/// the tab bar, map controls, sticky bars — never for whole pages.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 22,
    this.dark = false,
    this.padding,
    this.blur = 18,
    this.circle = false,
    this.shadow = true,
  });
  final Widget child;
  final double radius;
  final bool dark;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final bool circle;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final shape = circle ? const CircleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    final fill = dark ? const Color(0xFF14171E).withValues(alpha: 0.62) : Colors.white.withValues(alpha: 0.70);
    final edge = dark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.85);
    final inner = dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: shadow ? [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12), blurRadius: 18, offset: const Offset(0, 6))] : const [],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: ShapeDecoration(color: fill, shape: shape),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: shape,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark ? [Colors.white.withValues(alpha: 0.10), Colors.transparent] : [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.0)],
                  stops: const [0, 0.55],
                ),
              ),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: circle ? CircleBorder(side: BorderSide(color: edge, width: 1)) : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: edge, width: 1)),
              ),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: circle ? CircleBorder(side: BorderSide(color: inner, width: 0.5)) : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: inner, width: 0.5)),
                ),
                child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Squeezes its child while pressed so every tap feels acknowledged.
/// Wraps buttons; does not steal their gestures.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.96, this.enabled = true});
  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: widget.enabled ? (_) => setState(() => _down = true) : null,
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}
