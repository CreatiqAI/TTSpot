import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/titi.dart';
import '../../../core/widgets/glass_tab_bar.dart';
import 'garage/garage_body.dart';
import 'garage/garage_studio.dart';

/// The signed-in member's garage on Home (Garage tab): the studio card with
/// the car's toy, the other cars' thumbnails, the numbers and buttons above
/// the tab bar. The full-screen twin is [MyGarageScreen].
class GarageHomeTab extends ConsumerWidget {
  const GarageHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    if (me == null) return const SizedBox.shrink();
    return GarageBody(
      ownerId: me,
      title: 'My garage',
      // The buttons stay clear of the floating tab bar.
      bottomPadding: GlassTabBar.clearance(context),
      empty: const GarageEmpty(),
    );
  }
}

/// Full-screen garage, opened from My garage on the profile.
class MyGarageScreen extends ConsumerWidget {
  const MyGarageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    return Scaffold(
      backgroundColor: StudioColors.page,
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

/// No cars yet: TiTi with a camera and the Add button, on a studio card.
class GarageEmpty extends StatelessWidget {
  const GarageEmpty({super.key});

  @override
  Widget build(BuildContext context) => GarageEmptyCard(
        pose: TitiPose.camera,
        title: 'Park your first car',
        subtitle: 'Your daily, your project, your weekend toy. Today\'s car shows on the map and goes with you to meets.',
        actionLabel: 'Add a car',
        onAction: () => context.push(Routes.newCar),
      );
}
