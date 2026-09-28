import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../application/portrait_providers.dart';
import '../../domain/car.dart';
import '../../domain/portrait_style.dart';

/// "Which look?" Grid of the 8 portrait styles. Tapping one books the job and
/// returns straight away; the car page shows it painting.
Future<void> showPortraitStyleSheet(BuildContext context, WidgetRef ref, Car car) async {
  if (car.photoUrls.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a photo of the car first. The portrait is painted from it.')));
    return;
  }
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
            Text('Paint your ${car.model}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Same car, plate blanked, in a look you pick. Takes about a minute; you can leave and come back.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(portraitActionsProvider).request(car.id, picked.id);
    messenger.showSnackBar(SnackBar(content: Text('Painting your ${car.model} in ${picked.name}. We\'ll ping you when it\'s ready.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
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
