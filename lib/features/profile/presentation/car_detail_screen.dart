import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/post.dart';
import '../../social/presentation/widgets/masonry_grid.dart';
import '../application/portrait_providers.dart';
import '../application/profile_providers.dart';
import '../domain/car.dart';
import 'widgets/car_documents_section.dart';
import 'widgets/car_mods_section.dart';
import 'widgets/car_portraits_section.dart';
import 'widgets/portrait_style_sheet.dart';

class CarDetailScreen extends ConsumerStatefulWidget {
  const CarDetailScreen({super.key, required this.carId});
  final String carId;

  @override
  ConsumerState<CarDetailScreen> createState() => _CarDetailScreenState();
}

class _CarDetailScreenState extends ConsumerState<CarDetailScreen> {
  int _page = 0;

  Future<void> _delete(Car car) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${car.title}?'),
        content: const Text('This deletes the car, its mods, documents and photos from your garage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    final done = await ref.read(carFormControllerProvider.notifier).delete(car.id);
    if (done && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(carFormControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(next.error!))));
    });
    final car = ref.watch(carProvider(widget.carId));
    final me = ref.watch(currentUserIdProvider);
    final posts = ref.watch(postsWhereProvider((column: 'car_id', value: widget.carId))).value ?? const <FeedPost>[];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(car.value?.title ?? ''),
        actions: [
          if (car.value != null && car.value!.ownerId == me) ...[
            if (ref.watch(portraitsEnabledProvider).value ?? false) IconButton(icon: const Icon(AppIcons.sparkle), tooltip: 'AI portrait', onPressed: () => showPortraitStyleSheet(context, ref, car.value!)),
            IconButton(icon: const Icon(AppIcons.pencilSimple), onPressed: () => context.push(Routes.editCar(car.value!.id))),
            IconButton(icon: const Icon(AppIcons.trash), onPressed: () => _delete(car.value!)),
          ],
        ],
      ),
      body: car.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (c) {
          if (c == null) return const Center(child: Text('This car is no longer in the garage.'));
          final owner = ref.watch(profileProvider(c.ownerId)).value;
          final mine = c.ownerId == me;
          // The portrait (when chosen) leads the hero, then the real photos.
          final pages = [if (c.portraitUrl != null) c.portraitUrl!, ...c.photoUrls];
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: pages.isEmpty
                    ? CarPlaceholder(bodyStyle: c.bodyStyle, padding: 0.12)
                    : Stack(
                        children: [
                          PageView.builder(
                            itemCount: pages.length,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (_, i) => Image(image: CachedNetworkImageProvider(pages[i]), fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray)),
                          ),
                          if (pages.length > 1)
                            Positioned(
                              bottom: 10,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < pages.length; i++)
                                    Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? AppColors.primary : Colors.white70)),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              if (mine && (ref.watch(portraitsEnabledProvider).value ?? false)) Padding(padding: const EdgeInsets.only(top: 14), child: CarPortraitsSection(car: c)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(c.title, style: AppText.sectionTitle)),
                        if (c.year != null)
                          Container(
                            margin: const EdgeInsets.only(left: 8, top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
                            child: Text('${c.year}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    if (c.specLine != null) ...[const SizedBox(height: 4), Text(c.specLine!, style: TextStyle(fontSize: 13, color: AppColors.textSecondary))],
                    if ((c.description ?? '').trim().isNotEmpty) ...[const SizedBox(height: 10), Text(c.description!.trim(), style: const TextStyle(fontSize: 15, height: 1.5))],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        // Only the owner posts about their own car; visitors can Spot it from the feed.
                        if (mine) ...[
                          Expanded(child: SecondaryButton(label: 'Post about it', icon: AppIcons.cameraPlus, onPressed: () => context.push(Routes.createPost(PostKind.post, carId: c.id)))),
                          const SizedBox(width: 8),
                          Expanded(child: PrimaryButton(label: 'Add a mod', onPressed: () => context.push(Routes.newCarMod(c.id)))),
                        ] else
                          Expanded(child: SecondaryButton(label: 'Message owner', icon: AppIcons.chatCircle, onPressed: () => context.push(Routes.profile(c.ownerId)))),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => context.push(Routes.profile(c.ownerId)),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Row(
                        children: [
                          UserAvatar(url: owner?.avatarUrl, name: owner?.displayName ?? owner?.username, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                                children: [
                                  const TextSpan(text: 'In the garage of '),
                                  TextSpan(text: owner?.displayName ?? (owner?.username == null ? '…' : '@${owner!.username}'), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                ],
                              ),
                            ),
                          ),
                          Icon(AppIcons.caretRight, color: AppColors.textMuted),
                        ],
                      ),
                    ),

                    // ---- papers (owner only; RLS keeps them private too)
                    if (mine) ...[
                      const SizedBox(height: 18),
                      CarDocumentsSection(car: c),
                    ],

                    // ---- mods log
                    const SizedBox(height: 18),
                    CarModsSection(car: c, mine: mine),
                  ],
                ),
              ),
              if (posts.isNotEmpty) ...[
                Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text('POSTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary))),
                MasonryGrid(items: posts),
              ],
            ],
          );
        },
      ),
    );
  }
}
