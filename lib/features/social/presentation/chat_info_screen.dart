import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../events/application/event_providers.dart';
import '../../friends/application/friends_providers.dart';
import '../../friends/domain/friend.dart';
import '../../friends/presentation/call_sheet.dart';
import '../../safety/data/safety_repository.dart';
import '../../safety/presentation/report_sheet.dart';
import '../application/chat_providers.dart';
import '../application/community_providers.dart';
import '../application/social_providers.dart';
import '../domain/chat.dart';
import '../domain/club.dart';
import '../domain/post.dart';
import 'story_viewer_screen.dart';

/// The ⋯ page of a chat. A person: who they are, what you've shared, clubs
/// in common, then pin / delete / block / report. A meet chat: the meet,
/// its members, what's been shared, then pin / delete / report.
class ChatInfoScreen extends ConsumerWidget {
  const ChatInfoScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final conv = ref.watch(conversationProvider(conversationId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(conv.value?.isMeet == true ? 'Meet chat' : 'Chat info'),
      ),
      body: conv.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (c) => c == null
            ? const Center(child: Text('This chat is gone.'))
            : c.isMeet
                ? _MeetInfo(conv: c, me: me)
                : _DmInfo(conv: c, me: me),
      ),
    );
  }
}

// ------------------------------------------------------------------- DM ---

class _DmInfo extends ConsumerWidget {
  const _DmInfo({required this.conv, required this.me});
  final Conversation conv;
  final String? me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = conv.other;
    if (p == null) return const Center(child: Text('This person is no longer on TT Spot.'));
    final friendship = ref.watch(friendshipStatusProvider(p.id)).value ?? FriendshipStatus.none;
    final myClubs = ref.watch(myClubsProvider).value ?? const <Club>[];
    final theirClubs = ref.watch(clubsOfUserProvider(p.id)).value ?? const <Club>[];
    final common = theirClubs.where((c) => myClubs.any((m) => m.id == c.id)).toList();
    final blocked = ref.watch(blockedUserIdsProvider).value?.contains(p.id) ?? false;
    final name = p.displayName ?? '@${p.username}';

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: () => context.push(Routes.profile(p.id)),
            child: Column(
              children: [
                UserAvatar(url: p.avatarUrl, name: name, size: 96),
                const SizedBox(height: 10),
                Text(name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                Text('@${p.username ?? ''}${(p.homeState ?? '').isEmpty ? '' : ' · ${p.homeState}'}', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                if ((p.bio ?? '').trim().isNotEmpty)
                  Padding(padding: const EdgeInsets.fromLTRB(32, 8, 32, 0), child: Text(p.bio!.trim(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, height: 1.4))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: _Btn(icon: AppIcons.user, label: 'Profile', onTap: () => context.push(Routes.profile(p.id)))),
              const SizedBox(width: 8),
              if (friendship == FriendshipStatus.friends) ...[
                Expanded(child: _Btn(icon: AppIcons.phoneCall, label: 'Call', onTap: () => showCallSheet(context, ref, userId: p.id, name: name))),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _Btn(
                  icon: friendship == FriendshipStatus.friends ? AppIcons.checkCircle : AppIcons.userPlus,
                  label: switch (friendship) { FriendshipStatus.friends => 'Friends', FriendshipStatus.pendingOut => 'Requested', FriendshipStatus.pendingIn => 'Accept', _ => 'Add friend' },
                  onTap: friendship == FriendshipStatus.friends || friendship == FriendshipStatus.pendingOut
                      ? null
                      : () => _run(context, () async {
                            final a = ref.read(friendActionsProvider);
                            friendship == FriendshipStatus.pendingIn ? await a.accept(p.id) : await a.add(p.id);
                          }),
                ),
              ),
            ],
          ),
        ),
        _SharedStrip(conversationId: conv.id),
        if (common.isNotEmpty) ...[
          _Section('CLUBS IN COMMON · ${common.length}'),
          for (final c in common)
            ListTile(
              leading: UserAvatar(url: c.avatarUrl, name: c.name, size: 40),
              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('@${c.handle} · ${c.memberCount} members', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
              onTap: () => context.push(Routes.club(c.id)),
            ),
        ],
        const _Section('THIS CHAT'),
        _PinTile(conv: conv),
        _MuteTile(conv: conv),
        ListTile(
          leading: const Icon(AppIcons.trash, color: AppColors.danger),
          title: const Text('Delete chat', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          subtitle: const Text('Removes it from your list. It comes back if they message you.', style: TextStyle(fontSize: 12)),
          onTap: () => _deleteChat(context, ref, conv.id),
        ),
        const Divider(height: 16),
        ListTile(
          leading: Icon(blocked ? AppIcons.checkCircle : AppIcons.prohibit, color: AppColors.danger),
          title: Text(blocked ? 'Unblock $name' : 'Block $name', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          onTap: () => _run(context, () async {
            if (blocked) {
              await ref.read(safetyRepositoryProvider).unblock(blockerId: me!, blockedId: p.id);
              ref.invalidate(blockedUserIdsProvider);
            } else {
              await confirmBlockUser(context, ref, userId: p.id, displayName: name);
            }
          }),
        ),
        ListTile(
          leading: const Icon(AppIcons.flag, color: AppColors.danger),
          title: Text('Report $name', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          onTap: () => showReportSheet(context, target: ReportTarget.profile, targetId: p.id),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- meet ---

class _MeetInfo extends ConsumerWidget {
  const _MeetInfo({required this.conv, required this.me});
  final Conversation conv;
  final String? me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = conv.eventId == null ? null : ref.watch(eventDetailProvider(conv.eventId!)).value?.event;
    final members = conv.members;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        GestureDetector(
          onTap: conv.eventId == null ? null : () => context.push(Routes.event(conv.eventId!)),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: AspectRatio(
              aspectRatio: 16 / 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (conv.eventCover != null) Image(image: CachedNetworkImageProvider(conv.eventCover!), fit: BoxFit.cover),
                  const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]))),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(conv.eventTitle ?? 'Meet', maxLines: 2, style: const TextStyle(fontFamily: AppFonts.display, color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, height: 1)),
                        if (event != null) ...[
                          const SizedBox(height: 4),
                          Text('${formatEventDate(event.startsAt)} · ${event.venueName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                        ],
                        const SizedBox(height: 6),
                        const Text('Open the meet', style: TextStyle(color: AppColors.brand, fontSize: 12.5, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _SharedStrip(conversationId: conv.id),
        _Section('MEMBERS · ${members.length}'),
        for (final m in members)
          ListTile(
            leading: UserAvatar(url: m.avatarUrl, name: m.displayName ?? m.username, size: 40),
            title: Text(m.id == me ? 'You' : (m.displayName ?? '@${m.username}'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              m.id == event?.organizerId ? '@${m.username ?? ''} · HOST' : '@${m.username ?? ''}',
              style: TextStyle(fontSize: 12, color: m.id == event?.organizerId ? AppColors.brand : AppColors.textSecondary),
            ),
            trailing: m.id == me ? null : Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            onTap: m.id == me ? null : () => context.push(Routes.profile(m.id)),
          ),
        const _Section('THIS CHAT'),
        _MuteTile(conv: conv),
        _PinTile(conv: conv),
        ListTile(
          leading: const Icon(AppIcons.trash, color: AppColors.danger),
          title: const Text('Delete chat', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          subtitle: const Text('Removes it from your list. It comes back when someone writes.', style: TextStyle(fontSize: 12)),
          onTap: () => _deleteChat(context, ref, conv.id),
        ),
        if (conv.eventId != null)
          ListTile(
            leading: const Icon(AppIcons.flag, color: AppColors.danger),
            title: const Text('Report this meet', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            onTap: () => showReportSheet(context, target: ReportTarget.event, targetId: conv.eventId!),
          ),
      ],
    );
  }
}

// --------------------------------------------------------------- pieces ---

class _MuteTile extends ConsumerWidget {
  const _MuteTile({required this.conv});
  final Conversation conv;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
        secondary: Icon(conv.muted ? AppIcons.bellSlash : AppIcons.bell, color: AppColors.textPrimary),
        title: const Text('Mute', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('No badge for new messages here', style: TextStyle(fontSize: 12)),
        value: conv.muted,
        onChanged: (v) async {
          try {
            await ref.read(chatActionsProvider).setMute(conv.id, v);
          } catch (e) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
          }
        },
      );
}

/// Posts and moments sent in this chat, as a row of thumbnails.
class _SharedStrip extends ConsumerWidget {
  const _SharedStrip({required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shared = ref.watch(sharedInChatProvider(conversationId)).value ?? const <Message>[];
    if (shared.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section('SHARED HERE · ${shared.length}'),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: shared.length,
            itemBuilder: (_, i) => _SharedThumb(message: shared[i]),
          ),
        ),
      ],
    );
  }
}

class _SharedThumb extends ConsumerWidget {
  const _SharedThumb({required this.message});
  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? url;
    VoidCallback? open;
    String tag = '';
    if (message.imageUrl != null) {
      url = message.imageUrl;
      tag = 'Photo';
      open = () => showDialog<void>(
            context: context,
            barrierColor: Colors.black,
            builder: (ctx) => GestureDetector(onTap: () => Navigator.pop(ctx), child: InteractiveViewer(child: Center(child: Image(image: CachedNetworkImageProvider(message.imageUrl!))))),
          );
    } else if (message.postId != null) {
      final post = ref.watch(postProvider(message.postId!)).value?.post;
      url = post?.cover;
      tag = 'Post';
      open = () => context.push(Routes.post(message.postId!));
    } else if (message.storyId != null) {
      final s = ref.watch(storyProvider(message.storyId!)).value;
      url = s?.photoUrl;
      tag = 'Moment';
      if (s?.author != null) {
        open = () => context.push(Routes.stories, extra: StoryViewerArgs(groups: [StoryGroup(author: s!.author!, stories: [s], allSeen: true)], initialGroup: 0));
      }
    }
    return GestureDetector(
      onTap: open,
      child: Container(
        width: 84,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(10)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null) Image(image: CachedNetworkImageProvider(url), fit: BoxFit.cover) else Center(child: Icon(AppIcons.image, color: AppColors.textMuted)),
            Positioned(left: 6, bottom: 6, child: Text(tag, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 6, color: Colors.black)]))),
          ],
        ),
      ),
    );
  }
}

class _PinTile extends ConsumerWidget {
  const _PinTile({required this.conv});
  final Conversation conv;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
        leading: Icon(conv.pinned ? AppIcons.pushPinSlash : AppIcons.pushPin),
        title: Text(conv.pinned ? 'Unpin chat' : 'Pin chat', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Pinned chats stay at the top. Up to 3.', style: TextStyle(fontSize: 12)),
        onTap: () => _run(context, () => ref.read(chatActionsProvider).setPin(conv.id, !conv.pinned)),
      );
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: onTap == null ? AppColors.textSecondary : AppColors.textPrimary),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: onTap == null ? AppColors.textSecondary : AppColors.textPrimary)),
              ],
            ),
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

Future<void> _run(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

Future<void> _deleteChat(BuildContext context, WidgetRef ref, String conversationId) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this chat?'),
      content: const Text('It leaves your list. The other side keeps their copy.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await _run(context, () async {
    await ref.read(chatActionsProvider).hide(conversationId);
    if (context.mounted) context.go(Routes.inbox);
  });
}
