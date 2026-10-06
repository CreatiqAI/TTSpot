import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/titi.dart';
import 'garage/garage_body.dart';
import 'garage/garage_studio.dart';

/// My garage, full screen: opened from My garage on the profile (and
/// /garage). It was also a Home tab until 0.3.55, when Clubs & Events took
/// that place.
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
