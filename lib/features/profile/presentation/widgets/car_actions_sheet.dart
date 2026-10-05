import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../application/portrait_providers.dart';
import '../../application/profile_providers.dart';
import '../../application/toy_hooks.dart';
import '../../domain/car.dart';
import 'portrait_style_sheet.dart';

/// Owner's "…" (or long-press) on a garage car: edit, remake the toy car
/// (when the toy backend is wired in), garage look, portrait, open. Making a
/// car today's car lives in the garage itself.
Future<void> showCarActionsSheet(BuildContext context, WidgetRef ref, Car car) async {
  final remake = ref.read(toyRequesterProvider);
  final action = await showModalBottomSheet<String>(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(AppIcons.pencilSimple), title: const Text('Edit car'), onTap: () => Navigator.pop(ctx, 'edit')),
          if (remake != null)
            ListTile(
              leading: const Icon(AppIcons.sparkle),
              title: const Text('Remake toy car'),
              subtitle: Text(
                car.toyStatus == 'pending' ? 'One is being made now; this starts over' : 'A new toy model from your cover photo',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'toy'),
            ),
          ListTile(
            leading: Icon(car.garageStyle == 'card' ? AppIcons.cards : AppIcons.scissors),
            title: const Text('Garage look'),
            subtitle: Text(garageLookLabel(car), style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(ctx, 'look'),
          ),
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
    case 'toy':
      final messenger = ScaffoldMessenger.of(context);
      try {
        await remake!(car.id);
        messenger.showSnackBar(const SnackBar(content: Text('Making your toy car. It takes a few minutes; the garage updates on its own.')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    case 'look':
      await showGarageLookSheet(context, ref, car);
    case 'portrait':
      await showPortraitStyleSheet(context, ref, car);
    case 'open':
      context.push(Routes.car(car.id));
  }
}

/// "Cut-out" / "Photo card", with why a cut-out shows as a card.
String garageLookLabel(Car car) {
  if (car.garageStyle == 'card') return 'Photo card';
  final cover = car.photoCover;
  if (cover == null) return 'Photo card (add a photo for a cut-out)';
  if (car.cutoutSource == cover && car.cutoutUrl == null) return 'Cut-out (this photo shows as a card)';
  return 'Cut-out';
}

/// Garage look: the car cut out of its cover photo standing in the bay, or
/// its photo card. For when a cut-out came out wrong.
Future<void> showGarageLookSheet(BuildContext context, WidgetRef ref, Car car) async {
  final picked = await showModalBottomSheet<String>(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Garage look', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ),
            GarageLookOption(
              selected: car.garageStyle != 'card',
              icon: AppIcons.scissors,
              title: 'Cut-out',
              subtitle: 'Your car stands in the bay, cut out of its cover photo on your phone.',
              onTap: () => Navigator.pop(ctx, 'auto'),
            ),
            GarageLookOption(
              selected: car.garageStyle == 'card',
              icon: AppIcons.cards,
              title: 'Photo card',
              subtitle: 'The cover photo in a silver frame. Pick this if the cut-out looks wrong.',
              onTap: () => Navigator.pop(ctx, 'card'),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || picked == car.garageStyle || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(carFormControllerProvider.notifier).setGarageStyle(car, picked);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

/// One choice in the garage look picker (also used on the edit page).
class GarageLookOption extends StatelessWidget {
  const GarageLookOption({super.key, required this.selected, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppColors.textPrimary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, height: 1.3, color: AppColors.textSecondary)),
        trailing: selected ? const Icon(AppIcons.checkCircleFill, color: AppColors.brand) : null,
      );
}
