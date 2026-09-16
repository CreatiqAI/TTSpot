import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../social/application/community_providers.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/club.dart';
import '../../social/domain/post.dart';
import '../../social/presentation/widgets/masonry_grid.dart';
import '../application/profile_providers.dart';
import '../domain/car.dart';

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
        content: const Text('This deletes the car, its build log and its photos from your garage.'),
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
    final mods = ref.watch(carModsProvider(widget.carId)).value ?? const <CarMod>[];
    final posts = ref.watch(postsWhereProvider((column: 'car_id', value: widget.carId))).value ?? const <FeedPost>[];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(car.value?.title ?? ''),
        actions: [
          if (car.value != null && car.value!.ownerId == me) ...[
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
          final total = mods.fold<double>(0, (s, m) => s + (m.cost ?? 0));
          final showSpend = mine || c.showSpend;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: c.photoUrls.isEmpty
                    ? ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(AppArt.car, size: 120)))
                    : Stack(
                        children: [
                          PageView.builder(
                            itemCount: c.photoUrls.length,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (_, i) => Image.network(c.photoUrls[i], fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray)),
                          ),
                          if (c.photoUrls.length > 1)
                            Positioned(
                              bottom: 10,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < c.photoUrls.length; i++)
                                    Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? AppColors.primary : Colors.white70)),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
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
                    if ((c.description ?? '').trim().isNotEmpty) ...[const SizedBox(height: 10), Text(c.description!.trim(), style: const TextStyle(fontSize: 15, height: 1.5))],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        // Only the owner posts about their own car; visitors can Spot it from the feed.
                        if (mine) ...[
                          Expanded(child: SecondaryButton(label: 'Post about it', icon: AppIcons.cameraPlus, onPressed: () => context.push(Routes.createPost(PostKind.post, carId: c.id)))),
                          const SizedBox(width: 8),
                          Expanded(child: PrimaryButton(label: 'Log a mod', onPressed: () => context.push(Routes.newCarMod(c.id)))),
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
                    const SizedBox(height: 18),

                    // ---- build log
                    Row(
                      children: [
                        Expanded(child: Text('BUILD LOG', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary))),
                        if (showSpend && total > 0)
                          Text('RM ${_money(total)} spent', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        if (mine)
                          IconButton(
                            tooltip: c.showSpend ? 'Hide total from others' : 'Show total to others',
                            icon: Icon(c.showSpend ? AppIcons.eye : AppIcons.eyeSlash, size: 20),
                            onPressed: () => ref.read(communityActionsProvider).setShowSpend(c.id, !c.showSpend),
                          ),
                      ],
                    ),
                    if (mods.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(mine ? 'Nothing logged yet. Start with what you did first.' : 'Stock, or the owner hasn\'t logged anything yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                      )
                    else
                      for (var i = 0; i < mods.length; i++) _ModRow(mod: mods[i], last: i == mods.length - 1, showCost: showSpend, mine: mine, carId: c.id),
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

  static String _money(double v) {
    final s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
  }
}

class _ModRow extends ConsumerWidget {
  const _ModRow({required this.mod, required this.last, required this.showCost, required this.mine, required this.carId});
  final CarMod mod;
  final bool last;
  final bool showCost;
  final bool mine;
  final String carId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onLongPress: !mine
          ? null
          : () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Remove "${mod.title}"?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
                  ],
                ),
              );
              if (ok == true) {
                try {
                  await ref.read(communityActionsProvider).deleteMod(carId, mod.id);
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
                }
              }
            },
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle)),
                  if (!last) Expanded(child: Container(width: 1.5, color: AppColors.border)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(mod.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                        if (showCost && mod.cost != null) Text('RM ${_CarDetailScreenState._money(mod.cost!)}', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Text(formatDate(mod.doneOn), style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    if ((mod.description ?? '').trim().isNotEmpty) ...[const SizedBox(height: 4), Text(mod.description!.trim(), style: const TextStyle(fontSize: 14, height: 1.4))],
                    if (mod.photoUrls.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 72,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final u in mod.photoUrls)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(u, width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 72))),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
