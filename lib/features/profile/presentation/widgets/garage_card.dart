import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/car.dart';

/// One car in the garage list: photo, make and model, year, Default badge.
/// Quiet on purpose: the photo does the talking.
class GarageCard extends StatelessWidget {
  const GarageCard({super.key, required this.car, required this.onTap, this.onMore});
  final Car car;
  final VoidCallback onTap;
  /// Owner only: opens the Set as default / Edit sheet.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final cover = car.cover;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cover != null)
                  Image(image: CachedNetworkImageProvider(cover), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())
                else
                  Center(child: Icon(AppIcons.car, size: 40, color: AppColors.textMuted)),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.62)], stops: const [0.45, 1]),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(car.make.toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: Colors.white70)),
                            Text(car.model, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                          ],
                        ),
                      ),
                      if (car.year != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                          child: Text('${car.year}', style: const TextStyle(fontFamily: AppFonts.display, fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink, height: 1)),
                        ),
                    ],
                  ),
                ),
                if (car.isDefault)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
                      child: const Text('DEFAULT', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white)),
                    ),
                  ),
                if (onMore != null)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: IconButton(
                      onPressed: onMore,
                      icon: const Icon(AppIcons.dotsThree, color: Colors.white),
                      style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.28)),
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

/// Dashed "add a car" tile at the end of the owner's garage.
class AddCarTile extends StatelessWidget {
  const AddCarTile({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: OutlinedButton.icon(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), side: BorderSide(color: AppColors.border), foregroundColor: AppColors.textPrimary),
          icon: const Icon(AppIcons.plus, size: 18),
          label: const Text('Add a car'),
        ),
      );
}
