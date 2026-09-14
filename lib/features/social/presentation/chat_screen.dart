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
import '../application/chat_providers.dart';
import 'story_viewer_screen.dart';
import '../domain/post.dart';
import '../application/social_providers.dart';
import '../domain/chat.dart';

/// One conversation. Bubbles like Instagram DMs; meet chats show sender names.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(chatActionsProvider).markRead(widget.conversationId));
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(chatActionsProvider).send(widget.conversationId, body);
      _text.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final conv = ref.watch(conversationProvider(widget.conversationId)).value;
    final messages = ref.watch(messagesProvider(widget.conversationId));
    ref.listen(messagesProvider(widget.conversationId), (_, next) {
      if (next.hasValue) ref.read(chatActionsProvider).markRead(widget.conversationId);
    });

    final membersById = {for (final p in conv?.members ?? const []) p.id: p};

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        titleSpacing: 0,
        title: InkWell(
          onTap: conv == null
              ? null
              : () => conv.isMeet
                  ? (conv.eventId == null ? null : context.push(Routes.event(conv.eventId!)))
                  : (conv.other == null ? null : context.push(Routes.profile(conv.other!.id))),
          child: Row(
            children: [
              if (conv != null && !conv.isMeet) ...[
                UserAvatar(url: conv.other?.avatarUrl, name: conv.other?.displayName ?? conv.other?.username, size: 32),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conv?.title ?? 'Chat', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.screenTitle),
                    if (conv != null)
                      Text(
                        conv.isMeet ? '${conv.members.length} members · tap for the meet' : '@${conv.other?.username ?? ''}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(tooltip: 'Chat info', icon: const Icon(AppIcons.dotsThreeVertical), onPressed: () => context.push(Routes.chatInfo(widget.conversationId))),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(child: Text(friendlyError(e))),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('No messages yet. Say hi 👋', style: TextStyle(color: AppColors.textSecondary)));
                }
                final reversed = list.reversed.toList();
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemCount: reversed.length,
                  itemBuilder: (_, i) {
                    final m = reversed[i];
                    final mine = m.senderId == me;
                    final prev = i + 1 < reversed.length ? reversed[i + 1] : null;
                    final showName = (conv?.isMeet ?? false) && !mine && (prev == null || prev.senderId != m.senderId);
                    final sender = m.sender ?? membersById[m.senderId];
                    return _Bubble(message: m, mine: mine, showName: showName, senderName: sender?.username, avatarUrl: sender?.avatarUrl, showAvatar: !mine && (conv?.isMeet ?? false));
                  },
                );
              },
            ),
          ),
          Container(
            decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Message…',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: AppColors.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: AppColors.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: AppColors.textMuted)),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: _sending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(AppIcons.paperPlaneTiltFill, color: AppColors.primary),
                      onPressed: _sending ? null : _send,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.showName, this.senderName, this.avatarUrl, required this.showAvatar});
  final Message message;
  final bool mine;
  final bool showName;
  final String? senderName;
  final String? avatarUrl;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: mine ? AppColors.primary : AppColors.surfaceGray,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.postId != null) _SharedPost(postId: message.postId!, mine: mine),
          if (message.storyId != null) _SharedMoment(storyId: message.storyId!, mine: mine),
          if (message.postId == null && message.storyId == null || !(message.body == 'Shared a post' || message.body == 'Shared a moment'))
            Text(message.body, style: TextStyle(color: mine ? Colors.white : AppColors.textPrimary, fontSize: 15, height: 1.35)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showName) Padding(padding: const EdgeInsets.only(left: 40, bottom: 2), child: Text(senderName ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          Row(
            mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showAvatar) ...[UserAvatar(url: avatarUrl, name: senderName, size: 28), const SizedBox(width: 6)],
              Tooltip(message: formatEventDate(message.createdAt), child: bubble),
            ],
          ),
        ],
      ),
    );
  }
}


/// A shared post inside a bubble: cover, title line, tap to open.
class _SharedPost extends ConsumerWidget {
  const _SharedPost({required this.postId, required this.mine});
  final String postId;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref.watch(postProvider(postId)).value?.post;
    final fg = mine ? Colors.white : AppColors.textPrimary;
    final sub = mine ? Colors.white70 : AppColors.textSecondary;
    return GestureDetector(
      onTap: () => context.push(Routes.post(postId)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        width: 220,
        decoration: BoxDecoration(color: mine ? Colors.white.withValues(alpha: 0.14) : Colors.white, borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: post == null
            ? const SizedBox(height: 60, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (post.cover != null) AspectRatio(aspectRatio: 4 / 3, child: Image.network(post.cover!, fit: BoxFit.cover)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('@${post.author?.username ?? 'post'}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
                        if ((post.title ?? post.caption ?? '').isNotEmpty)
                          Text(post.title ?? post.caption!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: sub)),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A shared moment inside a bubble: the photo, tap to play it.
class _SharedMoment extends ConsumerWidget {
  const _SharedMoment({required this.storyId, required this.mine});
  final String storyId;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final story = ref.watch(storyProvider(storyId)).value;
    return GestureDetector(
      onTap: story?.author == null
          ? null
          : () => context.push(Routes.stories, extra: StoryViewerArgs(groups: [StoryGroup(author: story!.author!, stories: [story], allSeen: true)], initialGroup: 0)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        width: 180,
        height: 240,
        decoration: BoxDecoration(color: mine ? Colors.white.withValues(alpha: 0.14) : AppColors.surfaceGray, borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: story == null
            ? const Center(child: Text('Moment no longer available', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)))
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(story.photoUrl, fit: BoxFit.cover),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    right: 8,
                    child: Text('@${story.author?.username ?? ''}${story.whereLabel == null ? '' : ' · ${story.whereLabel}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
                  ),
                ],
              ),
      ),
    );
  }
}
