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
import 'dart:async';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'widgets/chat_media.dart';
import 'widgets/chat_composer.dart';

import '../../../core/theme/app_art.dart';
import '../../events/application/create_event_controller.dart' show pickCoverImage;
import '../../events/application/event_providers.dart';
import '../../profile/application/profile_providers.dart';
import '../application/chat_providers.dart';
import '../application/community_providers.dart';
import 'chat_attach.dart';
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
    _tick?.cancel();
    _rec.dispose();
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

  // ---- voice notes: hold the mic, slide left to cancel
  final _rec = AudioRecorder();
  bool _recording = false;
  bool _cancelling = false;
  Duration _elapsed = Duration.zero;
  Timer? _tick;
  DateTime? _recStart;
  double _dragX = 0;

  Future<void> _startRecording() async {
    if (_recording || _sending) return;
    if (!await _rec.hasPermission()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Allow the microphone to send voice notes.')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100), path: path);
    _recStart = DateTime.now();
    _dragX = 0;
    setState(() {
      _recording = true;
      _cancelling = false;
      _elapsed = Duration.zero;
    });
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final e = DateTime.now().difference(_recStart!);
      if (e > const Duration(minutes: 2)) {
        _stopRecording(send: true);
        return;
      }
      setState(() => _elapsed = e);
    });
  }

  Future<void> _stopRecording({required bool send}) async {
    if (!_recording) return;
    _tick?.cancel();
    final path = await _rec.stop();
    final ms = DateTime.now().difference(_recStart ?? DateTime.now()).inMilliseconds;
    setState(() {
      _recording = false;
      _cancelling = false;
    });
    if (!send || path == null || ms < 700) {
      if (path != null) File(path).delete().catchError((_) => File(path));
      return;
    }
    await _guard(() async {
      final bytes = await File(path).readAsBytes();
      await ref.read(chatActionsProvider).sendVoice(widget.conversationId, bytes, ms);
      File(path).delete().catchError((_) => File(path));
    });
  }

  Future<void> _video(ImageSource source) async {
    final f = await ImagePicker().pickVideo(source: source, maxDuration: const Duration(seconds: 60));
    if (f == null) return;
    await _guard(() => ref.read(chatActionsProvider).sendVideo(widget.conversationId, f));
  }

  Future<void> _cameraMenu() async {
    final what = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(AppIcons.camera), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, 'photo')),
            ListTile(leading: const Icon(AppIcons.record), title: const Text('Record a video'), subtitle: const Text('Up to 60 seconds', style: TextStyle(fontSize: 12)), onTap: () => Navigator.pop(ctx, 'video')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (what == 'photo') await _photo(ImageSource.camera);
    if (what == 'video') await _video(ImageSource.camera);
  }

  Future<void> _photo(ImageSource source) async {
    final f = await pickCoverImage(source);
    if (f == null) return;
    await _guard(() => ref.read(chatActionsProvider).sendPhoto(widget.conversationId, f));
  }

  Future<void> _sticker() async {
    final key = await showStickerSheet(context);
    if (key == null) return;
    await _guard(() => ref.read(chatActionsProvider).sendSticker(widget.conversationId, key));
  }

  Future<void> _attach({int tab = 0}) async {
    final a = await showAttachSheet(context, initialTab: tab);
    if (a == null) return;
    await _guard(() => ref.read(chatActionsProvider).attach(widget.conversationId, eventId: a.eventId, placeId: a.placeId, carId: a.carId));
  }

  Future<void> _plus() async {
    final what = await showComposerSheet(context);
    if (what == null || !mounted) return;
    switch (what) {
      case ComposerAction.photos:
        await _photo(ImageSource.gallery);
      case ComposerAction.video:
        await _video(ImageSource.gallery);
      case ComposerAction.camera:
        await _cameraMenu();
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

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final conv = ref.watch(conversationProvider(widget.conversationId)).value;
    final messages = ref.watch(messagesProvider(widget.conversationId));
    ref.listen(messagesProvider(widget.conversationId), (_, next) {
      if (next.hasValue) ref.read(chatActionsProvider).markRead(widget.conversationId);
    });

    final membersById = {for (final p in conv?.members ?? const []) p.id: p};
    final hostId = conv?.eventId == null ? null : ref.watch(eventDetailProvider(conv!.eventId!)).value?.event.organizerId;

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
                UserAvatar(url: conv.avatarUrl, name: conv.title, size: 32),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conv?.title ?? 'Chat', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.screenTitle),
                    if (conv != null)
                      Text(
                        conv.isMeet
                            ? '${conv.members.length} going'
                            : conv.showEntity
                                ? (conv.clubId != null ? 'Car club' : 'Partner')
                                : '@${conv.other?.username ?? ''}',
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
            tooltip: conv?.isMeet ?? false ? 'Members' : 'Chat info',
            icon: Icon(conv?.isMeet ?? false ? AppIcons.usersThree : AppIcons.dotsThreeVertical),
            onPressed: () => context.push(Routes.chatInfo(widget.conversationId)),
          ),
        ],
      ),
      body: Column(
        children: [
          if (conv != null && conv.isMeet && conv.eventId != null) _HostingCard(eventId: conv.eventId!, me: me),
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(child: Text(friendlyError(e))),
              data: (list) {
                if (list.isEmpty) {
                  final other = conv?.other;
                  final first = (other?.displayName ?? other?.username ?? '').split(' ').first;
                  final starters = conv?.isMeet ?? false
                      ? const ['Who\'s coming tonight?', 'Where to park?', 'Otw, 10 min', 'Anyone need a ride?']
                      : ['Hey $first, TT tonight?', 'Coming TTDI Thursday?', 'Nice ride, what mods?', 'Otw, 10 min', 'Where you usually TT?'];
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (other != null) UserAvatar(url: other.avatarUrl, name: other.displayName ?? other.username, size: 72),
                          const SizedBox(height: 10),
                          Text(conv?.isMeet ?? false ? 'Meet chat is empty' : 'Say hi to $first', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
                      ),
                    ),
                  );
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
                    final host = m.senderId == hostId;
                    final showEntity = m.asName != null;
                    return _Bubble(
                      message: m,
                      mine: mine,
                      showName: (showName || showEntity) && !mine,
                      senderName: showEntity ? m.asName : sender?.username,
                      avatarUrl: showEntity ? m.asLogo : sender?.avatarUrl,
                      showAvatar: !mine && ((conv?.isMeet ?? false) || showEntity),
                      host: host && !showEntity,
                    );
                  },
                );
              },
            ),
          ),
          ChatComposer(
            controller: _text,
            sending: _sending,
            onSend: _send,
            onPlus: _plus,
            onCamera: _cameraMenu,
            recording: _recording,
            cancelling: _cancelling,
            elapsed: _elapsed,
            onRecordStart: _startRecording,
            onRecordMove: (dx) {
              _dragX = dx;
              final c = _dragX < -80;
              if (c != _cancelling) setState(() => _cancelling = c);
            },
            onRecordEnd: ({required bool send}) => _stopRecording(send: send),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.showName, this.senderName, this.avatarUrl, required this.showAvatar, this.host = false});
  final Message message;
  final bool mine;
  final bool showName;
  final String? senderName;
  final String? avatarUrl;
  final bool showAvatar;
  final bool host;

  @override
  Widget build(BuildContext context) {
    final isShare = message.hasAttachment;
    final auto = message.autoBody;
    final maxW = MediaQuery.sizeOf(context).width * 0.72;

    Widget textBubble(String text) => Container(
          constraints: BoxConstraints(maxWidth: maxW),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: mine ? AppColors.surfaceGray : AppColors.surface,
            border: mine ? null : Border.all(color: AppColors.border),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: Text(text, style: TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.35)),
        );

    // A shared post / moment sits on its own, no bubble around it. A note, if any, follows underneath.
    final bubble = isShare
        ? Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.postId != null) _SharedPost(postId: message.postId!, mine: mine),
              if (message.storyId != null) _SharedMoment(storyId: message.storyId!, mine: mine),
              if (message.imageUrl != null) _Photo(url: message.imageUrl!),
              if (message.audioUrl != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: VoiceBubble(url: message.audioUrl!, ms: message.audioMs ?? 0, mine: mine)),
              if (message.videoUrl != null) VideoBubble(url: message.videoUrl!),
              if (message.sticker != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: ArtIcon(kStickers[message.sticker!] ?? AppArt.car, size: 96)),
              if (message.eventId != null) _SharedEvent(eventId: message.eventId!),
              if (message.placeId != null) _SharedPlace(placeId: message.placeId!),
              if (message.carId != null) _SharedCar(carId: message.carId!),
              if (!auto) textBubble(message.body),
            ],
          )
        : textBubble(message.body);
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
                  Text(senderName ?? '', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
              if (showAvatar) ...[UserAvatar(url: avatarUrl, name: senderName, size: 28), const SizedBox(width: 6)],
              Tooltip(message: formatEventDate(message.createdAt), child: bubble),
            ],
          ),
        ],
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
    final who = hosting ? 'You\'re hosting' : 'Hosted by ${e.vendorName ?? d.organizer?.displayName ?? d.organizer?.username ?? 'the organiser'}';
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


/// A photo sent in chat. Tap to see it full screen.
class _Photo extends StatelessWidget {
  const _Photo({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          barrierColor: Colors.black,
          builder: (ctx) => GestureDetector(onTap: () => Navigator.pop(ctx), child: InteractiveViewer(child: Center(child: Image.network(url)))),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 320),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
          child: Image.network(url, fit: BoxFit.cover),
        ),
      );
}

/// Small card shared for a meet, a spot or a car. Same shape for all three.
class _Card extends StatelessWidget {
  const _Card({required this.image, required this.fallback, required this.eyebrow, required this.title, required this.subtitle, required this.onTap});
  final String? image;
  final String fallback;
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
                child: image == null ? ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(fallback, size: 34))) : Image.network(image!, fit: BoxFit.cover),
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
      fallback: p?.kindArt ?? AppArt.pin,
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
      eyebrow: 'CAR',
      title: c == null ? 'Car' : '${c.make} ${c.model}',
      subtitle: c?.year?.toString(),
      onTap: () => context.push(Routes.car(carId)),
    );
  }
}
