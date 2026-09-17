import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/event_list_tile.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../accounts/presentation/account_switcher.dart';
import '../../accounts/presentation/account_title.dart';
import '../../auth/domain/profile.dart';
import '../../friends/application/friends_providers.dart';
import '../application/chat_providers.dart';
import '../application/community_providers.dart';
import '../application/social_providers.dart';
import '../domain/club.dart';
import '../domain/post.dart';
import '../../profile/presentation/profile_menu.dart';
import 'create_hub_sheet.dart';
import 'widgets/club_requests.dart';
import 'widgets/club_tier_widgets.dart';
import 'widgets/masonry_grid.dart';

/// A car club's page. Owners invite members and admins; members see each
/// other on the map and can switch that off per club. `embedded` = shown as
/// the Me tab while the club account is active.
class ClubScreen extends ConsumerWidget {
  const ClubScreen({super.key, required this.clubId, this.embedded = false});
  final String clubId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubProvider(clubId));
    final me = ref.watch(currentUserIdProvider);
    final isMember = ref.watch(isClubMemberProvider(clubId)).value ?? false;
    final members = ref.watch(clubMembersProvider(clubId)).value ?? const <Profile>[];
    final roles = ref.watch(clubMemberRolesProvider(clubId)).value ?? const <String, String>{};
    final events = ref.watch(clubEventsProvider(clubId)).value ?? const [];
    final posts = ref.watch(postsWhereProvider((column: 'club_id', value: clubId))).value ?? const <FeedPost>[];
    final invite = ref.watch(myClubInviteProvider(clubId)).value;
    final inviteRole = ref.watch(myClubInviteRoleProvider(clubId)).value;
    final sharing = ref.watch(myClubShareProvider(clubId)).value ?? true;
    final isOwner = club.value?.ownerId == me;
    final isManager = isOwner || roles[me] == 'vp' || roles[me] == 'secretary' || roles[me] == 'owner';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: !embedded,
        titleSpacing: embedded ? 16 : null,
        leading: embedded ? null : IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: embedded
            ? AccountTitle(text: club.value?.handle == null ? '' : '@${club.value!.handle}', onTap: () => showAccountSwitcher(context, ref))
            : Text(club.value?.handle == null ? '' : '@${club.value!.handle}'),
        actions: [
          if (embedded) ...[
            IconButton(tooltip: 'Create', icon: const Icon(AppIcons.plusCircle), onPressed: () => showCreateHub(context, ref)),
            IconButton(tooltip: 'Menu', icon: const Icon(AppIcons.list), onPressed: () => showProfileMenu(context, ref)),
          ],
        ],
      ),
      body: club.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (c) {
          if (c == null) return const Center(child: Text('This club no longer exists.'));
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(clubProvider(clubId));
              ref.invalidate(clubMembersProvider(clubId));
              ref.invalidate(clubMemberRolesProvider(clubId));
              ref.invalidate(clubEventsProvider(clubId));
              ref.invalidate(myClubInviteProvider(clubId));
              ref.invalidate(myClubInviteRoleProvider(clubId));
              ref.invalidate(myClubRequestProvider(clubId));
              ref.invalidate(clubJoinRequestsProvider(clubId));
              ref.invalidate(myClubShareProvider(clubId));
              ref.invalidate(postsWhereProvider((column: 'club_id', value: clubId)));
              await ref.read(clubProvider(clubId).future);
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _Header(club: c, meets: events.length, posts: posts.length),
                if (invite != null && (!isMember || inviteRole == 'vp' || inviteRole == 'secretary')) _InviteBanner(clubId: clubId, clubName: c.name, role: inviteRole ?? 'member'),
                ClubTierCard(club: c, isOwner: isOwner),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: isManager
                            ? PrimaryButton(label: 'Invite members', onPressed: () => _invite(context, ref, c))
                            : isMember
                                ? SecondaryButton(label: 'Member', icon: AppIcons.checkCircle, onPressed: () => _leave(context, ref))
                                : invite != null
                                    ? SecondaryButton(label: 'Message club', icon: AppIcons.chatCircle, onPressed: () => _messageClub(context, ref))
                                    : JoinRequestButton(clubId: clubId, clubName: c.name),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SecondaryButton(
                          label: isManager ? 'Post as club' : 'Post',
                          icon: AppIcons.cameraPlus,
                          onPressed: isMember || isManager ? () => context.push(Routes.createPost(PostKind.post, clubId: clubId, asClub: isManager)) : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isManager)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SecondaryButton(label: 'Schedule a meet as ${c.name}', icon: AppIcons.flagCheckered, onPressed: () => context.push(Routes.createEventAs(clubId: clubId))),
                  ),
                if (!isMember && !isManager && invite == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SecondaryButton(label: 'Message club', icon: AppIcons.chatCircle, onPressed: () => _messageClub(context, ref)),
                  ),
                if (isManager) ClubRequestsSection(clubId: clubId),
                if (!c.isOfficial && (isMember || isManager)) ClubGarageSection(club: c, isManager: isManager),
                if (isMember || isManager)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Container(
                      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
                      child: SwitchListTile.adaptive(
                        value: sharing,
                        onChanged: (v) async {
                          try {
                            await ref.read(communityActionsProvider).setClubShare(clubId, v);
                            ref.invalidate(friendPinsProvider);
                          } catch (e) {
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
                          }
                        },
                        secondary: const ArtIcon(AppArt.pin, size: 28),
                        title: const Text('Show me on the club map', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(
                          sharing ? 'Members of ${c.name} can see where you are while the app is open.' : 'Hidden from this club. Friends still see you.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                if (members.isNotEmpty) ...[
                  _Section('MEMBERS · ${members.length}'),
                  SizedBox(
                    height: 96,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final m in members)
                          _MemberTile(
                            profile: m,
                            role: m.id == c.ownerId ? 'owner' : (roles[m.id] ?? 'member'),
                            onTap: () => isManager && m.id != me && m.id != c.ownerId
                                ? _manageMember(context, ref, c, m, roles[m.id] ?? 'member', isOwner: isOwner)
                                : context.push(Routes.profile(m.id)),
                          ),
                      ],
                    ),
                  ),
                  if (isOwner)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Text('Tap a member to appoint a Vice President or Secretary. Officers can post, invite and schedule meets as the club.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                ],
                if (isMember || isManager) ClubLeaderboard(clubId: clubId),
                const _Section('MEETS'),
                if (events.isEmpty)
                  Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('No meets tagged to this club yet.', style: TextStyle(color: AppColors.textSecondary)))
                else
                  for (final e in events) EventListTile(event: e, onTap: () => context.push(Routes.event(e.id)), isOrganiser: e.organizerId == me),
                const _Section('POSTS'),
                if (posts.isEmpty)
                  Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('No posts yet.', style: TextStyle(color: AppColors.textSecondary)))
                else
                  MasonryGrid(items: posts),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _manageMember(BuildContext context, WidgetRef ref, Club c, Profile m, String role, {required bool isOwner}) async {
    final name = m.displayName ?? '@${m.username}';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: UserAvatar(url: m.avatarUrl, name: name, size: 40),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(role == 'member' ? 'Member' : '${clubRoleLabel(role)} · helps run ${c.name}', style: const TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'profile'),
            ),
            const Divider(height: 8),
            if (isOwner && role != 'vp')
              ListTile(
                leading: const Icon(AppIcons.shieldCheck),
                title: const Text('Make Vice President'),
                subtitle: const Text('They accept from Activity, then they can post, invite and schedule meets as the club.', style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'vp'),
              ),
            if (isOwner && role != 'secretary')
              ListTile(
                leading: const Icon(AppIcons.notePencil),
                title: const Text('Make Secretary'),
                subtitle: const Text('Same powers as the VP: posts, invites, meets, join requests.', style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'secretary'),
              ),
            if (isOwner && role != 'member')
              ListTile(leading: const Icon(AppIcons.shield), title: const Text('Back to member'), onTap: () => Navigator.pop(ctx, 'member')),
            ListTile(
              leading: const Icon(AppIcons.userMinus, color: AppColors.danger),
              title: const Text('Remove from club', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final actions = ref.read(communityActionsProvider);
    try {
      switch (action) {
        case 'profile':
          context.push(Routes.profile(m.id));
        case 'vp':
        case 'secretary':
          await actions.inviteToClub(clubId, m.id, role: action);
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invite sent. $name becomes ${clubRoleLabel(action)} once they accept.')));
        case 'member':
          await actions.setClubRole(clubId, m.id, 'member');
        case 'remove':
          await actions.removeClubMember(clubId, m.id);
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _messageClub(BuildContext context, WidgetRef ref) async {
    try {
      final id = await ref.read(chatActionsProvider).openClubDm(clubId);
      if (context.mounted) context.push(Routes.chat(id));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this club?'),
        content: const Text('You\'ll stop seeing members on the map and need a new invite to come back.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(communityActionsProvider).toggleClubMembership(clubId, isMember: true);
      ref.invalidate(friendPinsProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _invite(BuildContext context, WidgetRef ref, Club c) async {
    final memberIds = (ref.read(clubMembersProvider(clubId)).value ?? const <Profile>[]).map((m) => m.id).toSet();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _InviteSheet(clubId: clubId, clubName: c.name, memberIds: memberIds),
    );
  }
}

/// Avatar + handle, crown for the owner, small shield for admins.
class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.profile, required this.role, required this.onTap});
  final Profile profile;
  final String role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = profile;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(url: m.avatarUrl, name: m.displayName ?? m.username, size: 54),
                if (role == 'owner')
                  const Positioned(right: -2, top: -4, child: Icon(AppIcons.crown, size: 18, color: AppColors.warnColor))
                else if (role == 'vp' || role == 'secretary')
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                      child: const Icon(AppIcons.shieldCheck, size: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(width: 62, child: Text(m.username ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
            if (role != 'member')
              Text(clubRoleShort(role), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.club, required this.meets, required this.posts});
  final Club club;
  final int meets;
  final int posts;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF15181E), Color(0xFF2B2F3A)]),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(url: club.avatarUrl, name: club.name, size: 72, borderColor: AppColors.warnColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(club.name, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Chip(icon: club.isOfficial ? AppIcons.sealCheck : AppIcons.usersThree, text: club.isOfficial ? 'Official club' : 'Underground', color: club.isOfficial ? const Color(0xFFE6B422) : Colors.white70),
                        if ((club.homeState ?? '').isNotEmpty) _Chip(icon: AppIcons.mapPin, text: club.homeState!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((club.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(club.description!.trim(), style: const TextStyle(fontSize: 13.5, height: 1.4, color: Colors.white70)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(value: club.memberCount, label: 'members'),
              _Stat(value: meets, label: 'meets'),
              _Stat(value: posts, label: 'posts'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color ?? Colors.white70),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color ?? Colors.white70)),
          ],
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: const TextStyle(fontFamily: AppFonts.display, fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
          ],
        ),
      );
}

class _InviteBanner extends ConsumerStatefulWidget {
  const _InviteBanner({required this.clubId, required this.clubName, this.role = 'member'});
  final String clubId;
  final String clubName;
  final String role;
  bool get admin => role != 'member';
  @override
  ConsumerState<_InviteBanner> createState() => _InviteBannerState();
}

class _InviteBannerState extends ConsumerState<_InviteBanner> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    try {
      await ref.read(communityActionsProvider).respondClubInvite(widget.clubId, accept: accept);
      ref.invalidate(friendPinsProvider);
      if (mounted && accept) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.admin ? 'You now help run ${widget.clubName}. Switch to it from your @handle.' : 'Welcome to ${widget.clubName}.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.warnColor, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.admin ? 'Be ${clubRoleLabel(widget.role)} of ${widget.clubName}?' : 'You\'re invited', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
            const SizedBox(height: 4),
            Text(
              widget.admin
                  ? 'The president wants you as ${clubRoleLabel(widget.role)}. You\'ll be able to post, invite and schedule meets as the club.'
                  : 'Join ${widget.clubName} to see your clubmates on the map and get their meets first.',
              style: const TextStyle(fontSize: 13, height: 1.35, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _respond(false), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)), child: const Text('Decline'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(onPressed: _busy ? null : () => _respond(true), style: FilledButton.styleFrom(backgroundColor: Colors.black), child: Text(widget.admin ? 'Accept' : 'Join club'))),
              ],
            ),
          ],
        ),
      );
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.clubId, required this.clubName, required this.memberIds});
  final String clubId;
  final String clubName;
  final Set<String> memberIds;
  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _sent = <String>{};
  String? _busy;

  Future<void> _send(Profile p) async {
    setState(() => _busy = p.id);
    try {
      await ref.read(communityActionsProvider).inviteToClub(widget.clubId, p.id);
      setState(() => _sent.add(p.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider).value ?? const <Profile>[];
    final candidates = friends.where((f) => !widget.memberIds.contains(f.id)).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                children: [
                  Text('Invite to ${widget.clubName}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Pick from your friends. They accept from Activity or the club page.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Expanded(
              child: candidates.isEmpty
                  ? Center(child: Padding(padding: EdgeInsets.all(24), child: Text('All your friends are already in, or you have no friends on TT Spot yet. Add friends first.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary))))
                  : ListView.builder(
                      itemCount: candidates.length,
                      itemBuilder: (_, i) {
                        final p = candidates[i];
                        final sent = _sent.contains(p.id);
                        return ListTile(
                          leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, size: 40),
                          title: Text(p.displayName ?? '@${p.username}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('@${p.username ?? ''}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          trailing: SizedBox(
                            width: 96,
                            child: sent
                                ? const Text('Invited', textAlign: TextAlign.right, style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700))
                                : FilledButton(
                                    onPressed: _busy == null ? () => _send(p) : null,
                                    style: FilledButton.styleFrom(minimumSize: const Size(0, 34), visualDensity: VisualDensity.compact),
                                    child: _busy == p.id ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Invite'),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
