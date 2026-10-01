import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/car.dart';

/// The garage's fixed night palette: the bay and the card deck are always a
/// dark garage, in light and dark mode alike.
abstract final class GarageColors {
  static const wallTop = Color(0xFF1C1F26);
  static const wallMid = Color(0xFF15171C);
  static const wallBottom = Color(0xFF0E0F12);
  static const floorTop = Color(0xFF202329);
  static const floorBottom = Color(0xFF121318);
  static const deckCenter = Color(0xFF1D2027);
  static const deckEdge = Color(0xFF0A0B0E);
  static const bayLine = Color(0xFFE8B400);
  static const tube = Color(0xFFEAF2FF);
  static const text = Color(0xFFF3F4F6);
  static const textSoft = Color(0xFF9AA0AA);
  static const chip = Color(0xC70A0B0E); // rgba(10,11,14,.78)
  static const button = Color(0x8C0C0D10); // rgba(12,13,16,.55)

  /// Brushed silver frame of a collector card.
  static const silver = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF6F7F9), Color(0xFFB9BFC9), Color(0xFFF6F7F9), Color(0xFF9AA2AE)],
    stops: [0, 0.38, 0.58, 1],
  );
}

/// Width over height of a collector card (252 x 370 in the concept).
const kCollectorAspect = 252 / 370;

/// The member's own cover photo (never the AI portrait), else the portrait,
/// decoded at about the size a card shows it.
ImageProvider? garagePhotoProvider(Car car, {int decodeWidth = 820}) {
  final url = car.photoCover ?? car.portraitUrl;
  if (url == null) return null;
  return ResizeImage(CachedNetworkImageProvider(url), width: decodeWidth, policy: ResizeImagePolicy.fit);
}

/// A car's cut-out, as stored (already sized for the bay).
ImageProvider? garageCutoutProvider(Car car) => car.cutoutUrl == null ? null : CachedNetworkImageProvider(car.cutoutUrl!);

/// "01", "02"…
String bayNumber(int index) => (index + 1).toString().padLeft(2, '0');

/// A car as a silver-framed collector card: the member's real photo, a
/// "BAY 0n" notch, the TODAY tag on today's car, the name plate and a small
/// TT Spot logo. [sheen] (0–1, null for none) slides a band of light across
/// it, following the finger or the phone's tilt.
class CollectorCard extends StatelessWidget {
  const CollectorCard({super.key, required this.car, required this.index, required this.width, this.today = false, this.sheen, this.showBay = true, this.shadow = true});

  final Car car;
  final int index;
  final double width;
  final bool today;
  final ValueListenable<double>? sheen;
  /// The "BAY 0n" notch (off where the bay number is already on the wall).
  final bool showBay;
  /// Off for the reflection on the floor.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final s = width / 252;
    final h = width / kCollectorAspect;
    final photo = garagePhotoProvider(car);
    final innerRadius = BorderRadius.circular(15 * s);
    // The card is artwork: text may grow a little with the system size, not
    // so much that the plate covers the car.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Container(
        width: width,
        height: h,
        padding: EdgeInsets.all(8 * s),
        decoration: BoxDecoration(
          gradient: GarageColors.silver,
          borderRadius: BorderRadius.circular(22 * s),
          boxShadow: shadow ? [BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 30 * s, offset: Offset(0, 18 * s))] : null,
        ),
        child: ClipRRect(
          borderRadius: innerRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF111111)),
              if (photo != null)
                Image(
                  image: photo,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => CarPlaceholder(bodyStyle: car.bodyStyle, padding: 0.18),
                )
              else
                CarPlaceholder(bodyStyle: car.bodyStyle, padding: 0.18),
              // Night falls over the bottom so the plate reads on any photo.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: (h - 16 * s) * 0.46,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00050608), Color(0xEB050608)],
                      stops: [0, 0.7],
                    ),
                  ),
                ),
              ),
              if (showBay)
                Positioned(
                left: 10 * s,
                top: 10 * s,
                child: _Tag(text: 'BAY ${bayNumber(index)}', color: GarageColors.chip, scale: s, spacing: 2),
              ),
              if (today)
                Positioned(
                  right: 10 * s,
                  top: 10 * s,
                  child: _Tag(text: 'TODAY', color: AppColors.brand, scale: s, spacing: 1),
                ),
              Positioned(
                left: 14 * s,
                right: 14 * s,
                bottom: 14 * s,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            car.make.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11 * s, fontWeight: FontWeight.w700, letterSpacing: 2 * s, color: const Color(0xFFC7CCD4)),
                          ),
                          SizedBox(height: 2 * s),
                          Text(
                            car.model,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: AppFonts.display, fontSize: 30 * s, fontWeight: FontWeight.w800, height: 1, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8 * s),
                    Opacity(
                      opacity: 0.85,
                      child: Image.asset('assets/brand/logo_dark.png', width: 46 * s, filterQuality: FilterQuality.medium),
                    ),
                  ],
                ),
              ),
              if (sheen != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<double>(
                      valueListenable: sheen!,
                      builder: (_, p, _) => DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: const Alignment(-1, -0.5),
                            end: const Alignment(1, 0.5),
                            colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.30), Colors.white.withValues(alpha: 0)],
                            stops: const [0.38, 0.5, 0.62],
                            transform: _Slide((p - 0.5) * 2.2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, required this.scale, required this.spacing});
  final String text;
  final Color color;
  final double scale;
  final double spacing;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8 * scale)),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(fontSize: 11 * scale, fontWeight: FontWeight.w800, letterSpacing: spacing * scale, color: Colors.white, height: 1.1),
        ),
      );
}

/// Slides a gradient sideways by [dx] widths.
class _Slide extends GradientTransform {
  const _Slide(this.dx);
  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(bounds.width * dx, 0, 0);
}
