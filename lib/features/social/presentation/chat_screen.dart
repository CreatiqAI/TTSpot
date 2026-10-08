import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/media.dart';
import '../../../core/push/in_app_notice.dart' show OpenChats;
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_viewer.dart';
import '../../../core/widgets/user_avatar.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'widgets/chat_media.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_reply.dart';
import 'widgets/chat_wallpaper.dart';
import 'widgets/voice_bubble.dart';
import 'widgets/voice_recorder.dart';

import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_images.dart';
import '../../events/application/event_providers.dart';
import '../../friends/application/nicknames.dart';
import '../../profile/application/profile_providers.dart';
import '../application/chat_providers.dart';
import '../application/community_providers.dart';
import '../application/group_chat_providers.dart';
import 'widgets/group_avatar.dart';
import 'chat_attach.dart';
import 'chat_camera_screen.dart';
import 'story_viewer_screen.dart';
import 'chat_stickers.dart';
import 'widgets/media_send_preview.dart';
import 'widgets/video_badge.dart';
import '../domain/post.dart';
import '../application/social_providers.dart';
import '../domain/chat.dart';
import '../../auth/domain/profile.dart';
import '../../safety/data/safety_repository.dart';
import '../../safety/presentation/report_sheet.dart';

/// One conversation. Bubbles like Instagram DMs; meet, group and club chats
/// show the sender's name and face on the first bubble of each run.
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
    // No in-app banner for this chat while it's open; its notification leaves the shade.
    OpenChats.enter(widget.conversationId);
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(chatActionsProvider).markRead(widget.conversationId));
  }

  @override
  void dispose() {
    OpenChats.leave(widget.conversationId);
    _voice.dispose();
    _focus.dispose();
    _flashTimer?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- replies: swipe a bubble right, or long-press > Reply
  final _focus = FocusNode();
  Message? _replyTo;
  String? _flashId;
  Timer? _flashTimer;
  final _rowKeys = <String, GlobalKey>{};

  void _startReply(Message m) {
    setState(() => _replyTo = m);
    if (!_voice.active) _focus.requestFocus();
  }

  /// Drop the reply strip once the message that answered it is out.
  void _replied(Message? r) {
    if (mounted && r != null && _replyTo?.id == r.id) setState(() => _replyTo = null);
  }

  /// Who a quote is from: "You", the club / partner it was sent as, or the person.
  String _nameOf(Message o, String? me, Map<String, Profile> members, Conversation? conv) {
    if (o.senderId == me) return 'You';
    if (o.asClub != null || o.asVendor != null) return o.asName ?? conv?.entityName ?? 'Club';
    final p = o.sender ?? members[o.senderId];
    return displayNameFor(p, ref.read(nicknamesProvider));
  }

  /// Scroll the original of a reply into view and flash it.
  Future<void> _jumpTo(String id, List<Message> reversed) async {
    final idx = reversed.indexWhere((m) => m.id == id);
    if (idx < 0) {
      _hint('Original message unavailable');
      return;
    }
    // The list is lazy, so step towards it a screen at a time until it's built.
    for (var i = 0; i < 80 && mounted; i++) {
      final ctx = _rowKeys[id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: 0.4, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
        break;
      }
      final built = [for (var j = 0; j < reversed.length; j++) if (_rowKeys[reversed[j].id]?.currentContext != null) j];
      if (built.isEmpty || !_scroll.hasClients) break;
      final pos = _scroll.position;
      final step = pos.viewportDimension * 0.8;
      // Reversed list: further back in time = bigger offset.
      final to = (idx > built.last ? pos.pixels + step : pos.pixels - step).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (to == pos.pixels) break;
      _scroll.jumpTo(to);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    setState(() => _flashId = id);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _flashId = null);
    });
  }

  void _hint(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    final reply = _replyTo;
    setState(() => _sending = true);
    try {
      await ref.read(chatActionsProvider).send(widget.conversationId, body, replyTo: reply?.id);
      _text.clear();
      _replied(reply);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _guard(Future<void> Function() f) async {
    setState(() => _sending = true);
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// [_guard] for anything sent while a reply is open: it goes out as a reply,
  /// and the strip closes once it's sent.
  Future<void> _guardReply(Future<void> Function(String? replyTo) f) {
    final reply = _replyTo;
    return _guard(() async {
      await f(reply?.id);
      _replied(reply);
    });
  }

  // ---- voice notes: tap the mic to record hands-free, or hold it and let go to send
  late final _voice = VoiceRecorder(onReady: _sendVoiceNote, onHint: _hint, canStart: () => !_sending);

  Future<void> _sendVoiceNote(VoiceNote n) async {
    await _guardReply((replyTo) async {
      final bytes = await File(n.path).readAsBytes();
      await ref.read(chatActionsProvider).sendVoice(widget.conversationId, bytes, n.ms, wave: n.wave, replyTo: replyTo);
      File(n.path).delete().catchError((_) => File(n.path));
    });
  }

  Future<void> _video(ImageSource source) async {
    final f = await ImagePicker().pickVideo(source: source, maxDuration: kChatVideoMaxDuration);
    if (f == null || !mounted) return;
    // Library picks can skip maxDuration: refuse a huge file before previewing it.
    if (await f.length() > kChatVideoMaxMb * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That video is too big. Pick one under $kChatVideoMaxMb MB.')));
      return;
    }
    await _sendMedia([f]);
  }

  /// WhatsApp style: picked photos and videos open in a full-screen preview
  /// first (captions, add / remove more), then go out one message each. A
  /// reply being written goes with the first of them.
  Future<void> _sendMedia(List<XFile> files) async {
    if (files.isEmpty || !mounted) return;
    final items = await showMediaSendPreview(context, files);
    if (items == null || items.isEmpty) return;
    await _sendItems(items);
  }

  /// What the preview (or the camera, which runs it itself) said to send.
  Future<void> _sendItems(List<MediaSendItem> items) async {
    if (items.isEmpty || !mounted) return;
    final actions = ref.read(chatActionsProvider);
    await _guardReply((reply) async {
      for (final (i, it) in items.indexed) {
        final replyTo = i == 0 ? reply : null;
        if (it.isVideo) {
          await actions.sendVideo(widget.conversationId, it.file, replyTo: replyTo, poster: it.poster, ms: it.ms, caption: it.caption);
        } else {
          await actions.sendPhoto(widget.conversationId, it.file, replyTo: replyTo, caption: it.caption);
        }
      }
    });
  }

  /// The in-app camera: tap for a photo, hold for a video, or the gallery.
  /// It runs the send preview itself, so what comes back is ready to go.
  Future<void> _camera() async {
    final items = await openChatCamera(context);
    if (items != null) await _sendItems(items);
  }

  Future<void> _photos() async {
    final picked = await ImagePicker().pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85, limit: kChatMediaMaxItems);
    await _sendMedia(picked);
  }

  Future<void> _sticker() async {
    final key = await showStickerSheet(context);
    if (key == null) return;
    await _guardReply((r) => ref.read(chatActionsProvider).sendSticker(widget.conversationId, key, replyTo: r));
  }

  Future<void> _attach({int tab = 0}) async {
    final a = await showAttachSheet(context, initialTab: tab);
    if (a == null) return;
    await _guardReply((r) => ref.read(chatActionsProvider).attach(widget.conversationId, eventId: a.eventId, placeId: a.placeId, carId: a.carId, replyTo: r));
  }

  Future<void> _plus() async {
    final what = await showComposerSheet(context);
    if (what == null || !mounted) return;
    switch (what) {
      case ComposerAction.photos:
        await _photos();
      case ComposerAction.video:
        await _video(ImageSource.gallery);
      case ComposerAction.camera:
        await _camera();
      case ComposerAction.location:
        await _attach(tab: 1);
      case ComposerAction.meet:
        await _attach(tab: 0);
      case ComposerAction.car:
        await _attach(tab: 2);
      case ComposerAction.sticker:
        await _sticker();
    }
  }

  /// Long-press on a message: reply, copy its text, and on someone else's,
  /// report it or block the sender.
  Future<void> _messageMenu(Message m, String? username, {bool mine = false, bool canReply = true, bool canDelete = false}) async {
    final name = username ?? 'user';
    final canCopy = !m.autoBody && m.body.trim().isNotEmpty;
    final action = await showModalBottomSheet<String>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canReply) ListTile(leading: const Icon(AppIcons.arrowBendUpLeft), title: const Text('Reply'), onTap: () => Navigator.pop(ctx, 'reply')),
            if (canCopy) ListTile(leading: const Icon(AppIcons.copy), title: const Text('Copy text'), onTap: () => Navigator.pop(ctx, 'copy')),
            if (canDelete)
              ListTile(
                key: const Key('message-delete'),
                leading: const Icon(AppIcons.trash, color: AppColors.danger),
                title: Text('Delete for everyone', style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            if (!mine) ...[
              ListTile(leading: const Icon(AppIcons.flag), title: const Text('Report message'), onTap: () => Navigator.pop(ctx, 'report')),
              ListTile(leading: const Icon(AppIcons.prohibit, color: AppColors.danger), title: Text('Block @$name', style: TextStyle(color: AppColors.danger)), onTap: () => Navigator.pop(ctx, 'block')),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'reply':
        _startReply(m);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.body));
        _hint('Copied');
      case 'delete':
        await _deleteForEveryone(m, mine: mine);
      case 'report':
        await showReportSheet(context, target: ReportTarget.message, targetId: m.id);
      case 'block':
        await confirmBlockUser(context, ref, userId: m.senderId, displayName: '@$name');
    }
  }

  /// Your own message anywhere; anyone's in a club chat (officers) or a
  /// friends' group (admins).
  Future<void> _deleteForEveryone(Message m, {required bool mine}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete for everyone?'),
        content: Text(mine ? 'It disappears from this chat for everyone in it.' : 'It disappears from this chat for everyone, the sender too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(key: const Key('message-delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (_replyTo?.id == m.id) setState(() => _replyTo = null);
      await ref.read(groupChatActionsProvider).deleteMessage(widget.conversationId, m.id);
      _hint('Message deleted');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final blocked = ref.watch(blockedUserIdsProvider).value ?? const <String>{};
    final conv = ref.watch(conversationProvider(widget.conversationId)).value;
    final messages = ref.watch(messagesProvider(widget.conversationId));
    ref.listen(messagesProvider(widget.conversationId), (_, next) {
      if (next.hasValue) ref.read(chatActionsProvider).markRead(widget.conversationId);
    });

    final group = conv?.isGroup ?? false;
    // Many people: names and faces on bubbles. A group's (or club chat's) full list
    // names messages that came in live, which carry no sender profile.
    final multi = conv?.isMulti ?? false;
    final groupMembers = group ? ref.watch(groupMembersProvider(widget.conversationId)).value : null;
    final membersById = <String, Profile>{
      for (final p in conv?.members ?? const <Profile>[]) p.id: p,
      if (groupMembers != null)
        for (final g in groupMembers) g.id: g.profile,
    };
    final canModerate = ref.watch(canModerateChatProvider(widget.conversationId));
    final nick = ref.watch(nicknamesProvider);
    final title = conv == null ? 'Chat' : conversationTitle(conv, nick);
    final otherNick = conv?.other == null ? null : nick[conv!.other!.id];
    final hostId = conv?.eventId == null ? null : ref.watch(eventDetailProvider(conv!.eventId!)).value?.event.organizerId;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        titleSpacing: 0,
        title: InkWell(
          onTap: conv == null
              ? null
              : () => conv.isGroup
                  ? context.push(Routes.chatInfo(widget.conversationId))
                  : conv.isMeet
                  ? (conv.eventId == null ? null : context.push(Routes.event(conv.eventId!)))
                  : (conv.other == null ? null : context.push(Routes.profile(conv.other!.id))),
          child: Row(
            children: [
              if (conv != null && conv.isGroup) ...[
                GroupAvatar(conv: conv, size: 32),
                const SizedBox(width: 10),
              ] else if (conv != null && !conv.isMeet) ...[
                UserAvatar(url: conv.avatarUrl, name: conv.otherGone ? null : conv.title, seed: conv.showEntity ? null : conv.other?.id, size: 32, fallbackAsset: conv.showEntity && conv.clubId != null ? crestAsset(conv.clubId!) : null),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.screenTitle),
                    if (conv != null && !conv.otherGone)
                      Text(
                        conv.isGroup
                            ? '${conv.isClubChat ? 'Club chat · ' : ''}${groupMembers?.length ?? conv.size} members'
                            : conv.isMeet
                            ? '${conv.members.length} going'
                            : conv.showEntity
                                ? (conv.clubId != null ? 'Car club' : 'Partner')
                                // With a nickname, their real name comes back here.
                                : '${otherNick != null && (conv.other?.displayName ?? '').trim().isNotEmpty ? '${conv.other!.displayName!.trim()} · ' : ''}@${conv.other?.username ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: conv?.isMeet ?? false ? 'Members' : (group ? 'Group info' : 'Chat info'),
            icon: Icon(conv?.isMeet ?? false ? AppIcons.usersThree : AppIcons.dotsThreeVertical),
            onPressed: () => context.push(Routes.chatInfo(widget.conversationId)),
          ),
        ],
      ),
      body: Column(
        children: [
          if (conv != null && conv.isMeet && conv.eventId != null) _HostingCard(eventId: conv.eventId!, me: me),
          Expanded(
            child: ChatWallpaperBackground(child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: ChatWallpaperPanel(child: Text(friendlyError(e), textAlign: TextAlign.center)))),
              data: (all) {
                final list = all.where((m) => !blocked.contains(m.senderId)).toList();
                if (list.isEmpty && (conv?.otherGone ?? false)) return const SizedBox.shrink();
                if (list.isEmpty) {
                  final other = conv?.other;
                  final first = otherNick ?? (other?.displayName ?? other?.username ?? '').split(' ').first;
                  final starters = group
                      ? const ['TT tonight?', 'Where to lepak?', "Who's free this weekend?", 'Otw, 10 min']
                      : conv?.isMeet ?? false
                      ? const ['Who\'s coming tonight?', 'Where to park?', 'Otw, 10 min', 'Anyone need a ride?']
                      : ['Hey $first, TT tonight?', 'Coming TTDI Thursday?', 'Nice ride, what mods?', 'Otw, 10 min', 'Where you usually TT?'];
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: ChatWallpaperPanel(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (conv != null && group) GroupAvatar(conv: conv, size: 72) else if (other != null) UserAvatar(url: other.avatarUrl, name: other.displayName ?? other.username, seed: other.id, size: 72),
                          const SizedBox(height: 10),
                          Text(group ? 'Say hi to the group' : (conv?.isMeet ?? false ? 'Meet chat is empty' : 'Say hi to $first'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('Tap one to start, or type your own.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final t in starters)
                                ActionChip(
                                  label: Text(t),
                                  onPressed: () {
                                    _text.text = t;
                                    _send();
                                  },
                                ),
                            ],
                          ),
                        ],
                      )),
                    ),
                  );
                }
                final reversed = list.reversed.toList();
                final byId = {for (final m in all) m.id: m};
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemCount: reversed.length,
                  itemBuilder: (_, i) {
                    final m = reversed[i];
                    final mine = m.senderId == me;
                    final prev = i + 1 < reversed.length ? reversed[i + 1] : null;
                    // The day's first message gets a divider above it (the list runs bottom-up, so
                    // "above" is the older neighbour), and a meet chat names the sender again under it.
                    final newDay = prev == null || !isSameDay(prev.createdAt, m.createdAt);
                    // First of a run: a new day, a new sender, or the club / partner after the person.
                    final firstOfRun = prev == null || newDay || prev.senderId != m.senderId || (prev.asName != null) != (m.asName != null);
                    final showName = multi && !mine && firstOfRun;
                    final sender = m.sender ?? membersById[m.senderId];
                    final host = m.senderId == hostId;
                    final showEntity = m.asName != null;
                    final canReply = !(conv?.otherGone ?? false);
                    final replyId = m.replyTo;
                    final quote = replyId == null
                        ? null
                        : ReplyQuoteFor(
                            replyToId: replyId,
                            loaded: byId[replyId],
                            nameOf: (o) => _nameOf(o, me, membersById, conv),
                            isMine: (o) => o.senderId == me,
                            hidden: (o) => blocked.contains(o.senderId),
                            onTap: () => _jumpTo(replyId, reversed),
                          );
                    final row = KeyedSubtree(
                      key: _rowKeys.putIfAbsent(m.id, GlobalKey.new),
                      child: SwipeToReply(
                        enabled: canReply,
                        onReply: () => _startReply(m),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          decoration: BoxDecoration(
                            color: _flashId == m.id ? AppColors.brand.withValues(alpha: 0.12) : AppColors.brand.withValues(alpha: 0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: GestureDetector(
                            onLongPress: () => _messageMenu(m, sender?.username, mine: mine, canReply: canReply, canDelete: mine || canModerate),
                            child: _Bubble(
                              message: m,
                              mine: mine,
                              showName: (showName || (showEntity && (!group || firstOfRun))) && !mine,
                              // A group names people by my nickname for them, else their name, else @handle.
                              senderName: showEntity ? m.asName : (group ? displayNameFor(sender, nick) : (nick[m.senderId] ?? sender?.username)),
                              avatarUrl: showEntity ? m.asLogo : sender?.avatarUrl,
                              avatarSeed: showEntity ? null : m.senderId,
                              // In a group the face goes on the first bubble of a run; the rest keep its space.
                              showAvatar: !mine && (group ? firstOfRun : ((conv?.isMeet ?? false) || showEntity)),
                              avatarSpace: !mine && group,
                              host: host && !showEntity,
                              quote: quote,
                            ),
                          ),
                        ),
                      ),
                    );
                    if (!newDay) return row;
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_DayDivider(m.createdAt), row]);
                  },
                );
              },
            )),
          ),
          if (conv?.otherGone ?? false)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
                child: Text(
                  'This account was deleted, so messages can no longer be sent here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ChatComposer(
              controller: _text,
              sending: _sending,
              onSend: _send,
              onPlus: _plus,
              onCamera: _camera,
              recorder: _voice,
              focusNode: _focus,
              header: _replyTo == null
                  ? null
                  : ReplyComposerStrip(
                      original: _replyTo!,
                      name: _nameOf(_replyTo!, me, membersById, conv),
                      mine: _replyTo!.senderId == me,
                      onCancel: () => setState(() => _replyTo = null),
                    ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.showName, this.senderName, this.avatarUrl, this.avatarSeed, required this.showAvatar, this.avatarSpace = false, this.host = false, this.quote});
  final Message message;
  final bool mine;
  final bool showName;
  final String? senderName;
  final String? avatarUrl;
  final String? avatarSeed;
  final bool showAvatar;
  /// No face on this bubble, but keep its space so a run lines up (groups).
  final bool avatarSpace;
  final bool host;
  /// The quoted original when this message is a reply.
  final Widget? quote;

  @override
  Widget build(BuildContext context) {
    final isShare = message.hasAttachment;
    final auto = message.autoBody;
    final maxW = MediaQuery.sizeOf(context).width * 0.72;
    final time = formatTime(message.createdAt);
    final wp = ChatWallpaperStyle.of(context);

    // The text bubble is always the message's last piece, so it always carries the time.
    // A plain-text reply carries its quote inside, on top, the bubble as wide as the wider of the two.
    Widget textBubble(String text, {Widget? quote}) => Container(
          constraints: BoxConstraints(maxWidth: maxW),
          padding: quote == null ? const EdgeInsets.fromLTRB(14, 9, 12, 7) : const EdgeInsets.fromLTRB(5, 5, 5, 7),
          decoration: BoxDecoration(
            color: wp.bubbleFill(mine),
            border: wp.bubbleBorder(mine),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: quote == null
              ? _TimedText(text: text, time: time)
              : IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      quote,
                      Padding(padding: const EdgeInsets.fromLTRB(9, 6, 7, 0), child: _TimedText(text: text, time: time)),
                    ],
                  ),
                ),
        );

    // A reply with a photo, card or sticker: the quote rides in a small bubble on top.
    Widget quoteCard(Widget q) => Container(
          margin: const EdgeInsets.only(bottom: 3),
          constraints: BoxConstraints(maxWidth: maxW),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: wp.bubbleFill(mine),
            border: wp.bubbleBorder(mine),
            borderRadius: BorderRadius.circular(14),
          ),
          child: IntrinsicWidth(child: q),
        );

    // Time on a line of its own under a card, post, moment or sticker, lined up with its right edge.
    Widget under(Widget w, String? t) => t == null
        ? w
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              w,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: wp.chipFill, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(t, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11, color: wp.chipText)),
              ),
            ],
          );

    // A shared post / moment sits on its own, no bubble around it. A note, if any, follows underneath.
    // Each piece takes the time or null; only the last one gets it.
    // A caption typed under a photo or video sits inside the media's own bubble, WhatsApp style.
    final caption = !auto && (message.imageUrl != null || message.videoUrl != null) ? message.body : null;
    final pieces = <Widget Function(String? t)>[
      if (quote != null && message.audioUrl == null) (_) => quoteCard(quote!),
      if (message.postId != null) (t) => under(_SharedPost(postId: message.postId!, mine: mine), t),
      if (message.storyId != null) (t) => under(_SharedMoment(storyId: message.storyId!, mine: mine), t),
      if (message.imageUrl != null)
        (t) => caption == null ? _Photo(url: message.imageUrl!, time: t) : _Captioned(mine: mine, caption: caption, time: time, media: _Photo(url: message.imageUrl!, fill: true)),
      if (message.audioUrl != null)
        (t) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: VoiceBubble(url: message.audioUrl!, ms: message.audioMs ?? 0, mine: mine, time: t, wave: message.audioWave, seed: message.id, avatarUrl: avatarUrl, avatarSeed: avatarSeed, avatarName: senderName, quote: quote),
            ),
      if (message.videoUrl != null)
        (t) => caption == null
            ? VideoBubble(key: ValueKey('video-${message.id}'), url: message.videoUrl!, time: t, poster: message.videoPosterUrl, ms: message.videoMs)
            : _Captioned(mine: mine, caption: caption, time: time, media: VideoBubble(key: ValueKey('video-${message.id}'), url: message.videoUrl!, poster: message.videoPosterUrl, ms: message.videoMs)),
      if (message.sticker != null) (t) => under(Padding(padding: const EdgeInsets.only(bottom: 4), child: ChatSticker(message.sticker!)), t),
      if (message.eventId != null) (t) => under(_SharedEvent(eventId: message.eventId!), t),
      if (message.placeId != null) (t) => under(_SharedPlace(placeId: message.placeId!), t),
      if (message.carId != null) (t) => under(_SharedCar(carId: message.carId!), t),
      if (!auto && caption == null) (_) => textBubble(message.body),
    ];
    final bubble = isShare
        ? Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [for (var i = 0; i < pieces.length; i++) pieces[i](i == pieces.length - 1 ? time : null)],
          )
        : textBubble(message.body, quote: quote);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showName)
            Padding(
              padding: const EdgeInsets.only(left: 40, bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A group shows full names: a long one is cut, never overflows.
                  Flexible(child: Text(senderName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: wp.label))),
                  if (host) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
                      child: const Text('HOST', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .5)),
                    ),
                  ],
                ],
              ),
            ),
          Row(
            mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showAvatar) ...[UserAvatar(url: avatarUrl, name: senderName, seed: avatarSeed, size: 28), const SizedBox(width: 6)] else if (avatarSpace) const SizedBox(width: 34),
              bubble,
            ],
          ),
        ],
      ),
    );
  }
}

/// Message text with its send time in the bottom-right corner, WhatsApp style.
/// An invisible copy of the time rides at the end of the text, so the text
/// wraps around it: the time shares the last line when there's room, else it
/// drops to a line of its own. Same style, same text scaling, so it can't overlap.
class _TimedText extends StatelessWidget {
  const _TimedText({required this.text, required this.time});
  final String text;
  final String time;

  static const _timeStyle = TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w400);

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Text.rich(
            TextSpan(
              text: text,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.35),
              children: [
                // The plain space lets the line break before the time; the no-break
                // spaces keep the gap and the time in one piece.
                TextSpan(text: '   ${time.replaceAll(' ', ' ')}', style: _timeStyle.copyWith(color: Colors.transparent)),
              ],
            ),
            // Hug the longest line, so a bubble whose time dropped a line isn't stretched to full width.
            textWidthBasis: TextWidthBasis.longestLine,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            // Screen readers already hear the invisible copy.
            child: ExcludeSemantics(child: Text(time, maxLines: 1, softWrap: false, style: _timeStyle.copyWith(color: AppColors.textSecondary))),
          ),
        ],
      );
}

/// "Today", "Yesterday", "Monday", "28 Sep": a small centred pill between days.
class _DayDivider extends StatelessWidget {
  const _DayDivider(this.day);
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final wp = ChatWallpaperStyle.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 8, 0, 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: wp.chipFill, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text(formatDayLabel(day), maxLines: 1, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: wp.chipText)),
      ),
    );
  }
}


/// Top of a meet chat: who is hosting, when, where. Tap for the meet.
class _HostingCard extends ConsumerWidget {
  const _HostingCard({required this.eventId, required this.me});
  final String eventId;
  final String? me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(eventDetailProvider(eventId)).value;
    if (d == null) return const SizedBox.shrink();
    final e = d.event;
    final hosting = e.organizerId == me;
    final who = e.isListing
        ? e.listingLine
        : hosting
            ? 'You\'re hosting'
            : 'Hosted by ${e.vendorName ?? d.organizer?.displayName ?? d.organizer?.username ?? 'the organiser'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push(Routes.event(e.id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                  child: const Icon(AppIcons.starFill, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(who, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      Text('${formatTime(e.startsAt)} · ${e.venueName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
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
    final fg = AppColors.textPrimary;
    final sub = AppColors.textSecondary;
    return GestureDetector(
      onTap: () => context.push(Routes.post(postId)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        width: 220,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: post == null
            ? const SizedBox(height: 60, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (post.cover != null)
                    AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image(image: CachedNetworkImageProvider(post.cover!), fit: BoxFit.cover),
                          // A video post: its still, marked as a video.
                          if (post.isVideo) Positioned(left: 8, bottom: 8, child: VideoBadge(ms: post.videoMs)),
                        ],
                      ),
                    ),
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
        margin: const EdgeInsets.only(bottom: 4),
        width: 180,
        height: 240,
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: story == null
            ? Center(child: Text('Moment no longer available', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)))
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image(image: CachedNetworkImageProvider(story.photoUrl), fit: BoxFit.cover),
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


/// A photo sent in chat, with the send [time] in a pill at the bottom right
/// when given. Tap to see it full screen.
class _Photo extends StatelessWidget {
  const _Photo({required this.url, this.time, this.fill = false});
  final String url;
  final String? time;
  /// Fill the width it is given (inside a captioned bubble), cropping a tall photo.
  final bool fill;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => showPhotoViewer(context, [url]),
        child: Container(
          margin: EdgeInsets.only(bottom: fill ? 0 : 4),
          constraints: BoxConstraints(maxWidth: 240, maxHeight: 320, minHeight: fill ? 120 : 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
          child: fill
              ? Image(image: CachedNetworkImageProvider(url), fit: BoxFit.cover, width: double.infinity)
              : Stack(
                  children: [
                    Image(image: CachedNetworkImageProvider(url), fit: BoxFit.cover),
                    if (time != null) Positioned(right: 8, bottom: 8, child: ChatTimePill(time!)),
                  ],
                ),
        ),
      );
}

/// A photo or video with the caption typed under it, in one bubble: the media
/// on top, then the text with the send time at the end of its last line.
class _Captioned extends StatelessWidget {
  const _Captioned({required this.media, required this.caption, required this.time, required this.mine});
  final Widget media;
  final String caption;
  final String time;
  final bool mine;

  @override
  Widget build(BuildContext context) => Container(
        width: 246,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: ChatWallpaperStyle.of(context).bubbleFill(mine),
          border: ChatWallpaperStyle.of(context).bubbleBorder(mine),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            media,
            Padding(padding: const EdgeInsets.fromLTRB(9, 6, 7, 3), child: _TimedText(text: caption, time: time)),
          ],
        ),
      );
}

/// Small card shared for a meet, a spot or a car. Same shape for all three.
class _Card extends StatelessWidget {
  const _Card({required this.image, required this.fallback, required this.eyebrow, required this.title, required this.subtitle, required this.onTap, this.placeholder});
  final String? image;
  final String fallback;
  /// Drawn instead of the [fallback] art when there's no image (car renders).
  final Widget? placeholder;
  final String eyebrow;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          width: 240,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: image == null ? (placeholder ?? ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(fallback, size: 34)))) : Image(image: CachedNetworkImageProvider(image!), fit: BoxFit.cover),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(eyebrow, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.brand)),
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.2)),
                      if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _SharedEvent extends ConsumerWidget {
  const _SharedEvent({required this.eventId});
  final String eventId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(eventDetailProvider(eventId)).value?.event;
    return _Card(
      image: e?.coverUrl,
      fallback: e?.type.art ?? AppArt.flag,
      eyebrow: 'MEET',
      title: e?.title ?? 'Meet',
      subtitle: e == null ? null : '${formatEventDate(e.startsAt)} · ${e.venueName}',
      onTap: () => context.push(Routes.event(eventId)),
    );
  }
}

class _SharedPlace extends ConsumerWidget {
  const _SharedPlace({required this.placeId});
  final String placeId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(placeProvider(placeId)).value;
    return _Card(
      image: p?.coverUrl,
      fallback: p?.kindIcon ?? kindIconAsset('other'),
      eyebrow: 'SPOT',
      title: p?.name ?? 'Spot',
      subtitle: p == null ? null : '${p.kindLabel} · ${p.totalCheckins} check-ins',
      onTap: () => context.push(Routes.place(placeId)),
    );
  }
}

class _SharedCar extends ConsumerWidget {
  const _SharedCar({required this.carId});
  final String carId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(carProvider(carId)).value;
    return _Card(
      image: c?.cover,
      fallback: AppArt.car,
      placeholder: CarPlaceholder(bodyStyle: c?.bodyStyle),
      eyebrow: 'CAR',
      title: c == null ? 'Car' : '${c.make} ${c.model}',
      subtitle: c?.year?.toString(),
      onTap: () => context.push(Routes.car(carId)),
    );
  }
}
