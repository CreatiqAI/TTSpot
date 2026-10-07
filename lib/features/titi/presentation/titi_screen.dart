import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/guide/guide.dart';
import '../../../core/guide/guide_on_first_view.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../social/presentation/widgets/chat_media.dart' show ChatTimePill;
import '../application/titi_controller.dart';
import '../domain/titi_message.dart';
import 'titi_answer.dart';
import 'titi_background.dart';
import 'titi_sessions_sheet.dart';
import '../../guides/home_guides.dart';

/// Chat with TiTi, the app's assistant: meets, spots, clubs, the member's own
/// points, vouchers, cards, meets and car papers, one-tap actions, photos,
/// app how-to and car talk. Answers type out as bubbles and cards; follow-up
/// chips sit under the latest one. Past chats live behind the history button.
class TitiScreen extends ConsumerStatefulWidget {
  const TitiScreen({super.key});

  @override
  ConsumerState<TitiScreen> createState() => _TitiScreenState();
}

class _TitiScreenState extends ConsumerState<TitiScreen> {
  final _text = TextEditingController();

  /// Photos picked for the next question, and their bytes for the preview.
  final _photos = <XFile>[];
  final _previews = <Uint8List>[];
  static const _maxPhotos = 4;

  /// Photos go up at about this size, like the app's other uploads.
  static const _photoSide = 1280.0;

  // The list. A new chat (state.view) gets a fresh controller at the bottom.
  var _scroll = ScrollController();
  var _view = -1;

  /// Messages already there when this list was made (coming back to TiTi
  /// mid-chat): they sit above the anchor like loaded history, so the list
  /// opens at the bottom.
  var _screenBase = 0;
  static const _center = ValueKey('titi-center');

  /// Follow new words to the bottom. Off once the member scrolls up to read,
  /// back on when they return to the bottom or send something.
  var _stick = true;
  var _followQueued = false;
  var _animating = false;
  var _animToken = 0;
  var _showDown = false;

  static const _starters = ['How many points do I have?', 'Meets this weekend near me', 'When is my road tax due?', 'Fuel price this week'];

  @override
  void initState() {
    super.initState();
    // Every way in (the Chats row, "Ask TiTi") lands on the latest chat.
    Future.microtask(() => ref.read(titiControllerProvider.notifier).ensureLatest());
  }

  @override
  void dispose() {
    _followLater?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- send

  Future<void> _pick() async {
    final room = _maxPhotos - _photos.length;
    if (room <= 0) return;
    final source = await showPhotoSourceSheet(context);
    if (source == null) return;
    final picker = ImagePicker();
    final List<XFile> files;
    if (source == ImageSource.gallery && room > 1) {
      files = (await picker.pickMultiImage(maxWidth: _photoSide, maxHeight: _photoSide, imageQuality: 82, limit: room)).take(room).toList();
    } else {
      final f = await picker.pickImage(source: source, maxWidth: _photoSide, maxHeight: _photoSide, imageQuality: 82);
      files = f == null ? const [] : [f];
    }
    if (files.isEmpty) return;
    final bytes = await Future.wait(files.map((f) => f.readAsBytes()));
    if (!mounted) return;
    setState(() {
      _photos.addAll(files);
      _previews.addAll(bytes);
    });
  }

  void _removePhoto(int i) => setState(() {
        _photos.removeAt(i);
        _previews.removeAt(i);
      });

  void _send([String? pick]) {
    final t = (pick ?? _text.text).trim();
    final photos = pick == null ? List<XFile>.of(_photos) : const <XFile>[];
    if ((t.isEmpty && photos.isEmpty) || ref.read(titiControllerProvider).streaming) return;
    if (pick == null) {
      _text.clear();
      setState(() {
        _photos.clear();
        _previews.clear();
      });
    }
    ref.read(titiControllerProvider.notifier).send(t, photos: photos);
    _follow(force: true);
  }

  // -------------------------------------------------------------- scroll

  /// Glide to the newest line when the member is at (or was just sent to)
  /// the bottom. Never a jump, and one gentle glide at a time: growth while
  /// one is under way is picked up when it ends.
  void _follow({bool force = false}) {
    if (force) _stick = true;
    if (!_stick) return;
    final since = DateTime.now().difference(_followedAt);
    if (!force && _animating && since < _followEvery) {
      _followLater ??= Timer(_followEvery - since, () {
        _followLater = null;
        if (mounted) _follow();
      });
      return;
    }
    if (_followQueued) return;
    _followQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followQueued = false;
      if (!mounted || !_scroll.hasClients) return;
      final p = _scroll.positions.last;
      final gap = p.pixels - p.minScrollExtent;
      if (gap.abs() < 0.5) return;
      final token = ++_animToken;
      _animating = true;
      _followedAt = DateTime.now();
      final ms = (220 + gap.abs() * 0.4).clamp(260, 480).round();
      p.animateTo(p.minScrollExtent, duration: Duration(milliseconds: ms), curve: Curves.easeOutCubic).whenComplete(() {
        if (token == _animToken) _animating = false;
      });
    });
  }

  static const _followEvery = Duration(milliseconds: 260);
  Timer? _followLater;
  var _followedAt = DateTime(0);

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    final fromBottom = n.metrics.pixels - n.metrics.minScrollExtent;
    // The member's own scrolling decides; the list's own glide doesn't.
    final user = n is ScrollUpdateNotification && n.dragDetails != null;
    if (user || (!_animating && (n is ScrollUpdateNotification || n is ScrollEndNotification))) _stick = fromBottom < 72;
    _setDown(fromBottom);
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    if (n.depth == 0) _setDown(n.metrics.pixels - n.metrics.minScrollExtent);
    return false;
  }

  void _setDown(double fromBottom) {
    final down = fromBottom > 240;
    if (down != _showDown) setState(() => _showDown = down);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(titiControllerProvider);
    final c = ref.read(titiControllerProvider.notifier);
    // New items (a question, an answer starting): glide down to them.
    ref.listen(titiControllerProvider.select((s) => s.messages.length), (a, b) {
      if ((b) > (a ?? 0)) _follow();
    });
    if (s.view != _view) {
      // Another chat: a fresh list, starting at its newest message.
      final old = _scroll;
      _scroll = ScrollController();
      if (_view != -1) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      _view = s.view;
      _screenBase = s.messages.length;
      _stick = true;
      _showDown = false;
    }

    // First chat with TiTi: what he can do, once the history is in.
    return GuideOnFirstView(
      id: GuideIds.titiChat,
      ready: !s.loading,
      build: () => titiChatGuide(starters: ref.read(titiControllerProvider).messages.isEmpty),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
          titleSpacing: 0,
          title: Row(
            children: [
              const TitiAvatar(TitiPose.chat, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TiTi', style: AppText.screenTitle),
                    const _Subtitle(),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(tooltip: 'Past chats', icon: const Icon(AppIcons.clockCounterClockwise), onPressed: () => showTitiSessions(context)),
            IconButton(
              tooltip: 'New chat',
              icon: const Icon(AppIcons.notePencil),
              onPressed: s.messages.isEmpty && s.sessionId == null ? null : c.newChat,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: TitiBackground(
                child: Stack(
                  children: [
                    Positioned.fill(child: _list(s, c)),
                    // Nothing yet: TiTi says hi, with starters. Fades out on the first question.
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: s.messages.isNotEmpty || s.loading,
                        child: AnimatedOpacity(
                          opacity: s.messages.isEmpty && !s.loading ? 1 : 0,
                          duration: const Duration(milliseconds: 220),
                          child: _Empty(starters: _starters, onPick: _send, error: s.loadError, onReload: c.reload),
                        ),
                      ),
                    ),
                    if (s.loading && s.messages.isEmpty) const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    // Scrolled up: a quick way back to the newest message.
                    Positioned(
                      right: 14,
                      bottom: 10,
                      child: IgnorePointer(
                        ignoring: !_showDown,
                        child: AnimatedScale(
                          scale: _showDown ? 1 : 0.6,
                          duration: const Duration(milliseconds: 180),
                          child: AnimatedOpacity(
                            opacity: _showDown ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: Material(
                              color: AppColors.surface,
                              shape: CircleBorder(side: BorderSide(color: AppColors.border)),
                              elevation: 2,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _follow(force: true),
                                child: SizedBox(width: 40, height: 40, child: Icon(AppIcons.arrowDown, size: 18, color: AppColors.textPrimary)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _Composer(
              controller: _text,
              streaming: s.streaming,
              previews: _previews,
              canAttach: _photos.length < _maxPhotos,
              onAttach: _pick,
              onRemovePhoto: _removePhoto,
              onSend: _send,
              onStop: c.stop,
            ),
          ],
        ),
      ),
    );
  }

  /// The chat, anchored between what was there when it opened (above, drawn
  /// bottom-up) and what came since (below, top-down). New words grow the
  /// lower part downwards, so whatever the member is reading stays put;
  /// [_follow] glides the view down with them when they're at the bottom.
  Widget _list(TitiState s, TitiController c) {
    final base = math.min(math.max(s.base, _screenBase), s.messages.length);
    final last = s.messages.isEmpty ? null : s.messages.last;
    Widget row(int i) {
      final m = s.messages[i];
      final fresh = i >= base;
      if (m.mine) return fresh ? TitiAppear(key: ValueKey(m.key), child: _Mine(m)) : _Mine(m, key: ValueKey(m.key));
      return TitiAnswer(m, key: ValueKey(m.key), latest: i == s.messages.length - 1, onChip: _send, onRetry: c.retry);
    }

    // Oldest first, with a day pill wherever the date changes. An answer
    // still coming has no time yet and stays under the day before it.
    final loaded = <Widget>[];
    final fresh = <Widget>[];
    DateTime? day;
    for (var i = 0; i < s.messages.length; i++) {
      final part = i < base ? loaded : fresh;
      final at = s.messages[i].at;
      if (at != null && (day == null || !isSameDay(day, at))) {
        final key = ValueKey('day-${DateUtils.dateOnly(at)}');
        part.add(i < base ? TitiDayPill(at, key: key) : TitiAppear(key: key, child: TitiDayPill(at)));
        day = at;
      }
      part.add(row(i));
    }
    // A question that never got its answer.
    if (!s.streaming && last != null && last.mine) {
      final retry = Padding(
        key: const ValueKey('no-answer'),
        padding: const EdgeInsets.only(bottom: 8),
        child: TitiErrorRow(text: 'TiTi didn\'t answer that one.', onRetry: c.retry),
      );
      (fresh.isEmpty ? loaded : fresh).add(retry);
    }

    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _follow();
        return true;
      },
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            key: ValueKey('titi-list-${s.view}'),
            controller: _scroll,
            reverse: true,
            center: _center,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              // Below the anchor: what came since, oldest first, growing down.
              SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, fresh.isEmpty ? 0 : 8),
                sliver: SliverList.builder(itemCount: fresh.length, itemBuilder: (_, i) => fresh[i]),
              ),
              // The anchor and above: the chat as it was, newest first, growing up.
              SliverPadding(
                key: _center,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                sliver: SliverList.builder(itemCount: loaded.length, itemBuilder: (_, i) => loaded[loaded.length - 1 - i]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Thinking…" / "Typing…" while an answer comes, else the chat's title.
class _Subtitle extends ConsumerWidget {
  const _Subtitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (streaming, thinking, title) = ref.watch(titiControllerProvider.select((s) => (s.streaming, s.thinking, s.title)));
    final text = streaming ? (thinking ? 'Thinking…' : 'Typing…') : (title ?? 'Your pit crew · AI');
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
      child: Text(
        text,
        key: ValueKey(text),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: streaming ? AppColors.brand : AppColors.textSecondary),
      ),
    );
  }
}

// ------------------------------------------------------------- messages ---

class _Mine extends StatelessWidget {
  const _Mine(this.m, {super.key});
  final TitiMessage m;

  @override
  Widget build(BuildContext context) {
    final text = m.text.trim();
    final time = m.at == null ? null : formatTime(m.at!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Photos only: the time sits on the last one.
          if (m.images.isNotEmpty) _Photos(m.images, time: text.isEmpty ? time : null),
          if (m.images.isNotEmpty && text.isNotEmpty) const SizedBox(height: 4),
          if (text.isNotEmpty)
            Container(
              constraints: BoxConstraints(maxWidth: titiMaxBubble(context)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: TitiBackground.mineFill,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(4)),
              ),
              child: time == null ? _words(text) : Stack(children: [_words(text, room: titiTimeRoom(context, time)), Positioned(right: 0, bottom: 0, child: TitiTime(time))]),
            ),
        ],
      ),
    );
  }

  /// The question, keeping [room] free at the end of its last line for the time.
  Widget _words(String text, {Size? room}) => Text.rich(
        TextSpan(children: [
          TextSpan(text: text),
          if (room != null) WidgetSpan(alignment: PlaceholderAlignment.bottom, child: SizedBox.fromSize(size: room)),
        ]),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.35),
      );
}

/// My photos in a question: one big, or a 2-wide grid. Tap to see one full screen.
class _Photos extends StatelessWidget {
  const _Photos(this.images, {this.time});
  final List<TitiImage> images;
  final String? time;

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) return _Photo(images.first, width: 200, height: 220, time: time);
    return SizedBox(
      width: 224,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var i = 0; i < images.length; i++) _Photo(images[i], width: 110, height: 110, time: i == images.length - 1 ? time : null),
        ],
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo(this.image, {required this.width, required this.height, this.time});
  final TitiImage image;
  final double width;
  final double height;

  /// Shown on the photo, bottom-right, when there are no words to hold it.
  final String? time;

  ImageProvider? get _provider {
    final bytes = image.bytes;
    if (bytes != null) return MemoryImage(bytes);
    final url = image.url;
    // Signed URLs change on every load; the path keeps the cache.
    if (url != null) return CachedNetworkImageProvider(url, cacheKey: 'titi:${image.path ?? url}');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final t = time;
    final box = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: width,
        height: height,
        color: AppColors.surfaceGray,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (provider == null)
              Icon(AppIcons.imageBroken, color: AppColors.textMuted)
            else
              Image(
                image: ResizeImage.resizeIfNeeded((width * dpr).round(), null, provider),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => Icon(AppIcons.imageBroken, color: AppColors.textMuted),
              ),
            // The same pill friend chats put on photos.
            if (t != null) Positioned(right: 8, bottom: 8, child: ChatTimePill(t)),
          ],
        ),
      ),
    );
    if (provider == null) return box;
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        barrierColor: Colors.black,
        useRootNavigator: true,
        builder: (ctx) => GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(child: Center(child: Image(image: provider, fit: BoxFit.contain))),
        ),
      ),
      child: box,
    );
  }
}

// ---------------------------------------------------------------- empty ---

class _Empty extends StatelessWidget {
  const _Empty({required this.starters, required this.onPick, required this.onReload, this.error});
  final List<String> starters;
  final ValueChanged<String> onPick;
  final VoidCallback onReload;
  final String? error;

  @override
  // Sits straight on TiTi's background (the list behind is empty).
  Widget build(BuildContext context) => SizedBox.expand(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Titi(TitiPose.wave, height: 128),
                const SizedBox(height: 14),
                TitiBubble(
                  'Hi, I\'m TiTi, your pit crew. Ask me about meets, spots, your points and car papers, or send me a photo.',
                  dark: !AppColors.dark,
                  maxWidth: 300,
                ),
                const SizedBox(height: 20),
                Wrap(
                  key: TitiChatGuideKeys.starters,
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [for (final t in starters) TitiChip(t, onTap: () => onPick(t))],
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(onPressed: onReload, icon: const Icon(AppIcons.arrowsClockwise, size: 16), label: const Text('Load our chat')),
                ],
              ],
            ),
          ),
        ),
      );
}

// ------------------------------------------------------------- composer ---

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.streaming,
    required this.previews,
    required this.canAttach,
    required this.onAttach,
    required this.onRemovePhoto,
    required this.onSend,
    required this.onStop,
  });
  final TextEditingController controller;
  final bool streaming;
  final List<Uint8List> previews;
  final bool canAttach;
  final VoidCallback onAttach;
  final ValueChanged<int> onRemovePhoto;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Photos waiting to go with the next question.
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: previews.isEmpty
                      ? const SizedBox(width: double.infinity)
                      : SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                            itemCount: previews.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (_, i) => _Preview(bytes: previews[i], onRemove: () => onRemovePhoto(i)),
                          ),
                        ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (_, v, _) {
                    final canSend = !streaming && (v.text.trim().isNotEmpty || previews.isNotEmpty);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Add a photo',
                          onPressed: canAttach && !streaming ? onAttach : null,
                          icon: Icon(AppIcons.cameraPlus, color: canAttach && !streaming ? AppColors.textPrimary : AppColors.textMuted),
                        ),
                        Expanded(
                          child: TextField(
                            key: TitiChatGuideKeys.input,
                            controller: controller,
                            minLines: 1,
                            maxLines: 5,
                            maxLength: 1000,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => onSend(),
                            decoration: InputDecoration(
                              hintText: previews.isEmpty ? 'Ask TiTi anything…' : 'Ask about the photo…',
                              counterText: '',
                              filled: true,
                              fillColor: AppColors.surfaceGray,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: AppColors.textMuted)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: streaming
                              ? _Round(key: const ValueKey('stop'), icon: AppIcons.stop, color: AppColors.textPrimary, iconColor: AppColors.onInk, tooltip: 'Stop', onTap: onStop)
                              : _Round(
                                  key: const ValueKey('send'),
                                  icon: AppIcons.paperPlaneRight,
                                  color: canSend ? AppColors.brand : AppColors.surfaceGray,
                                  iconColor: canSend ? Colors.white : AppColors.textMuted,
                                  tooltip: 'Send',
                                  onTap: canSend ? onSend : null,
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
}

/// A picked photo in the composer, with a small ✕ to take it out.
class _Preview extends StatelessWidget {
  const _Preview({required this.bytes, required this.onRemove});
  final Uint8List bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(bytes, fit: BoxFit.cover, cacheWidth: (64 * MediaQuery.devicePixelRatioOf(context)).round(), gaplessPlayback: true),
              ),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: Material(
                color: AppColors.textPrimary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: Padding(padding: const EdgeInsets.all(3), child: Icon(AppIcons.x, size: 13, color: AppColors.onInk)),
                ),
              ),
            ),
          ],
        ),
      );
}

class _Round extends StatelessWidget {
  const _Round({super.key, required this.icon, required this.color, required this.iconColor, required this.tooltip, required this.onTap});
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20, color: iconColor)),
          ),
        ),
      );
}
