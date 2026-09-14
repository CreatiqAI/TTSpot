import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/features.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../accounts/presentation/account_switcher.dart';
import '../../accounts/presentation/account_title.dart';
import '../../auth/application/onboarding_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/profile.dart';
import '../../friends/application/friends_providers.dart';
import '../../friends/domain/friend.dart';
import '../../points/application/points_providers.dart';
import '../../safety/data/safety_repository.dart';
import '../../safety/presentation/report_sheet.dart';
import '../../social/application/chat_providers.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/post.dart';
import '../../social/presentation/create_hub_sheet.dart';
import '../../social/presentation/story_viewer_screen.dart';
import '../../social/presentation/widgets/masonry_grid.dart';
import '../application/profile_providers.dart';
import '../domain/car.dart';
import 'profile_menu.dart';
import 'widgets/profile_header.dart';

enum _Tab { posts, garage, saved }

/// Profile: identity on top, moments, then Posts · Garage · Saved.
/// `userId == null` means "me".
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.userId});
  final String? userId;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  _Tab _tab = _Tab.posts;
  bool _liked = false; // Saved tab: saved (false) or liked (true)

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final id = widget.userId ?? me;
    final isMe = id != null && id == me;
    if (id == null) return const Scaffold(body: SizedBox.shrink());

    final profile = ref.watch(profileProvider(id));
    final cars = ref.watch(userCarsProvider(id));
    final posts = ref.watch(userPostsProvider(id));
    final moments = ref.watch(userMomentsProvider(id)).value ?? const <Story>[];
    final stats = ref.watch(profileStatsProvider(id)).value;
    final friendCount = ref.watch(friendCountProvider(id)).value;
    final friendship = ref.watch(friendshipStatusProvider(id)).value ?? FriendshipStatus.none;
    final blocked = ref.watch(blockedUserIdsProvider).value?.contains(id) ?? false;
    final points = isMe ? (ref.watch(pointsBalanceProvider).value ?? 0) : null;
    final tabs = [
      (AppIcons.squaresFour, 'Posts'),
      (AppIcons.garage, 'Garage'),
      if (isMe) (AppIcons.bookmarkSimple, 'Saved'),
    ];

    Future<void> refresh() async {
      ref.invalidate(profileProvider(id));
      ref.invalidate(userCarsProvider(id));
      ref.invalidate(userPostsProvider(id));
      ref.invalidate(userMomentsProvider(id));
      ref.invalidate(profileStatsProvider(id));
      ref.invalidate(friendCountProvider(id));
      ref.invalidate(friendshipStatusProvider(id));
      if (isMe) {
        ref.invalidate(savedPostsProvider);
        ref.invalidate(likedPostsProvider);
      }
      await ref.read(profileProvider(id).future);
    }

    final handle = profile.value?.username == null ? '' : '@${profile.value!.username}';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.userId == null ? null : IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: isMe && widget.userId == null ? AccountTitle(text: handle, onTap: () => showAccountSwitcher(context, ref)) : Text(handle),
        actions: [
          if (isMe) ...[
            IconButton(tooltip: 'Scan', icon: const Icon(AppIcons.scan), onPressed: () => context.push(Routes.scan)),
            IconButton(tooltip: 'Create', icon: const Icon(AppIcons.plusCircle), onPressed: () => showCreateHub(context, ref)),
            IconButton(tooltip: 'Menu', icon: const Icon(AppIcons.list), onPressed: () => showProfileMenu(context, ref)),
          ] else if (profile.value != null)
            IconButton(icon: const Icon(AppIcons.dotsThreeVertical), onPressed: () => _otherMenu(context, profile.value!, blocked)),
        ],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e), style: const TextStyle(color: AppColors.textSecondary))),
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
                    moments: moments,
                    friendship: friendship,
                    onMeets: () => context.push(Routes.meets),
                    onFriends: isMe ? () => context.push(Routes.friends) : null,
                    onPoints: () => context.push(Routes.points),
                    onEdit: () => context.push(Routes.editProfile),
                    onRewards: () => context.push(Routes.rewards),
                    onQr: () => context.push(Routes.myQr),
                    onAvatar: () => _avatarSheet(p, isMe, moments),
                    onMoment: (m) => _openMoments(moments, moments.indexOf(m)),
                    onAddMoment: () => context.push(Routes.createMoment()),
                    onFriendAction: () => _friendAction(id, friendship, p.displayName ?? '@${p.username}'),
                    onMessage: () => _message(id),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: ProfileTabBar(
                    tabs: tabs,
                    selected: _tab.index.clamp(0, tabs.length - 1),
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
                    layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                    child: KeyedSubtree(
                      key: ValueKey(blocked ? 'blocked' : '$_tab$_liked'),
                      child: blocked
                          ? const _Fill(
                              child: EmptyState(art: AppArt.prohibited, title: 'You blocked this user', subtitle: 'Unblock from the menu to see their garage.'),
                            )
                          : switch (_tab) {
                              _Tab.posts => _postsBody(posts, isMe),
                              _Tab.garage => _garageBody(cars, isMe),
                              _Tab.saved => _savedBody(),
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

  // ------------------------------------------------------------------ tabs ---

  Widget _garageBody(AsyncValue<List<Car>> cars, bool isMe) {
    return cars.when(
      loading: () => const _Fill(child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => _Fill(child: Center(child: Text(friendlyError(e)))),
      data: (list) => list.isEmpty
          ? _Fill(
              child: EmptyState(
                art: AppArt.car,
                title: isMe ? 'Your garage is empty' : 'No cars yet',
                subtitle: isMe ? 'Add your daily, your project, your weekend toy.' : 'Nothing parked here so far.',
                actionLabel: isMe ? 'Add your first car' : null,
                onAction: isMe ? () => context.push(Routes.newCar) : null,
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                children: [
                  for (final c in list) ShowroomCard(car: c, onTap: () => context.push(Routes.car(c.id))),
                  if (isMe) AddCarCard(onTap: () => context.push(Routes.newCar)),
                ],
              ),
            ),
    );
  }

  Widget _postsBody(AsyncValue<List<FeedPost>> posts, bool isMe) {
    if (!kSocialFeed) return const SizedBox.shrink();
    return posts.when(
      loading: () => const _Fill(child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => _Fill(child: Center(child: Text(friendlyError(e)))),
      data: (list) => list.isEmpty
          ? _Fill(
              child: EmptyState(
                art: AppArt.camera,
                title: isMe ? 'No posts yet' : 'No posts',
                subtitle: isMe ? 'Share your ride, a spotted, a poll or a guide.' : 'Nothing shared so far.',
                actionLabel: isMe ? 'Create a post' : null,
                onAction: isMe ? () => showCreateHub(context, ref) : null,
              ),
            )
          : MasonryGrid(items: list),
    );
  }

  /// Saved tab: what I bookmarked, or what I liked. One small switch.
  Widget _savedBody() {
    final items = ref.watch(_liked ? likedPostsProvider : savedPostsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _Pill(label: 'Saved', icon: AppIcons.bookmarkSimple, on: !_liked, onTap: () => setState(() => _liked = false)),
              const SizedBox(width: 8),
              _Pill(label: 'Liked', icon: AppIcons.heart, on: _liked, onTap: () => setState(() => _liked = true)),
            ],
          ),
        ),
        items.when(
          loading: () => const _Fill(child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          error: (e, _) => _Fill(child: Center(child: Text(friendlyError(e)))),
          data: (list) => list.isEmpty
              ? _Fill(
                  child: EmptyState(
                    art: _liked ? AppArt.heartYellow : AppArt.bookmark,
                    title: _liked ? 'Nothing liked yet' : 'Nothing saved yet',
                    subtitle: _liked ? 'Double-tap a post to like it. It shows up here.' : 'Tap the bookmark on a post to keep it here.',
                  ),
                )
              : MasonryGrid(items: list),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- avatar ---

  void _openMoments(List<Story> moments, int index) {
    final author = moments.isEmpty ? null : moments.first.author;
    if (author == null) return;
    context.push(
      Routes.stories,
      extra: StoryViewerArgs(groups: [StoryGroup(author: author, stories: moments, allSeen: true)], initialGroup: 0),
    );
  }

  Future<void> _avatarSheet(Profile p, bool isMe, List<Story> moments) async {
    final hasPhoto = (p.avatarUrl ?? '').isNotEmpty;
    final live = moments.where((m) => m.isLive).toList();
    if (!isMe && !hasPhoto && live.isEmpty) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (live.isNotEmpty)
              ListTile(leading: const Icon(AppIcons.camera), title: Text('View moments (${live.length})'), onTap: () => Navigator.pop(ctx, 'moments')),
            if (hasPhoto) ListTile(leading: const Icon(AppIcons.eye), title: const Text('View photo'), onTap: () => Navigator.pop(ctx, 'view')),
            if (isMe) ListTile(leading: const Icon(AppIcons.images), title: const Text('Choose from library'), onTap: () => Navigator.pop(ctx, 'gallery')),
            if (isMe) ListTile(leading: const Icon(AppIcons.cameraPlus), title: const Text('Take photo'), onTap: () => Navigator.pop(ctx, 'camera')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'moments':
        _openMoments(live, 0);
      case 'view':
        showDialog<void>(
          context: context,
          barrierColor: Colors.black87,
          builder: (ctx) => GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Center(
              child: Hero(
                tag: 'avatar-${p.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: InteractiveViewer(child: Image.network(p.avatarUrl!, fit: BoxFit.contain)),
                ),
              ),
            ),
          ),
        );
      case 'gallery':
      case 'camera':
        await _changeAvatar(p.id, action == 'camera' ? ImageSource.camera : ImageSource.gallery);
    }
  }

  Future<void> _changeAvatar(String me, ImageSource source) async {
    try {
      final f = await pickAvatarImage(source);
      if (f == null) return;
      final repo = ref.read(authRepositoryProvider);
      final url = await repo.uploadAvatar(userId: me, bytes: await f.readAsBytes());
      await repo.saveProfile(userId: me, avatarUrl: url);
      ref.invalidate(profileProvider(me));
      ref.invalidate(currentProfileProvider);
      if (mounted) _snack('Profile photo updated.');
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  // ------------------------------------------------------------- friends ---

  Future<void> _friendAction(String id, FriendshipStatus status, String name) async {
    final actions = ref.read(friendActionsProvider);
    try {
      switch (status) {
        case FriendshipStatus.none:
          final s = await actions.add(id);
          _snack(s == FriendshipStatus.friends ? 'You\'re now friends.' : 'Request sent.');
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
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
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
            ListTile(leading: const Icon(AppIcons.flag), title: const Text('Report profile'), onTap: () => Navigator.pop(ctx, 'report')),
            ListTile(
              leading: Icon(blocked ? AppIcons.checkCircle : AppIcons.prohibit, color: AppColors.danger),
              title: Text(blocked ? 'Unblock' : 'Block', style: const TextStyle(color: AppColors.danger)),
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
        await showReportSheet(context, target: ReportTarget.profile, targetId: p.id);
      case 'block':
        await confirmBlockUser(context, ref, userId: p.id, displayName: name);
      case 'unblock':
        final me = ref.read(currentUserIdProvider);
        if (me == null) return;
        try {
          await ref.read(safetyRepositoryProvider).unblock(blockerId: me, blockedId: p.id);
          ref.invalidate(blockedUserIdsProvider);
        } catch (e) {
          if (context.mounted) _snack(friendlyError(e));
        }
    }
  }
}

// ---------------------------------------------------------------- pieces ---

/// Box-sized stand-in for the old SliverFillRemaining so tab bodies can animate.
class _Fill extends StatelessWidget {
  const _Fill({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(height: 380, child: child);
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon, required this.on, required this.onTap});
  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? AppColors.ink : AppColors.surfaceGray,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: on ? Colors.white : AppColors.textPrimary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.textPrimary)),
            ],
          ),
        ),
      );
}
