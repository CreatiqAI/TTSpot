import 'package:flutter/material.dart';

import '../../../../core/theme/app_images.dart';
import '../../domain/car.dart';
import '../../domain/garage_look.dart';
import '../garage/garage_images.dart';

/// Width over height of the toy's box (the renders are about 640 x 350).
const kToyAspect = 16 / 9;

/// A car as its toy model, in a fixed 16:9 box [width] wide, so nothing
/// moves when the toy arrives. In order: the toy render (`toy_url`); while
/// one is being made (`toy_status` pending, or not asked yet on the owner's
/// own car) the cut-out or the cover photo in a rounded frame under a small
/// "Building your toy car…" caption; otherwise (failed, or a visitor's car
/// with no toy) the cut-out, the photo, or the body-type art.
class ToyCarImage extends StatelessWidget {
  const ToyCarImage({super.key, required this.car, required this.width, this.mine = false, this.caption = true, this.semanticLabel});

  final Car car;
  final double width;

  /// The owner's own car: a toy not asked for yet counts as on its way.
  final bool mine;

  /// The "Building your toy car…" caption on the pending fallback (off on
  /// thumbnails).
  final bool caption;
  final String? semanticLabel;

  double get height => width / kToyAspect;

  /// What this car shows: 'toy', 'pending' or 'fallback'.
  static String stateFor(Car car, {required bool mine}) {
    if (garageToyProvider(car) != null) return 'toy';
    final status = toyDemoStatus(car) ?? car.toyStatus;
    if (status == 'pending' || (status == null && mine)) return 'pending';
    return 'fallback';
  }

  @override
  Widget build(BuildContext context) {
    final state = stateFor(car, mine: mine);
    final label = semanticLabel ?? '${car.make} ${car.model}';
    final Widget body;
    if (state == 'toy') {
      body = _Toy(image: garageToyProvider(car)!, label: label);
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
              child: Center(child: _BuildingCaption(scale: (width / 300).clamp(0.6, 1.0))),
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

/// A small dark pill with a band of light sliding over the words.
class _BuildingCaption extends StatefulWidget {
  const _BuildingCaption({required this.scale});
  final double scale;

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
    return Container(
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
          'Building your toy car…',
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
          style: TextStyle(fontSize: 11.5 * s, fontWeight: FontWeight.w600, color: Colors.white, height: 1.2),
        ),
      ),
    );
  }
}

/// Moves a gradient sideways by [dx] px.
class _Slide extends GradientTransform {
  const _Slide(this.dx);
  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(dx, 0, 0);
}
