import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/car.dart';
import '../../domain/car_toy.dart';
import '../garage/garage_studio.dart' show HeroToy, StudioColors, TodayChip;
import '../widgets/toy_car_image.dart';

/// The top of the car page, in the garage's language: the dark studio
/// (always night, in light and dark mode alike) with make and year, the
/// model, the toy car on its contact shadow and the paint line. The owner
/// also reads what is happening to the toy (a repaint that failed, or one
/// the daily cap holds back). The page's sheet rides up over its bottom edge.
class CarHero extends StatelessWidget {
  const CarHero({super.key, required this.car, required this.mine, required this.topInset, this.quota, this.onRetryToy, this.onLongPress});

  final Car car;
  final bool mine;

  /// The status bar; the hero runs under it and the top bar.
  final double topInset;

  /// Toy renders left today (owner), for "the new paint goes on after…".
  final ToyQuota? quota;

  /// The owner's "Try again" after a toy or repaint that didn't work.
  final VoidCallback? onRetryToy;

  /// The owner's car menu (long press on the toy, like the garage).
  final VoidCallback? onLongPress;

  /// How far the page's sheet rides up over the studio floor.
  static const sheetOverlap = 24.0;

  /// The top bar's height under the status bar.
  static const barHeight = 56.0;

  /// The toy's width on a page [width] wide.
  static double toyWidthFor(double width) => math.min(width - 32, 460.0) * 0.94;

  @override
  Widget build(BuildContext context) {
    final c = car;
    final ts = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final kicker = [c.make.toUpperCase(), if (c.year != null) '${c.year}'].join(' · ');
    final paint = toyPaintLine(c, mine: mine);
    final note = mine ? _ownerNote(c) : null;
    return LayoutBuilder(
      builder: (context, box) {
        final toyW = toyWidthFor(box.maxWidth);
        return DecoratedBox(
          key: const ValueKey('car-hero'),
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, 0.2),
              radius: 0.95,
              colors: [StudioColors.lift, StudioColors.card, StudioColors.page],
              stops: [0, 0.55, 1],
              transform: _Ellipse(0.7),
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(top: topInset + barHeight + 2, bottom: 16 + sheetOverlap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  kicker,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: ts,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5, height: 1.25, color: StudioColors.textSoft),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  c.model,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: ts,
                                  style: const TextStyle(fontFamily: AppFonts.display, fontSize: 36, fontWeight: FontWeight.w800, height: 1.0, color: StudioColors.text),
                                ),
                              ],
                            ),
                          ),
                          if (c.isDefault) ...[
                            const SizedBox(width: 10),
                            Padding(padding: const EdgeInsets.only(top: 2), child: TodayChip(text: mine ? 'TODAY\'S CAR' : 'DAILY')),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: GestureDetector(
                        onLongPress: onLongPress,
                        child: HeroToy(car: c, width: toyW, mine: mine, active: true),
                      ),
                    ),
                    if (paint != null) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: paint.swatch,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                paint.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textScaler: ts,
                                style: const TextStyle(fontSize: 13, height: 1.3, fontWeight: FontWeight.w600, color: StudioColors.textSoft),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (note != null) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _ToyNote(text: note.text, action: note.retry ? 'Try again' : null, onAction: onRetryToy),
                      ),
                    ],
                  ],
                ),
              ),
              // The sheet's rounded top edge, riding up over the floor.
              Positioned(
                left: 0,
                right: 0,
                bottom: -1,
                height: sheetOverlap + 1,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// What the owner should know about the toy, if anything.
  ({String text, bool retry})? _ownerNote(Car c) {
    if (c.toyPending) return null; // the pill on the toy says it
    if (c.toy == ToyStatus.failed) {
      if (c.toyUrl == null) return (text: 'Your toy car didn\'t come out this time.', retry: true);
      return c.toyPaintStale
          ? (text: 'The new paint didn\'t take. Your toy keeps its old one for now.', retry: true)
          : (text: 'The new toy didn\'t come out. You still have the old one.', retry: true);
    }
    final q = quota;
    if (c.toyPaintWaiting && q != null && q.capped) return (text: toyCapMessage(q), retry: false);
    return null;
  }
}

/// A quiet line on the studio floor, with an optional action.
class _ToyNote extends StatelessWidget {
  const _ToyNote({required this.text, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ts = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: StudioColors.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StudioColors.edge),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text, textScaler: ts, style: const TextStyle(fontSize: 13, height: 1.35, color: StudioColors.textSoft)),
          ),
          if (action != null && onAction != null) ...[
            const SizedBox(width: 10),
            Material(
              color: Colors.white,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(action!, maxLines: 1, textScaler: ts, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: StudioColors.page)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Stretches a radial gradient sideways into a wide ellipse ([ratio] =
/// height over width), like the garage card's glow.
class _Ellipse extends GradientTransform {
  const _Ellipse(this.ratio);
  final double ratio;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final c = bounds.center;
    return Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(1, ratio * bounds.width / bounds.height, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
  }
}
