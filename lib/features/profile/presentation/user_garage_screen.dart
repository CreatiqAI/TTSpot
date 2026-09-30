import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/domain/profile.dart';
import '../../safety/data/safety_repository.dart';
import '../application/garage_providers.dart';
import '../application/profile_providers.dart';
import '../domain/car.dart';
import '../domain/car_mod.dart';

/// "Keith's garage", or plain "Garage" when there is no name to put on it.
String garageTitle(Profile? p) {
  final name = p?.displayName ?? p?.username;
  return name == null ? 'Garage' : '$name\'s garage';
}

/// Someone else's garage, read-only, from the garage row on their profile:
/// every car as a big card (photo, name, the Daily tag, a line on its mods),
/// tap one for its page. Only what anyone may see: `car_mod_list` leaves
/// out private mods and prices, and papers never show here.
class UserGarageScreen extends ConsumerWidget {
  const UserGarageScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(userId)).value;
    final cars = ref.watch(userCarsProvider(userId));
    final blocked = ref.watch(blockedUserIdsProvider).value?.contains(userId) ?? false;

    Future<void> refresh() async {
      for (final c in cars.value ?? const <Car>[]) {
        ref.invalidate(carModsProvider(c.id));
      }
      ref.invalidate(userCarsProvider(userId));
      await ref.read(userCarsProvider(userId).future);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(garageTitle(profile)),
      ),
      body: blocked
          ? const EmptyState(art: AppArt.prohibited, title: 'You blocked this user', subtitle: 'Unblock from their profile to see their cars.')
          : RefreshIndicator(
              onRefresh: refresh,
              child: cars.when(
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: true,
                loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                error: (e, _) => _Scrollable(child: Center(child: Text(friendlyError(e), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)))),
                data: (list) => list.isEmpty
                    ? _Scrollable(
                        child: EmptyState(
                          titi: TitiPose.binoculars,
                          title: 'No cars yet',
                          subtitle: '${profile?.displayName ?? profile?.username ?? 'They'} hasn\'t parked a car here yet.',
                        ),
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.paddingOf(context).bottom + 24),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 28),
                        itemBuilder: (_, i) => _CarCard(car: list[i]),
                      ),
              ),
            ),
    );
  }
}

/// Fills the page but still pulls to refresh.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(constraints: BoxConstraints(minHeight: c.maxHeight), child: child),
        ),
      );
}

/// One car, big: the photo, make and year over the model, then its mods.
/// Labels sit under the photo, never on it.
class _CarCard extends ConsumerWidget {
  const _CarCard({required this.car});
  final Car car;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = car;
    final mods = ref.watch(carModsProvider(c.id));
    final blank = CarPlaceholder(bodyStyle: c.bodyStyle);
    final cover = c.cover;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(Routes.car(c.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: ColoredBox(
                color: AppColors.surfaceGray,
                child: cover == null ? blank : Image(image: CachedNetworkImageProvider(cover), fit: BoxFit.cover, errorBuilder: (_, _, _) => blank),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(
                  [c.make.toUpperCase(), if (c.year != null) '${c.year}'].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: AppColors.textSecondary),
                ),
              ),
              if (c.isDefault) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: const Text('Daily', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            c.model,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: AppFonts.display, fontSize: 26, fontWeight: FontWeight.w800, height: 1.1, color: AppColors.textPrimary),
          ),
          // The line keeps its height while the mods load, so cards don't jump.
          if (!mods.hasError) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(AppIcons.wrench, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    mods.hasValue ? modsSummary(mods.value!) : '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
