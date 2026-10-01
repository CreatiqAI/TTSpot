import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/widgets/glass_tab_bar.dart';
import 'garage/garage_body.dart';

/// The signed-in member's garage on Home (Garage tab): the roller-door bay
/// or the card deck filling the tab, the top bar (Bay ⇄ Cards, add) floating
/// over it and the car's panel above the tab bar. The full-screen twin is
/// [MyGarageScreen].
class GarageHomeTab extends ConsumerWidget {
  const GarageHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    if (me == null) return const SizedBox.shrink();
    return GarageBody(
      ownerId: me,
      title: 'My garage',
      // The panel's buttons stay clear of the floating tab bar.
      bottomPadding: GlassTabBar.clearance(context),
      empty: const GarageEmpty(),
    );
  }
}

/// Full-screen garage, opened from My garage on the profile: the bay from
/// edge to edge, under the status bar.
class MyGarageScreen extends ConsumerWidget {
  const MyGarageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    return Scaffold(
      body: me == null
          ? const SizedBox.shrink()
          : GarageBody(
              ownerId: me,
              title: 'My garage',
              onBack: () => context.pop(),
              bottomPadding: MediaQuery.paddingOf(context).bottom + 12,
              empty: const GarageEmpty(),
            ),
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
