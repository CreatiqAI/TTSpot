import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/features.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/domain/profile.dart';
import '../../friends/application/friends_providers.dart';
import '../../friends/domain/friend.dart';
import '../../points/application/points_providers.dart';
import '../../safety/data/safety_repository.dart';
import '../../safety/presentation/report_sheet.dart';
import '../../social/application/chat_providers.dart';
import '../../social/application/notification_providers.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/post.dart';
import '../../social/presentation/create_hub_sheet.dart';
import '../../social/presentation/story_viewer_screen.dart';
import '../../social/presentation/widgets/masonry_grid.dart';
import '../application/profile_providers.dart';
import 'profile_menu.dart';
import 'widgets/profile_header.dart';
import '../domain/car.dart';

enum _Tab { garage, moments, posts }

/// Garage profile, Instagram profile layout. `userId == null` means "me".
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.userId});
  final String? userId;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  _Tab _tab = _Tab.garage;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final id = widget.userId ?? me;
    final isMe = id != null && id == me;
    if (id == null) return const Scaffold(body: SizedBox.shrink());

    final profile = ref.watch(profileProvider(id));
    final cars = ref.watch(userCarsProvider(id));
    final posts = ref.watch(userPostsProvider(id));
    final moments = ref.watch(userMomentsProvider(id));
    final stats = ref.watch(profileStatsProvider(id)).value;
    final friendCount = ref.watch(friendCountProvider(id)).value;
    final friendship =
        ref.watch(friendshipStatusProvider(id)).value ?? FriendshipStatus.none;
    final badges = ref.watch(earnedBadgesProvider(id)).value ?? const [];
    final streak = ref.watch(ttStreakProvider(id)).value ?? 0;
    final blocked =
        ref.watch(blockedUserIdsProvider).value?.contains(id) ?? false;
    final points = isMe ? (ref.watch(pointsBalanceProvider).value ?? 0) : null;

    Future<void> refresh() async {
      ref.invalidate(profileProvider(id));
      ref.invalidate(userCarsProvider(id));
      ref.invalidate(userPostsProvider(id));
      ref.invalidate(userMomentsProvider(id));
      ref.invalidate(profileStatsProvider(id));
      ref.invalidate(friendCountProvider(id));
      ref.invalidate(friendshipStatusProvider(id));
      ref.invalidate(earnedBadgesProvider(id));
      ref.invalidate(ttStreakProvider(id));
      await ref.read(profileProvider(id).future);
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.userId == null
            ? null
            : IconButton(
                icon: const Icon(AppIcons.arrowLeft),
                onPressed: () => context.pop(),
              ),
        title: Text(
          profile.value?.username == null ? '' : '@${profile.value!.username}',
        ),
        actions: [
          if (isMe) ...[
            IconButton(
              tooltip: 'Scan',
              icon: const Icon(AppIcons.scan),
              onPressed: () => context.push(Routes.scan),
            ),
            IconButton(
              tooltip: 'Create',
              icon: const Icon(AppIcons.plusCircle),
              onPressed: () => showCreateHub(context),
            ),
            IconButton(
              tooltip: 'Menu',
              icon: const Icon(AppIcons.list),
              onPressed: () => showProfileMenu(context, ref),
            ),
          ] else if (profile.value != null)
            IconButton(
              icon: const Icon(AppIcons.dotsThreeVertical),
              onPressed: () => _otherMenu(context, profile.value!, blocked),
            ),
        ],
      ),
      body: profile.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(
          child: Text(
            friendlyError(e),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        data: (p) {
          if (p == null) return const Center(child: Text('This profile doesn\'t exist.'));
          return RefreshIndicator(
            onRefresh: refresh,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ProfileHeader(
                    profile: p,
                    isMe: isMe,
                    cars: cars.value ?? const <Car>[],
                    stats: stats,
                    friendCount: friendCount,
                    points: points,
                    streak: streak,
                    badges: badges,
                    friendship: friendship,
                    onMeets: () => context.push(Routes.meets),
                    onFriends: isMe ? () => context.push(Routes.friends) : null,
                    onPoints: () => context.push(Routes.points),
                    onBadges: () => context.push(Routes.badges(id)),
                    onEdit: () => context.push(Routes.editProfile),
                    onAddCar: () => context.push(Routes.newCar),
                    onFriendAction: () => _friendAction(id, friendship, p.displayName ?? '@${p.username}'),
                    onMessage: () => _message(id),
                  ),
                ),
                if (isMe)
                  SliverToBoxAdapter(
                    child: ProfileQuickActions(
                      points: points ?? 0,
                      onPoints: () => context.push(Routes.points),
                      onRewards: () => context.push(Routes.rewards),
                      onVouchers: () => context.push(Routes.myVouchers),
                      onQr: () => context.push(Routes.myQr),
                      onScan: () => context.push(Routes.scan),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: ProfileTabs(
                    tabs: [
                      (AppIcons.garage, 'Garage'),
                      (AppIcons.camera, 'Moments'),
                      if (kSocialFeed) (AppIcons.squaresFour, 'Posts'),
                    ],
                    selected: _tab.index,
                    onSelect: (i) => setState(() => _tab = _Tab.values[i]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    ),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, ?current],
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(blocked ? 'blocked' : _tab),
                      child: blocked
                          ? const _Fill(
                              child: EmptyState(
                                art: AppArt.prohibited,
                                title: 'You blocked this user',
                                subtitle: 'Unblock from the menu to see their garage.',
                              ),
                            )
                          : switch (_tab) {
                              _Tab.garage => _garageSliver(cars, isMe),
                              _Tab.moments => _momentsSliver(moments, isMe),
                              _Tab.posts => _postsSliver(posts, isMe),
                            },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _garageSliver(AsyncValue<List<Car>> cars, bool isMe) {
    return cars.when(
      loading: () => const _Fill(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => _Fill(
        child: Center(child: Text(friendlyError(e))),
      ),
      data: (list) => list.isEmpty
          ? _Fill(
              child: EmptyState(
                art: AppArt.car,
                title: isMe ? 'Your garage is empty' : 'No cars yet',
                subtitle: isMe
                    ? 'Add your daily, your project, your weekend toy.'
                    : 'Nothing parked here so far.',
                actionLabel: isMe ? 'Add your first car' : null,
                onAction: isMe ? () => context.push(Routes.newCar) : null,
              ),
            )
          : _Grid(
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 1.5,
                  crossAxisSpacing: 1.5,
                ),
                itemCount: list.length,
                itemBuilder: (_, i) => _CarTile(
                  car: list[i],
                  onTap: () => context.push(Routes.car(list[i].id)),
                ),
              ),
            ),
    );
  }

  Widget _postsSliver(AsyncValue<List<dynamic>> posts, bool isMe) {
    return posts.when(
      loading: () => const _Fill(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => _Fill(
        child: Center(child: Text(friendlyError(e))),
      ),
      data: (list) => list.isEmpty
          ? _Fill(
              child: EmptyState(
                art: AppArt.camera,
                title: isMe ? 'No posts yet' : 'No posts',
                subtitle: isMe
                    ? 'Share your ride, a spotted, a poll or a guide.'
                    : 'Nothing shared so far.',
                actionLabel: isMe ? 'Create a post' : null,
                onAction: isMe ? () => showCreateHub(context) : null,
              ),
            )
          : MasonryGrid(items: list.cast()),
    );
  }

  Widget _momentsSliver(AsyncValue<List<Story>> moments, bool isMe) {
    return moments.when(
      loading: () => const _Fill(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => _Fill(
        child: Center(child: Text(friendlyError(e))),
      ),
      data: (list) => list.isEmpty
          ? _Fill(
              child: EmptyState(
                art: AppArt.camera,
                title: isMe ? 'No moments yet' : 'No moments',
                subtitle: isMe
                    ? 'Snap one at a meet. It stays in that meet\'s album.'
                    : 'Nothing kept so far.',
                actionLabel: isMe ? 'Add a moment' : null,
                onAction: isMe
                    ? () => context.push(Routes.createMoment())
                    : null,
              ),
            )
          : _Grid(
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 1.5,
                  crossAxisSpacing: 1.5,
                  childAspectRatio: 0.8,
                ),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final m = list[i];
                  return GestureDetector(
                    onTap: () {
                      final author = m.author;
                      if (author == null) return;
                      context.push(
                        Routes.stories,
                        extra: StoryViewerArgs(
                          groups: [
                            StoryGroup(
                              author: author,
                              stories: [m],
                              allSeen: true,
                            ),
                          ],
                          initialGroup: 0,
                        ),
                      );
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          m.photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: AppColors.surfaceGray),
                        ),
                        if (m.whereLabel != null)
                          Positioned(
                            left: 6,
                            right: 6,
                            bottom: 6,
                            child: Text(
                              m.whereLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(blurRadius: 6, color: Colors.black),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  Future<void> _friendAction(
    String id,
    FriendshipStatus status,
    String name,
  ) async {
    final actions = ref.read(friendActionsProvider);
    try {
      switch (status) {
        case FriendshipStatus.none:
          final s = await actions.add(id);
          _snack(
            s == FriendshipStatus.friends
                ? 'You\'re now friends.'
                : 'Request sent.',
          );
        case FriendshipStatus.pendingIn:
          await actions.accept(id);
          _snack('You\'re now friends.');
        case FriendshipStatus.pendingOut:
          await actions.decline(id); // cancels my own request (delete)
          await actions.remove(id);
        case FriendshipStatus.friends:
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Remove $name?'),
              content: const Text('You\'ll stop seeing each other on the map.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Remove',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          );
          if (ok == true) await actions.remove(id);
      }
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _message(String id) async {
    try {
      final conv = await ref.read(chatActionsProvider).openDm(id);
      if (mounted) context.push(Routes.chat(conv));
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _otherMenu(BuildContext context, Profile p, bool blocked) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AppIcons.flag),
              title: const Text('Report profile'),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
            ListTile(
              leading: Icon(
                blocked ? AppIcons.checkCircle : AppIcons.prohibit,
                color: AppColors.danger,
              ),
              title: Text(
                blocked ? 'Unblock' : 'Block',
                style: const TextStyle(color: AppColors.danger),
              ),
              onTap: () => Navigator.pop(ctx, blocked ? 'unblock' : 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    final name = p.displayName ?? '@${p.username}';
    switch (action) {
      case 'report':
        await showReportSheet(
          context,
          target: ReportTarget.profile,
          targetId: p.id,
        );
      case 'block':
        await confirmBlockUser(context, ref, userId: p.id, displayName: name);
      case 'unblock':
        final me = ref.read(currentUserIdProvider);
        if (me == null) return;
        try {
          await ref
              .read(safetyRepositoryProvider)
              .unblock(blockerId: me, blockedId: p.id);
          ref.invalidate(blockedUserIdsProvider);
        } catch (e) {
          if (context.mounted) _snack(friendlyError(e));
        }
    }
  }
}

// ---------------------------------------------------------------- pieces ---

class _CarTile extends StatelessWidget {
  const _CarTile({required this.car, required this.onTap});
  final Car car;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (car.cover != null)
            Image.network(
              car.cover!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: AppColors.surfaceGray),
            )
          else
            const ColoredBox(
              color: AppColors.surfaceGray,
              child: Center(child: ArtIcon(AppArt.car, size: 44)),
            ),
          if (car.photoUrls.length > 1)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(AppIcons.images, size: 16, color: Colors.white),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x99000000)],
                ),
              ),
              child: Text(
                car.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Box-sized stand-in for the old SliverFillRemaining so tab bodies can animate.
class _Fill extends StatelessWidget {
  const _Fill({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(height: 380, child: child);
}

class _Grid extends StatelessWidget {
  const _Grid({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
