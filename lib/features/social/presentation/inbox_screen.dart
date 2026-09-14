import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../friends/application/friends_providers.dart';
import '../../friends/domain/friend.dart';
import '../../auth/domain/profile.dart';
import '../application/chat_providers.dart';
import '../domain/chat.dart';
import '../application/notification_providers.dart';
import 'activity_screen.dart';

/// Chats tab: DMs and meet group chats, with Activity (likes, requests,
/// TT-now pings, badges) as a second tab.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadChats = ref.watch(unreadMessagesProvider).value ?? 0;
    final unreadActivity = ref.watch(unreadNotificationsProvider).value ?? 0;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Chats'),
          actions: [
            IconButton(tooltip: 'New message', icon: const Icon(AppIcons.notePencil), onPressed: () => context.push(Routes.search)),
          ],
          bottom: TabBar(
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.textPrimary,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorWeight: 1.5,
            dividerColor: AppColors.border,
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            tabs: [
              Tab(child: _TabLabel('Chats', unreadChats)),
              Tab(child: _TabLabel('Activity', unreadActivity)),
            ],
          ),
        ),
        body: const TabBarView(children: [_ChatList(), ActivityList()]),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.text, this.count);
  final String text;
  final int count;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(999)),
              child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      );
}

class _ChatList extends ConsumerWidget {
  const _ChatList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final friends = ref.watch(friendsProvider).value ?? const <Profile>[];
    final pins = ref.watch(friendPinsProvider).value ?? const <FriendPin>[];
    final live = {for (final p in pins) p.user.id: p};
    // Friends on the map first, then the rest.
    final strip = [...friends]..sort((a, b) => (live.containsKey(b.id) ? 1 : 0) - (live.containsKey(a.id) ? 1 : 0));

    Future<void> openDm(String userId) async {
      try {
        final id = await ref.read(chatActionsProvider).openDm(userId);
        if (context.mounted) context.push(Routes.chat(id));
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(inboxProvider);
        ref.invalidate(friendsProvider);
        await ref.read(inboxProvider.future);
      },
      child: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (list) {
          final chatted = {for (final c in list) if (c.other != null) c.other!.id};
          final unchatted = friends.where((f) => !chatted.contains(f.id)).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (strip.isNotEmpty) _FriendStrip(friends: strip, live: live, onTap: openDm),
              if (list.isEmpty && friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: EmptyState(
                    art: AppArt.speech,
                    title: 'No messages yet',
                    subtitle: 'Add friends first. Then message them here, or chat in a meet\'s group.',
                    actionLabel: 'Add friends',
                    onAction: () => context.push(Routes.friends),
                  ),
                ),
              if (list.isNotEmpty) const _Section('CHATS'),
              for (final c in list) _ChatTile(c: c),
              if (unchatted.isNotEmpty) ...[
                _Section(list.isEmpty ? 'SAY HI' : 'NOT CHATTED YET'),
                for (final f in unchatted)
                  ListTile(
                    leading: UserAvatar(url: f.avatarUrl, name: f.displayName ?? f.username, size: 48),
                    title: Text(f.displayName ?? '@${f.username}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      live[f.id]?.placeName != null ? 'On the map · ${live[f.id]!.placeName}' : (live.containsKey(f.id) ? 'On the map now' : '@${f.username ?? ''}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: live.containsKey(f.id) ? AppColors.success : AppColors.textSecondary),
                    ),
                    trailing: OutlinedButton(
                      onPressed: () => openDm(f.id),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 14), visualDensity: VisualDensity.compact),
                      child: const Text('Say hi'),
                    ),
                    onTap: () => openDm(f.id),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Friends as a row of circles; a green dot means they're on the map right now.
class _FriendStrip extends StatelessWidget {
  const _FriendStrip({required this.friends, required this.live, required this.onTap});
  final List<Profile> friends;
  final Map<String, FriendPin> live;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final liveCount = friends.where((f) => live.containsKey(f.id)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              const Text('FRIENDS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
              if (liveCount > 0) ...[
                const SizedBox(width: 8),
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('$liveCount on the map', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
              ],
            ],
          ),
        ),
        SizedBox(
          height: 86,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: friends.length,
            itemBuilder: (_, i) {
              final f = friends[i];
              final on = live.containsKey(f.id);
              return GestureDetector(
                onTap: () => onTap(f.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SizedBox(
                    width: 62,
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            UserAvatar(url: f.avatarUrl, name: f.displayName ?? f.username, size: 56, borderColor: on ? AppColors.success : null),
                            if (on)
                              Positioned(
                                right: 1,
                                bottom: 1,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2)),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(f.displayName?.split(' ').first ?? f.username ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.c});
  final Conversation c;

  @override
  Widget build(BuildContext context) {
    final last = c.lastMessage;
    return ListTile(
      leading: c.isMeet
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 48,
                height: 48,
                child: c.eventCover == null
                    ? const ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.usersThree, color: AppColors.textSecondary))
                    : Image.network(c.eventCover!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surfaceGray)),
              ),
            )
          : UserAvatar(url: c.other?.avatarUrl, name: c.other?.displayName ?? c.other?.username, size: 48),
      title: Text(c.title, style: TextStyle(fontWeight: c.unread > 0 ? FontWeight.w700 : FontWeight.w600)),
      subtitle: Text(
        last == null ? (c.isMeet ? 'Group chat · ${c.members.length} members' : 'Say hi') : last.body,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: c.unread > 0 ? AppColors.textPrimary : AppColors.textSecondary, fontWeight: c.unread > 0 ? FontWeight.w500 : FontWeight.w400),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (last != null) Text(timeAgo(last.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (c.unread > 0) ...[
            const SizedBox(height: 4),
            Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
          ],
        ],
      ),
      onTap: () => context.push(Routes.chat(c.id)),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
