import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/widgets/glass_tab_bar.dart';
import '../application/profile_providers.dart';
import 'garage/garage_body.dart';

/// The signed-in member's garage on Home (Garage tab): the roller-door bay
/// or the card deck (Bay ⇄ Cards in the title row), swipe between cars,
/// the car's panel underneath. The full-screen twin is [MyGarageScreen].
class GarageHomeTab extends ConsumerWidget {
  const GarageHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    if (me == null) return const SizedBox.shrink();
    final count = ref.watch(userCarsProvider(me)).value?.length ?? 0;
    return GarageBody(
      ownerId: me,
      // Clear of the floating tab bar so the buttons can scroll into view.
      bottomPadding: GlassTabBar.clearance(context),
      empty: const GarageEmpty(),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 6, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                count > 1 ? 'MY GARAGE · $count CARS' : 'MY GARAGE',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: AppColors.textPrimary),
              ),
            ),
            if (count > 0) const GarageViewToggle(),
            IconButton(tooltip: 'Add a car', icon: const Icon(AppIcons.plus), onPressed: () => context.push(Routes.newCar)),
          ],
        ),
      ),
    );
  }
}

/// Full-screen garage, opened from My garage on the profile.
class MyGarageScreen extends ConsumerWidget {
  const MyGarageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final count = me == null ? 0 : ref.watch(userCarsProvider(me)).value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('My garage'),
        actions: [
          if (count > 0) const GarageViewToggle(),
          IconButton(tooltip: 'Add a car', icon: const Icon(AppIcons.plus), onPressed: () => context.push(Routes.newCar)),
          const SizedBox(width: 4),
        ],
      ),
      body: me == null
          ? const SizedBox.shrink()
          : GarageBody(ownerId: me, bottomPadding: MediaQuery.paddingOf(context).bottom + 24, empty: const GarageEmpty()),
    );
  }
}

/// No cars yet: TiTi with a camera and the Add button.
class GarageEmpty extends StatelessWidget {
  const GarageEmpty({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        child: Column(
          children: [
            const Titi(TitiPose.camera, height: 150),
            const SizedBox(height: 18),
            const Text('Park your first car', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Your daily, your project, your weekend toy. Today\'s car shows on the map and goes with you to meets.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: FilledButton(
                onPressed: () => context.push(Routes.newCar),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  backgroundColor: AppColors.textPrimary,
                  foregroundColor: AppColors.onInk,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                child: const Text('Add a car'),
              ),
            ),
          ],
        ),
      );
}
