import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/sheet_header.dart';
import '../../../points/application/points_providers.dart';
import '../../application/portrait_providers.dart';
import '../../domain/car.dart';
import '../../domain/portrait_style.dart';

/// "Which look?" Grid of the 8 portrait styles, then a confirm sheet with the
/// price in points. Generate books the job (the server takes the points) and
/// returns straight away; the car page shows it painting.
Future<void> showPortraitStyleSheet(BuildContext context, WidgetRef ref, Car car) async {
  final messenger = ScaffoldMessenger.of(context);
  if (car.photoUrls.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Add a photo of the car first. The portrait is painted from it.')));
    return;
  }
  // Fresh switch and price: an admin may have changed either since the page opened.
  ref.invalidate(portraitSettingsProvider);
  final settings = await ref.read(portraitSettingsProvider.future);
  if (!context.mounted) return;
  if (!settings.enabled) {
    messenger.showSnackBar(const SnackBar(content: Text('AI portraits are paused right now. Try again later.')));
    return;
  }
  ref.invalidate(pointsBalanceProvider); // the confirm sheet shows a fresh balance
  final picked = await showModalBottomSheet<PortraitStyle>(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader(title: 'Paint your ${car.model}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Same car, plate blanked, in a look you pick. ${settings.cost > 0 ? '${settings.cost} points each. ' : ''}Takes about a minute; you can leave and come back.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.05),
                itemCount: kPortraitStyles.length,
                itemBuilder: (_, i) => PortraitStyleTile(style: kPortraitStyles[i], onTap: () => Navigator.pop(ctx, kPortraitStyles[i])),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  final go = await showModalBottomSheet<bool>(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    builder: (_) => _ConfirmPortraitSheet(car: car, style: picked, cost: settings.cost),
  );
  if (go != true || !context.mounted) return;
  try {
    await ref.read(portraitActionsProvider).request(car.id, picked.id);
    messenger.showSnackBar(SnackBar(content: Text('Painting your ${car.model} in ${picked.name}. We\'ll ping you when it\'s ready.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

/// "Uses 300 points · you have 1,240", then Generate / Cancel. With too few
/// points Generate stays off and the sheet points to how to earn more.
class _ConfirmPortraitSheet extends ConsumerWidget {
  const _ConfirmPortraitSheet({required this.car, required this.style, required this.cost});
  final Car car;
  final PortraitStyle style;
  final int cost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(pointsBalanceProvider);
    final have = balance.value;
    final enough = cost <= 0 || (have != null && have >= cost);
    final short = have == null ? 0 : cost - have;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(width: 88, height: 66, child: _Tint(style: style)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${style.name} portrait', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('Your ${car.model}. ${style.description}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Row(
                children: [
                  const PointsCoin(size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                        children: [
                          TextSpan(text: cost > 0 ? 'Uses ${_n(cost)} points' : 'Free right now', style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: ' · you have ${have == null ? '…' : _n(have)}', style: TextStyle(color: enough ? AppColors.textSecondary : AppColors.danger)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!enough && have != null) ...[
              const SizedBox(height: 10),
              Text('You need ${_n(short)} more points. Check in at meets and spots to earn them.', style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.danger)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.pop(context, false);
                    router.push(Routes.points);
                  },
                  child: const Text('How to earn points'),
                ),
              ),
            ] else if (cost > 0) ...[
              const SizedBox(height: 8),
              Text('If it doesn\'t come out, you get the points back.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 16),
            PrimaryButton(label: 'Generate', loading: balance.isLoading && have == null, onPressed: enough ? () => Navigator.pop(context, true) : null),
            const SizedBox(height: 8),
            SecondaryButton(label: 'Cancel', onPressed: () => Navigator.pop(context, false)),
          ],
        ),
      ),
    );
  }

  static String _n(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// One style in the grid: tinted placeholder (or the curated reference when
/// we have one), name and one-line description.
class PortraitStyleTile extends StatelessWidget {
  const PortraitStyleTile({super.key, required this.style, required this.onTap});
  final PortraitStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ref = style.referenceUrl;
    return Material(
      color: AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: ref != null
                    ? Image(image: CachedNetworkImageProvider(ref), fit: BoxFit.cover, errorBuilder: (_, _, _) => _Tint(style: style))
                    : _Tint(style: style),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(style.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(style.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, height: 1.3, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tint extends StatelessWidget {
  const _Tint({required this.style});
  final PortraitStyle style;

  @override
  Widget build(BuildContext context) {
    final t = style.tint;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(t, Colors.white, 0.18)!, t, Color.lerp(t, Colors.black, 0.28)!],
        ),
      ),
      child: Stack(
        children: [
          Positioned(right: -10, bottom: -14, child: Icon(AppIcons.car, size: 84, color: Colors.white.withValues(alpha: 0.14))),
          Positioned(left: 10, top: 10, child: Icon(style.icon, size: 22, color: Colors.white.withValues(alpha: 0.92))),
        ],
      ),
    );
  }
}
