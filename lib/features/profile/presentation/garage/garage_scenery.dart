import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'collector_card.dart';

// The dark garage bay, piece by piece: shared by the garage's roller-door
// stage (garage_bay.dart) and the top of the car page (car_page/car_stage.dart).
// The bay is always night: these colours never follow the app theme.

/// Back wall with panel seams, the epoxy floor from [floorAt] (a fraction of
/// the height) down, and the two yellow bay lines leaning out at the viewer.
class BayBackdrop extends StatelessWidget {
  const BayBackdrop({super.key, this.floorAt = 0.58, this.lineInset = 34});

  /// Where the floor meets the wall, as a fraction of the height.
  final double floorAt;

  /// How far in from each side the yellow lines start, at the bottom edge.
  final double lineInset;

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(painter: _BayPainter(floorAt: floorAt, lineInset: lineInset)));
}

class _BayPainter extends CustomPainter {
  const _BayPainter({required this.floorAt, required this.lineInset});
  final double floorAt;
  final double lineInset;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final all = Offset.zero & size;
    canvas.drawRect(
      all,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GarageColors.wallTop, GarageColors.wallMid, GarageColors.wallBottom],
          stops: [0, 0.58, 1],
        ).createShader(all),
    );
    // Panel seams on the back wall.
    final seam = Paint()..color = Colors.white.withValues(alpha: 0.025);
    for (var x = 0.0; x < w; x += 64) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, h * floorAt), seam);
    }
    // Floor.
    final floor = Rect.fromLTWH(0, h * floorAt, w, h * (1 - floorAt));
    canvas.drawRect(
      floor,
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [GarageColors.floorTop, GarageColors.floorBottom]).createShader(floor),
    );
    canvas.drawRect(Rect.fromLTWH(0, h * floorAt, w, 1), Paint()..color = Colors.white.withValues(alpha: 0.05));
    // Yellow bay lines, leaning out towards the viewer.
    final line = Paint()..color = GarageColors.bayLine.withValues(alpha: 0.55);
    final lineH = h * (1 - floorAt - 0.02);
    final lean = lineH * math.tan(24 * math.pi / 180);
    final a = lineInset, b = lineInset + 4;
    canvas.drawPath(
      Path()
        ..moveTo(a, h)
        ..lineTo(b, h)
        ..lineTo(b + lean, h - lineH)
        ..lineTo(a + lean, h - lineH)
        ..close(),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w - a, h)
        ..lineTo(w - b, h)
        ..lineTo(w - b - lean, h - lineH)
        ..lineTo(w - a - lean, h - lineH)
        ..close(),
      line,
    );
  }

  @override
  bool shouldRepaint(_BayPainter old) => old.floorAt != floorAt || old.lineInset != lineInset;
}

/// The bay's number painted big and outlined on the back wall ("01").
class BayNumber extends StatelessWidget {
  const BayNumber({super.key, required this.text, required this.size});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textScaler: TextScaler.noScaling, // wall art, not reading text
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w800,
          fontSize: size,
          height: 1,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.white.withValues(alpha: 0.09),
        ),
      );
}

/// The ceiling tube, the cold light it spills over the wall and the pool of
/// light on the floor. Fills its stack. [tube] and [wash] (0–1) let the
/// garage flicker it on; the car page keeps both at 1.
class CeilingLight extends StatelessWidget {
  const CeilingLight({super.key, required this.top, this.inset = 50, this.tube = 1, this.wash = 1, this.washCenter = const Alignment(0, -1.05), this.floorPoolHeight});

  /// The tube's distance from the top.
  final double top;

  /// The tube's distance from each side.
  final double inset;
  final double tube;
  final double wash;

  /// Centre of the light spilled over the wall.
  final Alignment washCenter;

  /// Height of the pool of light on the floor; 42 % of the stack when null.
  final double? floorPoolHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: inset,
              right: inset,
              top: top,
              height: 6,
              child: DecoratedBox(decoration: BoxDecoration(color: const Color(0xFF2A2E36), borderRadius: BorderRadius.circular(6))),
            ),
            Positioned(
              left: inset,
              right: inset,
              top: top,
              height: 6,
              child: Opacity(
                opacity: tube.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: GarageColors.tube,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [BoxShadow(color: Color(0x8CC8E1FF), blurRadius: 18, spreadRadius: 6)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (wash * tube.clamp(0.35, 1.0)).clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: washCenter,
                        radius: 0.95,
                        colors: const [Color(0x38D2E4FF), Color(0x00D2E4FF)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: w / 2 - 150,
              width: 300,
              bottom: 0,
              height: floorPoolHeight ?? h * 0.42,
              child: IgnorePointer(
                child: Opacity(
                  opacity: wash.clamp(0.0, 1.0),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, 0.1),
                        radius: 0.6,
                        colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A car cut out of its photo standing on the epoxy: a soft contact shadow
/// under the tyres, the car in a [box]-tall slot whose bottom sits [bottom]
/// above the stack's bottom, and its reflection fading out below. Fills its
/// stack. [wrap] decorates the car itself (the garage's light streak).
class StandingCutout extends StatelessWidget {
  const StandingCutout({
    super.key,
    required this.image,
    required this.stageWidth,
    required this.stageHeight,
    required this.box,
    required this.bottom,
    this.side = 10,
    this.semanticLabel,
    this.onTap,
    this.onLongPress,
    this.wrap,
  });

  final ImageProvider image;
  final double stageWidth;
  final double stageHeight;

  /// Height of the car's slot.
  final double box;

  /// Floor line: the slot's bottom edge, measured from the stack's bottom.
  final double bottom;

  /// Space left and right of the car's slot.
  final double side;
  final String? semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget Function(Widget car)? wrap;

  @override
  Widget build(BuildContext context) {
    final w = stageWidth, h = stageHeight;
    final car = Image(
      image: image,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // Contact shadow under the tyres: a soft ellipse as wide as the car.
        Positioned(
          left: w * 0.1,
          right: w * 0.1,
          bottom: bottom - h * 0.045,
          height: h * 0.09,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.5,
                  colors: [Color(0xB3000000), Color(0x00000000)],
                  stops: [0.35, 1],
                  transform: _Squash(),
                ),
              ),
            ),
          ),
        ),
        // Reflection on the epoxy: the car upside down, fading out fast.
        Positioned(
          left: side,
          right: side,
          top: h - bottom,
          height: box,
          child: IgnorePointer(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
                stops: [0, 0.55],
              ).createShader(r),
              child: Transform.flip(
                flipY: true,
                child: Image(image: image, fit: BoxFit.contain, alignment: Alignment.bottomCenter, gaplessPlayback: true, filterQuality: FilterQuality.medium),
              ),
            ),
          ),
        ),
        Positioned(
          left: side,
          right: side,
          bottom: bottom,
          height: box,
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            child: wrap == null ? car : wrap!(car),
          ),
        ),
      ],
    );
  }
}

/// Stretches a radial gradient to the box's width: a circle becomes an ellipse.
class _Squash extends GradientTransform {
  const _Squash();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final c = bounds.center;
    return Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(bounds.width / bounds.height, 1, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
  }
}

/// A photo as a framed print: brushed silver frame, the picture cropped to
/// fill a fixed mat inside it. Any photo shape (portrait phone shots, wide
/// panoramas) sits neatly; it is never shown raw.
class SilverPrint extends StatelessWidget {
  const SilverPrint({super.key, required this.child, this.frame = 6, this.radius = 16});

  /// What goes in the mat (an Image with BoxFit.cover).
  final Widget child;
  final double frame;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(frame),
        decoration: BoxDecoration(
          gradient: GarageColors.silver,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 30, offset: Offset(0, 18))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(math.max(0, radius - frame + 1)),
          child: ColoredBox(color: GarageColors.wallBottom, child: SizedBox.expand(child: child)),
        ),
      );
}
