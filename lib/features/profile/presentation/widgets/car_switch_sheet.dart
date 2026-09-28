import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../application/profile_providers.dart';
import '../../domain/car.dart';

/// "Which car are you today?" Pick the default: it fronts the profile,
/// drives on the map and goes with you to meets.
Future<void> showCarSwitchSheet(BuildContext context, WidgetRef ref, List<Car> cars) async {
  final picked = await showModalBottomSheet<String>(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('Which car today?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ),
          for (final c in cars)
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 40,
                  child: c.cover == null
                      ? ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.car, size: 18, color: AppColors.textSecondary))
                      : Image(image: CachedNetworkImageProvider(c.cover!), fit: BoxFit.cover),
                ),
              ),
              title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: c.year == null ? null : Text('${c.year}', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              trailing: c.isDefault ? const Icon(AppIcons.checkCircle, color: AppColors.brand) : null,
              onTap: () => Navigator.pop(ctx, c.id),
            ),
          ListTile(
            leading: const SizedBox(width: 56, child: Icon(AppIcons.plus)),
            title: const Text('Add a car', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(ctx, 'new'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  if (picked == 'new') {
    context.push(Routes.newCar);
    return;
  }
  if (cars.any((c) => c.id == picked && c.isDefault)) return;
  try {
    await ref.read(carFormControllerProvider.notifier).setDefault(picked);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

/// Owner's "…" on a garage card: make it the default, or edit.
Future<void> showCarActionsSheet(BuildContext context, WidgetRef ref, Car car) async {
  final action = await showModalBottomSheet<String>(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!car.isDefault)
            ListTile(leading: const Icon(AppIcons.checkCircle), title: const Text('Set as default car'), subtitle: const Text('Fronts your profile and goes with you to meets', style: TextStyle(fontSize: 12)), onTap: () => Navigator.pop(ctx, 'default')),
          ListTile(leading: const Icon(AppIcons.pencilSimple), title: const Text('Edit car'), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(leading: const Icon(AppIcons.car), title: const Text('Open car page'), onTap: () => Navigator.pop(ctx, 'open')),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'default':
      try {
        await ref.read(carFormControllerProvider.notifier).setDefault(car.id);
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    case 'edit':
      context.push(Routes.editCar(car.id));
    case 'open':
      context.push(Routes.car(car.id));
  }
}
