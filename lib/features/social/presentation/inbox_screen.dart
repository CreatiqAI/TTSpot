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
import '../application/chat_providers.dart';
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
    return RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(inboxProvider);
          await ref.read(inboxProvider.future);
        },
        child: inbox.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (list) => list.isEmpty
              ? LayoutBuilder(
                  builder: (_, c) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: c.maxHeight,
                      child: EmptyState(
                        art: AppArt.speech,
                        title: 'No messages yet',
                        subtitle: 'Message a driver from their garage, or open a meet\'s group chat.',
                        actionLabel: 'Find people',
                        onAction: () => context.push(Routes.search),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final c = list[i];
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
                  },
                ),
        ),
    );
  }
}
