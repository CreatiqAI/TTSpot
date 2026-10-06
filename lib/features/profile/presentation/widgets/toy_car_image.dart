import 'package:flutter/material.dart';

import '../../../../core/theme/app_images.dart';
import '../../../map/presentation/widgets/car_marker.dart' show kCarColors, kCarColorLabels;
import '../../domain/car.dart';
import '../../domain/car_toy.dart';
import '../../domain/garage_look.dart';
import '../garage/garage_images.dart';

/// Width over height of the toy's box (the renders are about 640 x 350).
const kToyAspect = 16 / 9;

/// The pill on the owner's toy while a new paint goes on.
const kRepaintingCaption = 'Repainting your toy car… about 2 minutes';

/// The pill while a new toy is made from a new cover photo.
const kRemakingCaption = 'Making your new toy car… about 2 minutes';

/// A car as its toy model, in a fixed 16:9 box [width] wide, so nothing
/// moves when the toy arrives. In order: the toy render (`toy_url`); while
/// one is being made (`toy_status` pending, or not asked yet on the owner's
/// own car) the cut-out or the cover photo in a rounded frame under a small
/// "Building your toy car…" caption; otherwise (failed, or a visitor's car
/// with no toy) the cut-out, the photo, or the body-type art. On the owner's
/// own car, a toy being repainted (or remade from a new cover) stays on show,
/// dimmed, under "Repainting your toy car… about 2 minutes".
class ToyCarImage extends StatelessWidget {
  const ToyCarImage({super.key, required this.car, required this.width, this.mine = false, this.caption = true, this.semanticLabel});

  final Car car;
  final double width;

  /// The owner's own car: a toy not asked for yet counts as on its way, and
  /// a repaint shows as one.
  final bool mine;

  /// The "Building your toy car…" caption on the pending fallback (off on
  /// thumbnails).
  final bool caption;
  final String? semanticLabel;

  double get height => width / kToyAspect;

  /// What this car shows: 'toy', 'repainting', 'pending' or 'fallback'.
  static String stateFor(Car car, {required bool mine}) {
    if (garageToyProvider(car) != null) {
      return mine && !toyDemoOn && car.toyPending ? 'repainting' : 'toy';
    }
    final status = toyDemoStatus(car) ?? car.toyStatus;
    // No photo: no toy is coming, so nothing says one is.
    if (status == 'pending' || (status == null && mine && car.photoCover != null)) return 'pending';
    return 'fallback';
  }

  @override
  Widget build(BuildContext context) {
    final state = stateFor(car, mine: mine);
    final label = semanticLabel ?? '${car.make} ${car.model}';
    final Widget body;
    if (state == 'toy') {
      body = _Toy(image: garageToyProvider(car)!, label: label);
    } else if (state == 'repainting') {
      body = Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: 0.45, child: _Toy(image: garageToyProvider(car)!, label: label)),
          if (caption)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: _BuildingCaption(
                  scale: (width / 300).clamp(0.6, 1.0),
                  maxWidth: width * 0.94,
                  text: car.toyPaintStale ? kRepaintingCaption : kRemakingCaption,
                ),
              ),
            ),
        ],
      );
    } else {
      body = Stack(
        fit: StackFit.expand,
        children: [
          _Fallback(car: car, width: width, label: label),
          if (state == 'pending' && caption)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(child: _BuildingCaption(scale: (width / 300).clamp(0.6, 1.0), maxWidth: width * 0.94)),
            ),
        ],
      );
    }
    return SizedBox(width: width, height: height, child: body);
  }
}

/// The toy itself, fading in as it decodes.
class _Toy extends StatelessWidget {
  const _Toy({required this.image, required this.label});
  final ImageProvider image;
  final String label;

  @override
  Widget build(BuildContext context) => Image(
        image: image,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        semanticLabel: label,
        frameBuilder: (context, child, frame, syncLoaded) {
          if (syncLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
}

/// The cut-out (made from the current cover), else the cover photo in a
/// rounded frame, else the body-type art.
class _Fallback extends StatelessWidget {
  const _Fallback({required this.car, required this.width, required this.label});
  final Car car;
  final double width;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cut = garageLookFor(car) == GarageLook.cutout ? garageCutoutProvider(car) : null;
    if (cut != null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: width * 0.04, vertical: width * 0.02),
        child: Image(image: cut, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.medium, semanticLabel: label, errorBuilder: (_, _, _) => _art()),
      );
    }
    final photo = garagePhotoProvider(car);
    if (photo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular((width * 0.06).clamp(8.0, 20.0)),
        child: ColoredBox(
          color: const Color(0xFF1A1D24),
          child: Image(image: photo, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium, semanticLabel: label, errorBuilder: (_, _, _) => _art()),
        ),
      );
    }
    return _art();
  }

  Widget _art() => Padding(
        padding: EdgeInsets.symmetric(horizontal: width * 0.08, vertical: width * 0.03),
        child: Image.asset(carPlaceholderAsset(car.bodyStyle), fit: BoxFit.contain, filterQuality: FilterQuality.medium, semanticLabel: label, errorBuilder: (_, _, _) => const SizedBox.shrink()),
      );
}

/// A small dark pill with a band of light sliding over the words. Shrinks to
/// fit [maxWidth] rather than wrap or overflow at large text sizes.
class _BuildingCaption extends StatefulWidget {
  const _BuildingCaption({required this.scale, required this.maxWidth, this.text = 'Building your toy car…'});
  final double scale;
  final double maxWidth;
  final String text;

  @override
  State<_BuildingCaption> createState() => _BuildingCaptionState();
}

class _BuildingCaptionState extends State<_BuildingCaption> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 5 * s),
          decoration: BoxDecoration(
            color: const Color(0xCC07080B),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => LinearGradient(
                colors: const [Color(0xFF9AA0AA), Colors.white, Color(0xFF9AA0AA)],
                stops: const [0.35, 0.5, 0.65],
                transform: _Slide((_ctrl.value * 2.6 - 1.3) * r.width),
              ).createShader(r),
              child: child,
            ),
            child: Text(
              widget.text,
              maxLines: 1,
              softWrap: false,
              textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
              style: TextStyle(fontSize: 11.5 * s, fontWeight: FontWeight.w600, color: Colors.white, height: 1.2),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line under a toy: its paint. The owner reads the paint they picked
/// ("Blue paint", "Repainting in Blue…" while it goes on, "Blue paint is
/// next" while the daily cap holds it back); visitors read the paint of the
/// toy they see. Null when no colour was picked (the toy keeps the photo's).
({Color swatch, String text})? toyPaintLine(Car car, {required bool mine}) {
  final key = mine || car.toyUrl == null ? car.paint : (car.toyPaint ?? car.paint);
  if (key == null) return null;
  final name = kCarColorLabels[key] ?? key;
  final swatch = kCarColors[key] ?? const Color(0xFFB0B4BC);
  if (mine && car.toyRepainting) return (swatch: swatch, text: 'Repainting in $name…');
  if (mine && car.toyPaintWaiting) {
    return (swatch: swatch, text: car.toy == ToyStatus.failed ? 'The $name repaint didn\'t work' : '$name paint is next');
  }
  return (swatch: swatch, text: '$name paint');
}

/// Moves a gradient sideways by [dx] px.
class _Slide extends GradientTransform {
  const _Slide(this.dx);
  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(dx, 0, 0);
}
