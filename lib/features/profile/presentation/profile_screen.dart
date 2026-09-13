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
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_repository.dart';
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
              onPressed: () => _myMenu(context),
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
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            UserAvatar(
                              url: p.avatarUrl,
                              name: p.displayName ?? p.username,
                              size: 86,
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _Stat(
                                    value: stats?.went,
                                    label: 'meets',
                                    onTap: () => context.push(Routes.meets),
                                  ),
                                  _Stat(
                                    value: posts.value?.length,
                                    label: 'posts',
                                    onTap: () =>
                                        setState(() => _tab = _Tab.posts),
                                  ),
                                  _Stat(
                                    value: friendCount,
                                    label: 'friends',
                                    onTap: isMe
                                        ? () => context.push(Routes.friends)
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          p.displayName ?? '@${p.username}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if ((p.bio ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            p.bio!.trim(),
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          [
                            if ((p.homeState ?? '').isNotEmpty) p.homeState!,
                            if (stats != null)
                              '${stats.cars} car${stats.cars == 1 ? '' : 's'}',
                            if (stats != null) '${stats.organised} organised',
                            if (stats != null && stats.attended > stats.went)
                              '${stats.attended - stats.went} upcoming',
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (badges.isNotEmpty ||
                            streak > 0 ||
                            points != null) ...[
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () => context.push(Routes.badges(id)),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (points != null)
                                  GestureDetector(
                                    onTap: () => context.push(Routes.points),
                                    child: _Pill(
                                      '$points pts',
                                      art: AppArt.star,
                                      highlight: true,
                                    ),
                                  ),
                                if (streak > 0)
                                  _Pill(
                                    '$streak-wk TT streak',
                                    art: AppArt.fire,
                                  ),
                                for (final b in badges.take(6))
                                  _Pill(
                                    b.badge.name,
                                    art: AppArt.forEmoji(b.badge.emoji),
                                  ),
                                if (badges.length > 6)
                                  _Pill('+${badges.length - 6}'),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (isMe)
                          Row(
                            children: [
                              Expanded(
                                child: SecondaryButton(
                                  label: 'Edit profile',
                                  onPressed: () =>
                                      context.push(Routes.editProfile),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SecondaryButton(
                                  label: 'Friends',
                                  onPressed: () => context.push(Routes.friends),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 46,
                                child: ElevatedButton(
                                  onPressed: () => context.push(Routes.newCar),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(46, 46),
                                  ),
                                  child: const Icon(AppIcons.car, size: 20),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: _FriendButton(
                                  status: friendship,
                                  onTap: () => _friendAction(
                                    id,
                                    friendship,
                                    p.displayName ?? '@${p.username}',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SecondaryButton(
                                  label: 'Message',
                                  onPressed: () => _message(id),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const Divider(),
                      Row(
                        children: [
                          _TabButton(
                            icon: AppIcons.garage,
                            selected: _tab == _Tab.garage,
                            onTap: () => setState(() => _tab = _Tab.garage),
                          ),
                          _TabButton(
                            icon: AppIcons.camera,
                            selected: _tab == _Tab.moments,
                            onTap: () => setState(() => _tab = _Tab.moments),
                          ),
                          if (kSocialFeed)
                            _TabButton(
                              icon: AppIcons.squaresFour,
                              selected: _tab == _Tab.posts,
                              onTap: () => setState(() => _tab = _Tab.posts),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (blocked)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      art: AppArt.prohibited,
                      title: 'You blocked this user',
                      subtitle: 'Unblock from the menu to see their garage.',
                    ),
                  )
                else if (_tab == _Tab.garage)
                  _garageSliver(cars, isMe)
                else if (_tab == _Tab.moments)
                  _momentsSliver(moments, isMe)
                else
                  _postsSliver(posts, isMe),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _garageSliver(AsyncValue<List<Car>> cars, bool isMe) {
    return cars.when(
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text(friendlyError(e))),
      ),
      data: (list) => list.isEmpty
          ? SliverFillRemaining(
              hasScrollBody: false,
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
          : SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverGrid.builder(
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
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text(friendlyError(e))),
      ),
      data: (list) => list.isEmpty
          ? SliverFillRemaining(
              hasScrollBody: false,
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
          : SliverToBoxAdapter(child: MasonryGrid(items: list.cast())),
    );
  }

  Widget _momentsSliver(AsyncValue<List<Story>> moments, bool isMe) {
    return moments.when(
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text(friendlyError(e))),
      ),
      data: (list) => list.isEmpty
          ? SliverFillRemaining(
              hasScrollBody: false,
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
          : SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverGrid.builder(
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

  Future<void> _myMenu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(AppIcons.pencilSimple),
                title: const Text('Edit profile'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                leading: const Icon(AppIcons.users),
                title: const Text('Friends'),
                onTap: () => Navigator.pop(ctx, 'friends'),
              ),
              if (kSocialFeed)
                ListTile(
                  leading: const Icon(AppIcons.bookmarkSimple),
                  title: const Text('Saved'),
                  onTap: () => Navigator.pop(ctx, 'saved'),
                ),
              ListTile(
                leading: const Icon(AppIcons.star),
                title: const Text('Points'),
                onTap: () => Navigator.pop(ctx, 'points'),
              ),
              if (ref.read(currentProfileProvider).value?.isAdmin ?? false)
                ListTile(
                  leading: const Icon(AppIcons.shieldCheck),
                  title: const Text('Review queue'),
                  onTap: () => Navigator.pop(ctx, 'review'),
                ),
              ListTile(
                leading: const Icon(AppIcons.qrCode),
                title: const Text('My QR'),
                onTap: () => Navigator.pop(ctx, 'qr'),
              ),
              ListTile(
                leading: const Icon(AppIcons.trophy),
                title: const Text('Badges'),
                onTap: () => Navigator.pop(ctx, 'badges'),
              ),
              ListTile(
                leading: const Icon(AppIcons.plusCircle),
                title: const Text('Add car'),
                onTap: () => Navigator.pop(ctx, 'car'),
              ),
              ListTile(
                leading: const Icon(AppIcons.signOut, color: AppColors.danger),
                title: const Text(
                  'Log out',
                  style: TextStyle(color: AppColors.danger),
                ),
                onTap: () => Navigator.pop(ctx, 'logout'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    final me = ref.read(currentUserIdProvider);
    switch (action) {
      case 'edit':
        context.push(Routes.editProfile);
      case 'friends':
        context.push(Routes.friends);
      case 'saved':
        context.push(Routes.saved);
      case 'badges':
        if (me != null) context.push(Routes.badges(me));
      case 'points':
        context.push(Routes.points);
      case 'review':
        context.push(Routes.adminReview);
      case 'qr':
        context.push(Routes.myQr);
      case 'car':
        context.push(Routes.newCar);
      case 'logout':
        await ref.read(authControllerProvider.notifier).signOut();
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

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});
  final int? value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Text(
            value?.toString() ?? '–',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.art, this.highlight = false});
  final String text;
  final String? art;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(art == null ? 9 : 5, 3, 9, 3),
    decoration: BoxDecoration(
      color: highlight ? AppColors.warnColor : AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (art != null) ...[ArtIcon(art!, size: 18), const SizedBox(width: 4)],
        Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(
                icon,
                size: 24,
                color: selected ? AppColors.textPrimary : AppColors.textMuted,
              ),
              const SizedBox(height: 8),
              Container(
                height: 1.5,
                color: selected ? AppColors.textPrimary : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

class _FriendButton extends StatelessWidget {
  const _FriendButton({required this.status, required this.onTap});
  final FriendshipStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => switch (status) {
    FriendshipStatus.none => PrimaryButton(
      label: 'Add friend',
      onPressed: onTap,
    ),
    FriendshipStatus.pendingOut => SecondaryButton(
      label: 'Requested',
      onPressed: onTap,
    ),
    FriendshipStatus.pendingIn => PrimaryButton(
      label: 'Accept request',
      onPressed: onTap,
    ),
    FriendshipStatus.friends => SecondaryButton(
      label: 'Friends ✓',
      onPressed: onTap,
    ),
  };
}
