import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../application/portrait_providers.dart';
import '../../domain/car.dart';
import 'portrait_style_sheet.dart';

/// Owner's "…" (or long-press) on a garage card: edit, portrait, open.
/// Making a car today's car lives in the garage itself (tap the card).
Future<void> showCarActionsSheet(BuildContext context, WidgetRef ref, Car car) async {
  final action = await showModalBottomSheet<String>(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(AppIcons.pencilSimple), title: const Text('Edit car'), onTap: () => Navigator.pop(ctx, 'edit')),
          if (ref.read(portraitsEnabledProvider).value ?? false) ListTile(leading: const Icon(AppIcons.sparkle), title: const Text('AI portrait'), subtitle: const Text('Turn a photo into plate-free artwork', style: TextStyle(fontSize: 12)), onTap: () => Navigator.pop(ctx, 'portrait')),
          ListTile(leading: const Icon(AppIcons.car), title: const Text('Open car page'), onTap: () => Navigator.pop(ctx, 'open')),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'edit':
      context.push(Routes.editCar(car.id));
    case 'portrait':
      await showPortraitStyleSheet(context, ref, car);
    case 'open':
      context.push(Routes.car(car.id));
  }
}
