import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/glass_tab_bar.dart';
import '../../../core/config/features.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/titi_avatar_grid.dart';
import '../../../core/widgets/user_avatar.dart' show DefaultAvatars;
import '../../cards/application/cards_providers.dart';
import '../../cards/presentation/widgets/box_nudge.dart';
import '../../cards/presentation/widgets/profile_cards_grid.dart';
import '../../accounts/presentation/account_switcher.dart';
import '../../accounts/presentation/account_title.dart';
import '../../admin/application/admin_providers.dart' show adminMemberPointsProvider;
import '../../auth/application/onboarding_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/profile.dart';
import '../../friends/application/friends_providers.dart';
import '../../friends/domain/friend.dart';
import '../../friends/presentation/call_sheet.dart';
import '../../friends/presentation/friend_colour_sheet.dart';
import '../../points/application/points_providers.dart';
import '../../safety/data/safety_repository.dart';
import '../../safety/presentation/report_sheet.dart';
import '../../social/application/chat_providers.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/album.dart';
import '../../social/domain/post.dart';
import '../../social/presentation/create_hub_sheet.dart';
import '../../social/presentation/story_viewer_screen.dart';
import '../../social/presentation/widgets/masonry_grid.dart';
import '../application/profile_providers.dart';
import '../domain/car.dart';
import 'profile_menu.dart';
import 'widgets/albums_strip.dart';
import 'widgets/profile_header.dart';
import '../../../core/utils/share_links.dart';

enum _Tab { posts, cards }

/// Profile: about the person. Identity on top (with a garage row: My garage
/// on my page, their read-only garage on someone else's), then Posts · Cards.
/// On my own page the Posts tab also holds Saved · Liked · Commented.
/// `userId == null` means "me".
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.userId});
  final String? userId;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  _Tab _tab = _Tab.posts;

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
    final albums = ref.watch(userAlbumsProvider(id)).value ?? const <MomentAlbum>[];
    final stats = ref.watch(profileStatsProvider(id)).value;
    final friendCount = ref.watch(friendCountProvider(id)).value;
    final friendship = ref.watch(friendshipStatusProvider(id)).value ?? FriendshipStatus.none;
    final blocked = ref.watch(blockedUserIdsProvider).value?.contains(id) ?? false;
    // Points stay private: my own, or anyone's when an admin is looking.
    final adminView = !isMe && (ref.watch(currentProfileProvider).value?.isAdmin ?? false);
    // Null (no pill) until the balance is known, never a wrong 0.
    final points = isMe ? ref.watch(pointsBalanceProvider).value : adminView ? ref.watch(adminMemberPointsProvider(id)).value : null;
    final tabs = [
      (AppIcons.squaresFour, 'Posts'),
      (AppIcons.cards, 'Cards'),
    ];

    Future<void> refresh() async {
      ref.invalidate(profileProvider(id));
      ref.invalidate(userCarsProvider(id));
      ref.invalidate(userPostsProvider(id));
      ref.invalidate(userMomentsProvider(id));
      ref.invalidate(userAlbumsProvider(id));
      ref.invalidate(profileStatsProvider(id));
      ref.invalidate(friendCountProvider(id));
      ref.invalidate(friendshipStatusProvider(id));
      ref.invalidate(cardTypesProvider);
      if (adminView) ref.invalidate(adminMemberPointsProvider(id));
      if (isMe) {
        ref.read(cardsActionsProvider).refreshCollection();
        ref.invalidate(savedPostsProvider);
        ref.invalidate(likedPostsProvider);
        ref.invalidate(commentedPostsProvider);
      }
      await ref.read(profileProvider(id).future);
    }

    final handle = profile.value?.username == null ? '' : '@${profile.value!.username}';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: widget.userId != null,
        titleSpacing: widget.userId == null ? 16 : null,
        leading: widget.userId == null ? null : IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: isMe && widget.userId == null ? AccountTitle(text: handle, onTap: () => showAccountSwitcher(context, ref)) : Text(handle),
        actions: [
          if (isMe) ...[
            IconButton(tooltip: 'Scan', icon: const Icon(AppIcons.scan), onPressed: () => context.push(Routes.scan)),
            IconButton(tooltip: 'Menu', icon: const Icon(AppIcons.list), onPressed: () => showProfileMenu(context, ref)),
          ] else if (profile.value != null)
            IconButton(icon: const Icon(AppIcons.dotsThreeVertical), onPressed: () => _otherMenu(context, profile.value!, blocked)),
        ],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e), style: TextStyle(color: AppColors.textSecondary))),
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
                    cars: blocked ? const <Car>[] : (cars.value ?? const <Car>[]),
                    stats: stats,
                    friendCount: friendCount,
                    points: points,
                    moments: moments,
                    friendship: friendship,
                    onMeets: () => context.push(Routes.meets),
                    onFriends: isMe ? () => context.push(Routes.friends) : null,
                    // An admin on someone else's profile lands in Give points with them picked.
                    onPoints: () => context.push(isMe ? Routes.points : Routes.adminPointsFor(id)),
                    onEdit: () => context.push(Routes.editProfile),
                    onRewards: () => context.push(Routes.rewards),
                    onQr: () => context.push(Routes.myQr),
                    onAvatar: () => _avatarSheet(p, isMe, moments),
                    onGarage: () => context.push(isMe ? Routes.myGarage : Routes.userGarage(id)),
                    onFriendAction: () => _friendAction(id, friendship, p.displayName ?? '@${p.username}'),
                    onMessage: () => _message(id),
                    onCall: !isMe && friendship == FriendshipStatus.friends && ref.watch(friendPhoneProvider(id)).value != null
                        ? () => showCallSheet(context, ref, userId: id, name: p.displayName ?? '@${p.username}')
                        : null,
                  ),
                ),
                if (isMe && ref.watch(sealedBoxesProvider).isNotEmpty)
                  SliverToBoxAdapter(child: BoxNudge(count: ref.watch(sealedBoxesProvider).length, onTap: () => context.push(Routes.openBox(ref.read(sealedBoxesProvider).first.id)))),
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
                      key: ValueKey(blocked ? 'blocked' : '$_tab'),
                      child: blocked
                          ? const _Fill(
                              child: EmptyState(art: AppArt.prohibited, title: 'You blocked this user', subtitle: 'Unblock from the menu to see their posts.'),
                            )
                          : switch (_tab) {
                              _Tab.posts => _postsBody(posts, isMe, p, albums),
                              _Tab.cards => ProfileCardsGrid(
                                  userId: id,
                                  isMe: isMe,
                                  isFriend: friendship == FriendshipStatus.friends,
                                  onAddFriend: friendship == FriendshipStatus.none ? () => _friendAction(id, friendship, p.displayName ?? '@${p.username}') : null,
                                ),
                            },
                    ),
                  ),
                ),
                // The last row of posts or cards scrolls clear of the floating tab bar.
                SliverToBoxAdapter(child: SizedBox(height: GlassTabBar.clearance(context))),
              ],
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------ tabs ---

  Widget _postsBody(AsyncValue<List<FeedPost>> posts, bool isMe, Profile p, List<MomentAlbum> albums) {
    if (!kSocialFeed) return const SizedBox.shrink();
    return posts.when(
      loading: () => const _Fill(child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => _Fill(child: Center(child: Text(friendlyError(e)))),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AlbumsStrip(albums: albums, onAlbum: (a) => _openAlbum(p, a), onAdd: isMe ? () => context.push(Routes.newAlbum) : null),
          if (list.isEmpty)
            _Fill(
              child: EmptyState(
                art: AppArt.camera,
                title: isMe ? 'No posts yet' : 'No posts',
                subtitle: isMe ? 'Share your ride, a spotted, a poll or a guide.' : 'Nothing shared so far.',
                actionLabel: isMe ? 'Create a post' : null,
                onAction: isMe ? () => showCreateHub(context, ref) : null,
              ),
            )
          else
            MasonryGrid(items: list),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- avatar ---

  Future<void> _openAlbum(Profile p, MomentAlbum a) async {
    try {
      final list = await ref.read(albumMomentsProvider(a.id).future);
      if (!mounted) return;
      if (list.isEmpty) {
        if (p.id == ref.read(currentUserIdProvider)) context.push(Routes.editAlbum(a.id));
        return;
      }
      context.push(
        Routes.stories,
        extra: StoryViewerArgs(groups: [StoryGroup(author: p, stories: list, allSeen: true, label: a.name, albumId: a.id)], initialGroup: 0),
      );
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

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
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMe) ...[
              TitiAvatarGrid(selected: DefaultAvatars.indexOfUrl(p.avatarUrl), onPick: (i) => Navigator.pop(ctx, 'titi:$i')),
              const Divider(height: 16),
            ],
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
                  child: InteractiveViewer(child: Image(image: DefaultAvatars.image(p.avatarUrl) ?? CachedNetworkImageProvider(p.avatarUrl!), fit: BoxFit.contain)),
                ),
              ),
            ),
          ),
        );
      case 'gallery':
      case 'camera':
        await _changeAvatar(p.id, action == 'camera' ? ImageSource.camera : ImageSource.gallery);
      default:
        final i = action.startsWith('titi:') ? int.tryParse(action.substring(5)) : null;
        if (i != null) await _setPresetAvatar(p.id, i);
    }
  }

  /// A TiTi default avatar: saved as its public Storage URL, no upload.
  Future<void> _setPresetAvatar(String me, int index) async {
    try {
      await ref.read(authRepositoryProvider).saveProfile(userId: me, avatarUrl: DefaultAvatars.publicUrl(index));
      ref.invalidate(profileProvider(me));
      ref.invalidate(currentProfileProvider);
      if (mounted) _snack('Profile photo updated.');
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
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

  Future<void> _pickColour(BuildContext context, Profile p) =>
      showFriendColourSheet(context, ref, userId: p.id, name: p.displayName ?? '@${p.username}');

  Future<void> _otherMenu(BuildContext context, Profile p, bool blocked) async {
    final action = await showModalBottomSheet<String>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(AppIcons.shareFat), title: const Text('Share profile'), onTap: () => Navigator.pop(ctx, 'share')),
            if (ref.read(friendIdsProvider).contains(p.id)) ...[
              ListTile(leading: const Icon(AppIcons.cards), title: const Text('Trade cards'), subtitle: const Text('Swap blind box cards with them', style: TextStyle(fontSize: 12)), onTap: () => Navigator.pop(ctx, 'trade')),
              ListTile(leading: const Icon(AppIcons.mapPin), title: const Text('Colour on the map'), subtitle: const Text('Pick a colour so you spot them fast', style: TextStyle(fontSize: 12)), onTap: () => Navigator.pop(ctx, 'colour')),
            ],
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
      case 'share':
        await shareThing(type: 'profile', id: p.id, text: '@${p.username} on TT Spot');
      case 'trade':
        context.push(Routes.newTradeWith(p.id));
      case 'colour':
        await _pickColour(context, p);
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

