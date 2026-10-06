import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/car.dart';
import '../../domain/portrait_style.dart';
import '../widgets/portrait_style_sheet.dart' show PortraitSampleImage;
import 'car_build_tab.dart' show DashedButton;
import 'car_page_model.dart';

/// The Portraits section: the owner's portraits still painting (or failed
/// this week), the finished ones two to a row (the one the car wears is
/// marked), and, with none yet, "Make it look pro" or a plain button.
/// Visitors see the portrait the car wears.
class CarPortraitsSection extends StatelessWidget {
  const CarPortraitsSection({super.key, required this.data, required this.imageFor, required this.onOpen, required this.onNew, required this.onDismissPromo});

  final CarPageData data;
  final CarImageResolver imageFor;
  final void Function(CarPortraitMedia portrait, List<CarPortraitMedia> all) onOpen;
  final VoidCallback onNew;
  final VoidCallback onDismissPromo;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final portraits = carPortraitsFor(d.car, portraits: d.portraits);
    final news = d.portraitNews;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (news.isNotEmpty) PortraitNews(car: d.car, portraits: news, onRetry: onNew),
        if (portraits.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _PortraitGrid(portraits: portraits, imageFor: imageFor, onOpen: (p) => onOpen(p, portraits)),
          )
        else if (d.showPromo)
          MakeItLookProCard(car: d.car, cost: d.portraitCost, onPaint: onNew, onDismiss: onDismissPromo)
        else if (d.mine && d.portraitsEnabled && news.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DashedButton(label: '+ New AI portrait', onTap: onNew),
          ),
      ],
    );
  }
}

class _PortraitGrid extends StatelessWidget {
  const _PortraitGrid({required this.portraits, required this.imageFor, required this.onOpen});
  final List<CarPortraitMedia> portraits;
  final CarImageResolver imageFor;
  final ValueChanged<CarPortraitMedia> onOpen;

  @override
  Widget build(BuildContext context) {
    const gap = 6.0;
    final single = portraits.length == 1;
    final rows = <Widget>[];
    for (var i = 0; i < portraits.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
          child: Row(
            children: [
              Expanded(child: _PortraitTile(p: portraits[i], imageFor: imageFor, onTap: () => onOpen(portraits[i]), wide: single)),
              if (!single) ...[
                const SizedBox(width: gap),
                Expanded(
                  child: i + 1 < portraits.length
                      ? _PortraitTile(p: portraits[i + 1], imageFor: imageFor, onTap: () => onOpen(portraits[i + 1]))
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _PortraitTile extends StatelessWidget {
  const _PortraitTile({required this.p, required this.imageFor, required this.onTap, this.wide = false});
  final CarPortraitMedia p;
  final CarImageResolver imageFor;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final ts = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2);
    return Semantics(
      button: true,
      label: p.wearing ? '${p.label}, on the car' : p.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: wide ? 16 / 10 : 3 / 2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: AppColors.surfaceGray),
                Image(
                  image: ResizeImage(imageFor(p.url), width: 720, policy: ResizeImagePolicy.fit),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => Icon(AppIcons.imageBroken, color: AppColors.textMuted),
                ),
                // A soft shade at the bottom so the name reads on any picture.
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x99000000)]),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 6,
                  child: Row(
                    children: [
                      const Icon(AppIcons.sparkle, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          p.style?.name ?? 'Portrait',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: ts,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                if (p.wearing)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Text(
                        'ON THE CAR',
                        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Make it look pro": three real samples and the Paint button, for an
/// owner whose car has no portrait yet. The X hides it for this car on this
/// phone.
class MakeItLookProCard extends StatelessWidget {
  const MakeItLookProCard({super.key, required this.car, required this.cost, required this.onPaint, required this.onDismiss});
  final Car car;
  final int cost;
  final VoidCallback onPaint;
  final VoidCallback onDismiss;

  static const _samples = ['night_city', 'golden_hour', 'race_poster'];

  @override
  Widget build(BuildContext context) {
    final price = cost > 0 ? ' · $cost points' : '';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF15171C), Color(0xFF2A1215)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('MAKE IT LOOK PRO', style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w800, height: 1.05, color: Colors.white)),
                    const SizedBox(height: 3),
                    Text('Your own ${car.model}, painted in a style you pick.', style: TextStyle(fontSize: 13, height: 1.3, color: Colors.white.withValues(alpha: 0.75))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Hide this',
                child: GestureDetector(
                  onTap: onDismiss,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.12)),
                    child: const Icon(AppIcons.x, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < _samples.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 1.6,
                      child: PortraitSampleImage(style: PortraitStyle.byId(_samples[i])!, cacheWidth: 360),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: onPaint,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            child: Text('Paint my ${car.model}$price', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// The owner's portraits still painting, and ones that failed this week
/// (points back, try again).
class PortraitNews extends StatelessWidget {
  const PortraitNews({super.key, required this.car, required this.portraits, required this.onRetry});
  final Car car;
  final List<CarPortrait> portraits;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: Column(
        children: [
          for (final p in portraits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.surfaceGray,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: p.isPending ? null : onRetry,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: p.isPending
                                ? Shimmer(child: ColoredBox(color: AppColors.border))
                                : ColoredBox(color: AppColors.danger.withValues(alpha: 0.12), child: const Icon(AppIcons.warning, size: 20, color: AppColors.danger)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.isPending ? 'Painting your ${car.model}…' : '${p.style?.name ?? 'The portrait'} didn\'t come out',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.isPending
                                    ? '${p.style?.name ?? 'Your portrait'}, ready in about a minute. We\'ll ping you.'
                                    : (p.refunded ? 'Your ${p.pointsSpent} points are back. Tap to try again.' : (p.error ?? 'Tap to try another style.')),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (!p.isPending) ...[
                          const SizedBox(width: 8),
                          Icon(AppIcons.arrowsClockwise, size: 18, color: AppColors.textSecondary),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A soft light sweep across [child], for things still being made.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) => Stack(
        fit: StackFit.expand,
        children: [
          child!,
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1.5 + 3 * _c.value, -0.3),
                  end: Alignment(-0.5 + 3 * _c.value, 0.3),
                  colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: AppColors.dark ? 0.10 : 0.55), Colors.white.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
