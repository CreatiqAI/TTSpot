import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/titi.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/domain/profile.dart';
import '../../safety/data/safety_repository.dart';
import '../application/profile_providers.dart';
import 'garage/garage_body.dart';
import 'garage/garage_studio.dart';

/// "Keith's garage", or plain "Garage" when there is no name to put on it.
String garageTitle(Profile? p) {
  final name = p?.displayName ?? p?.username;
  return name == null ? 'Garage' : '$name\'s garage';
}

/// Someone else's garage, read-only, from the garage row on their profile:
/// the same studio as mine, tap a car for its page. No edit, today's car or
/// add. Only what anyone may see: `car_mod_list` leaves out private mods and
/// prices, and papers never show.
class UserGarageScreen extends ConsumerWidget {
  const UserGarageScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(userId)).value;
    final blocked = ref.watch(blockedUserIdsProvider).value?.contains(userId) ?? false;

    if (blocked) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
          title: Text(garageTitle(profile)),
        ),
        body: const EmptyState(art: AppArt.prohibited, title: 'You blocked this user', subtitle: 'Unblock from their profile to see their cars.'),
      );
    }
    return Scaffold(
      backgroundColor: StudioColors.page,
      body: GarageBody(
        ownerId: userId,
        title: garageTitle(profile),
        onBack: () => context.pop(),
        bottomPadding: MediaQuery.paddingOf(context).bottom + 12,
        empty: GarageEmptyCard(
          pose: TitiPose.binoculars,
          title: 'No cars yet',
          subtitle: '${profile?.displayName ?? profile?.username ?? 'They'} hasn\'t parked a car here yet.',
        ),
      ),
    );
  }
}
