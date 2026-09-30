import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/photo_viewer.dart';
import '../../../../core/widgets/thumb_image.dart';
import '../../application/garage_providers.dart';
import '../../domain/car.dart';
import '../../domain/car_documents.dart';
import '../../domain/car_mod.dart';
import 'car_documents_section.dart';

/// The mods log on the car page: "12 mods · Suspension, Exhaust, Wheels",
/// then one row per mod, newest first. The owner sees prices, private mods
/// (lock) and taps a row to edit; everyone else sees the public ones.
class CarModsSection extends ConsumerWidget {
  const CarModsSection({super.key, required this.car, required this.mine});
  final Car car;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mods = ref.watch(carModsProvider(car.id));
    final list = mods.value ?? const <CarMod>[];
    final spent = list.fold<double>(0, (s, m) => s + (m.cost ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('MODS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary))),
            // Prices never leave the owner's phone (the server hides them from everyone else).
            if (mine && spent > 0) Text('RM ${formatRinggit(spent)} spent', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 6),
        if (list.isNotEmpty) ...[
          Text(modsSummary(list), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final m in list) _ModRow(mod: m, mine: mine),
        ] else if (!mods.isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              mine ? 'Nothing logged yet. Start with the first thing you changed.' : 'Stock, or the owner hasn\'t logged anything yet.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
        if (mine && list.isNotEmpty) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              onPressed: () => context.push(Routes.newCarMod(car.id)),
              icon: const Icon(AppIcons.plus, size: 16),
              label: const Text('Add a mod'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ModRow extends StatelessWidget {
  const _ModRow({required this.mod, required this.mine});
  final CarMod mod;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final shop = mod.shopName;
    final photo = mod.photo;
    return InkWell(
      onTap: mine ? () => context.push(Routes.editCarMod(mod.carId, mod.id)) : (photo == null ? null : () => showPhotoViewer(context, mod.photoUrls)),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: photo == null ? null : () => showPhotoViewer(context, mod.photoUrls),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: photo == null
                      ? ColoredBox(color: AppColors.surfaceGray, child: Icon(mod.category.icon, size: 24, color: AppColors.textPrimary))
                      : ThumbImage(photo, width: 56, height: 56, error: ColoredBox(color: AppColors.surfaceGray, child: Icon(mod.category.icon, size: 24))),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(mod.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.25))),
                      if (mod.isPrivate)
                        Padding(
                          padding: const EdgeInsets.only(left: 6, top: 2),
                          child: Tooltip(message: 'Only you', child: Icon(AppIcons.lock, size: 14, color: AppColors.textMuted)),
                        ),
                      if (mine && mod.cost != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text('RM ${formatRinggit(mod.cost!)}', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${mod.category.label} · ${formatDay(mod.doneOn)}', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  if (shop != null)
                    GestureDetector(
                      onTap: mod.vendorId == null ? null : () => context.push(Routes.partner(mod.vendorId!)),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(mod.vendorId == null ? AppIcons.wrench : AppIcons.storefront, size: 13, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                shop,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: mod.vendorId == null ? AppColors.textSecondary : AppColors.textPrimary,
                                  fontWeight: mod.vendorId == null ? FontWeight.w400 : FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if ((mod.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(mod.description!.trim(), maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.4)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
