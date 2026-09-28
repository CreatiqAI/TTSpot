import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../application/portrait_providers.dart';
import '../../domain/car.dart';
import '../../domain/portrait_style.dart';
import 'portrait_style_sheet.dart';

/// Owner-only strip on the car page: every portrait of this car, newest
/// first. Pending ones shimmer, ready ones can be made the car picture.
class CarPortraitsSection extends ConsumerWidget {
  const CarPortraitsSection({super.key, required this.car});
  final Car car;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portraits = ref.watch(carPortraitsProvider(car.id)).value ?? const <CarPortrait>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            children: [
              Expanded(child: Text('AI PORTRAITS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary))),
              TextButton.icon(
                onPressed: () => showPortraitStyleSheet(context, ref, car),
                icon: const Icon(AppIcons.sparkle, size: 18),
                label: const Text('New portrait'),
              ),
            ],
          ),
        ),
        if (portraits.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: InkWell(
              onTap: () => showPortraitStyleSheet(context, ref, car),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(AppIcons.sparkle, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Turn a photo into artwork', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('${kPortraitStyles.length} looks, plate blanked, ready in about a minute.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Icon(AppIcons.caretRight, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: portraits.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _PortraitTile(car: car, portrait: portraits[i]),
            ),
          ),
      ],
    );
  }
}

class _PortraitTile extends ConsumerWidget {
  const _PortraitTile({required this.car, required this.portrait});
  final Car car;
  final CarPortrait portrait;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = portrait.style;
    final inUse = portrait.url != null && car.portraitUrl == portrait.url;
    final Widget body = switch (portrait.status) {
      PortraitStatus.pending => Shimmer(
          child: Container(
            color: AppColors.surfaceGray,
            padding: const EdgeInsets.all(12),
            alignment: Alignment.bottomLeft,
            child: Text('Painting your ${car.model}…', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
        ),
      PortraitStatus.failed => Container(
          color: AppColors.surfaceGray,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.warning, size: 20, color: AppColors.danger),
              const Spacer(),
              Text('Didn\'t come out', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(portrait.error ?? 'Try another style.', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
      PortraitStatus.ready => Stack(
          fit: StackFit.expand,
          children: [
            Image(image: CachedNetworkImageProvider(portrait.url!), fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray)),
            if (inUse)
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
                  child: const Text('IN USE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white)),
                ),
              ),
          ],
        ),
    };
    return SizedBox(
      width: 200,
      child: Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: switch (portrait.status) {
            PortraitStatus.pending => null,
            PortraitStatus.failed => () => showPortraitStyleSheet(context, ref, car),
            PortraitStatus.ready => () => _preview(context, ref, inUse: inUse),
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              body,
              if (style != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(999)),
                    child: Text(style.name, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _preview(BuildContext context, WidgetRef ref, {required bool inUse}) async {
    final action = await showModalBottomSheet<String>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image(image: CachedNetworkImageProvider(portrait.url!), fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray)),
                ),
              ),
              const SizedBox(height: 12),
              Text('${car.title} · ${portrait.style?.name ?? portrait.styleId}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (inUse)
                SecondaryButton(label: 'Use the photos instead', icon: AppIcons.images, onPressed: () => Navigator.pop(ctx, 'photos'))
              else
                PrimaryButton(label: 'Use as car picture', onPressed: () => Navigator.pop(ctx, 'use')),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (action == 'use') {
        await ref.read(portraitActionsProvider).choose(portrait);
        messenger.showSnackBar(SnackBar(content: Text('Your ${car.model} now wears the ${portrait.style?.name ?? ''} portrait.')));
      } else if (action == 'photos') {
        await ref.read(portraitActionsProvider).usePhotos(car.id);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
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
