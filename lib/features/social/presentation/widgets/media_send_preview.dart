import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/config/media.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import 'chat_media.dart' show fmtMs;

/// One picked photo or video, ready to send: its caption (may be empty), and
/// for a video a JPEG still for the bubble (null if it couldn't be grabbed)
/// and its length.
class MediaSendItem {
  const MediaSendItem({required this.file, required this.isVideo, this.caption = '', this.poster, this.ms});
  final XFile file;
  final bool isVideo;
  final String caption;
  final Uint8List? poster;
  final int? ms;
}

const _videoExts = {'mp4', 'mov', 'm4v', '3gp', '3gpp', 'webm', 'mkv', 'avi'};

/// Video or photo, from the mime type when the picker gives one, else the extension.
bool isVideoFile(XFile f) {
  final mime = f.mimeType;
  if (mime != null && mime.isNotEmpty) return mime.startsWith('video/');
  final name = (f.name.isNotEmpty ? f.name : f.path).toLowerCase();
  final dot = name.lastIndexOf('.');
  return dot >= 0 && _videoExts.contains(name.substring(dot + 1));
}

/// WhatsApp-style check before photos and videos go out: full screen on
/// black, swipe between them, a thumbnail strip (X removes one, + adds more),
/// a caption per item, and a round red Send. Videos play muted. Returns what
/// to send, in order, or null when cancelled.
Future<List<MediaSendItem>?> showMediaSendPreview(BuildContext context, List<XFile> files) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<List<MediaSendItem>>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => MediaSendPreview(files: files),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

/// One item on the preview: its caption, and for a video its player and still.
class _Draft {
  _Draft(this.file) : isVideo = isVideoFile(file);
  final XFile file;
  final bool isVideo;
  final caption = TextEditingController();
  final frameKey = GlobalKey();
  VideoPlayerController? player;
  bool failed = false;
  Uint8List? poster;
  bool grabbing = false;

  int? get ms => player != null && player!.value.isInitialized ? player!.value.duration.inMilliseconds : null;

  void dispose() {
    caption.dispose();
    player?.dispose();
  }
}

class MediaSendPreview extends StatefulWidget {
  const MediaSendPreview({super.key, required this.files});
  final List<XFile> files;

  @override
  State<MediaSendPreview> createState() => _MediaSendPreviewState();
}

class _MediaSendPreviewState extends State<MediaSendPreview> {
  late final List<_Draft> _items = [for (final f in widget.files.take(kChatMediaMaxItems)) _Draft(f)];
  final _pages = PageController();
  int _page = 0;
  bool _muted = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    if (_items.isNotEmpty) _show(0);
  }

  @override
  void dispose() {
    for (final d in _items) {
      d.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  _Draft get _current => _items[_page.clamp(0, _items.length - 1)];

  /// Bring item [i] up: its video (if it is one) plays, every other one pauses.
  Future<void> _show(int i) async {
    for (var j = 0; j < _items.length; j++) {
      if (j != i) _items[j].player?.pause();
    }
    final d = _items[i];
    if (!d.isVideo || d.failed) return;
    if (d.player == null) {
      final c = VideoPlayerController.file(File(d.file.path));
      d.player = c;
      c.addListener(() => _onTick(d));
      try {
        await c.initialize();
        await c.setLooping(true);
        await c.setVolume(_muted ? 0 : 1);
      } catch (_) {
        d.failed = true;
        if (mounted) setState(() {});
        return;
      }
      if (mounted) setState(() {});
    }
    if (mounted && _items.indexOf(d) == _page) await d.player!.play();
  }

  void _onTick(_Draft d) {
    if (!mounted) return;
    final c = d.player!;
    // A frame from just after the start makes the still, like WhatsApp's.
    if (d.poster == null && !d.grabbing && c.value.isPlaying && c.value.position >= const Duration(milliseconds: 250)) {
      d.grabbing = true;
      _grab(d).then((b) {
        d.poster = b;
        d.grabbing = false;
        if (mounted) setState(() {});
      });
    }
    if (identical(d, _current)) setState(() {});
  }

  /// The video frame on screen as a JPEG (long side ~720 px), or null when
  /// the capture comes back blank (some phones can't read the video surface).
  Future<Uint8List?> _grab(_Draft d) async {
    try {
      final boundary = d.frameKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) return null;
      final longest = math.max(boundary.size.width, boundary.size.height);
      if (longest <= 0) return null;
      final img = await boundary.toImage(pixelRatio: 720 / longest);
      try {
        final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (raw == null || _blank(raw)) return null;
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) return null;
        return await FlutterImageCompress.compressWithList(png.buffer.asUint8List(), minWidth: img.width, minHeight: img.height, quality: 80, format: CompressFormat.jpeg);
      } finally {
        img.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Nearly every sampled pixel black or see-through: the capture missed the video.
  static bool _blank(ByteData rgba) {
    final n = rgba.lengthInBytes ~/ 4;
    if (n == 0) return true;
    final step = math.max(1, n ~/ 2000);
    var lit = 0, seen = 0;
    for (var i = 0; i < n; i += step) {
      final o = i * 4;
      seen++;
      if (rgba.getUint8(o + 3) > 0 && rgba.getUint8(o) + rgba.getUint8(o + 1) + rgba.getUint8(o + 2) > 36) lit++;
    }
    return lit < seen * 0.02;
  }

  void _goTo(int i) {
    if (i == _page) return;
    _pages.animateToPage(i, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
  }

  void _remove(int i) {
    final d = _items.removeAt(i);
    d.dispose();
    if (_items.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final next = math.min(_page > i ? _page - 1 : _page, _items.length - 1);
    setState(() => _page = next);
    if (_pages.hasClients) _pages.jumpToPage(next);
    _show(next);
  }

  Future<void> _addMore() async {
    final room = kChatMediaMaxItems - _items.length;
    if (room <= 0) return;
    for (final d in _items) {
      d.player?.pause();
    }
    final picked = await ImagePicker().pickMultipleMedia(maxWidth: 1600, maxHeight: 1600, imageQuality: 85, limit: room);
    if (!mounted) return;
    var tooBig = false;
    final add = <_Draft>[];
    for (final f in picked.take(room)) {
      final d = _Draft(f);
      if (d.isVideo && await f.length() > kChatVideoMaxMb * 1024 * 1024) {
        tooBig = true;
        d.dispose();
        continue;
      }
      add.add(d);
    }
    if (!mounted) return;
    if (tooBig) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Left out a video over $kChatVideoMaxMb MB.')));
    if (add.isEmpty) {
      _show(_page);
      return;
    }
    final first = _items.length;
    setState(() => _items.addAll(add));
    // After the PageView has grown to include them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pages.hasClients) _pages.jumpToPage(first);
    });
  }

  Future<void> _send() async {
    if (_sending || _items.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    // Videos never brought up have no still yet: show each briefly to grab one.
    for (var i = 0; i < _items.length; i++) {
      final d = _items[i];
      if (!d.isVideo || d.failed || d.poster != null) continue;
      if (_page != i) {
        _pages.jumpToPage(i);
        setState(() => _page = i);
      }
      await _show(i);
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (mounted && d.poster == null && !d.failed && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (d.poster == null && !d.failed) {
        await d.player?.pause();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        d.poster = await _grab(d);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop([
      for (final d in _items) MediaSendItem(file: d.file, isVideo: d.isVideo, caption: d.caption.text.trim(), poster: d.poster, ms: d.ms),
    ]);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    for (final d in _items) {
      d.player?.setVolume(_muted ? 0 : 1);
    }
  }

  void _togglePlay(_Draft d) {
    final c = d.player;
    if (c == null || !c.value.isInitialized) return;
    c.value.isPlaying ? c.pause() : c.play();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const ColoredBox(color: Colors.black);
    final d = _current;
    final c = d.player;
    final ready = c != null && c.value.isInitialized;
    // The caption bar rides on top of the keyboard; the photo stays put behind it.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _pages,
                itemCount: _items.length,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  _show(i);
                },
                itemBuilder: (_, i) => _Page(draft: _items[i], onTap: () => _togglePlay(_items[i])),
              ),
            ),
            // Top: cancel, and the sound switch for a video.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent])),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                    child: Row(
                      children: [
                        IconButton(tooltip: 'Cancel', icon: const Icon(AppIcons.x, color: Colors.white, size: 24), onPressed: _sending ? null : () => Navigator.of(context).pop()),
                        Expanded(
                          child: Text(
                            _items.length > 1 ? '${_page + 1} of ${_items.length}' : '',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (d.isVideo && ready)
                          IconButton(tooltip: _muted ? 'Unmute' : 'Mute', icon: Icon(_muted ? AppIcons.speakerSlash : AppIcons.speakerHigh, color: Colors.white, size: 22), onPressed: _toggleMute)
                        else
                          const SizedBox(width: 48),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Bottom: video progress, thumbnails, caption and Send, above the keyboard.
            Positioned(
              left: 0,
              right: 0,
              bottom: keyboard,
              child: DecoratedBox(
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.black54, Colors.transparent], stops: [0, 0.7, 1])),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (d.isVideo && ready) ...[
                          Row(
                            children: [
                              Expanded(
                                child: VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 8), colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white24, backgroundColor: Colors.white12)),
                              ),
                              const SizedBox(width: 10),
                              Text(fmtMs(c.value.duration.inMilliseconds), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (keyboard == 0) ...[
                          SizedBox(
                            height: 62,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (var i = 0; i < _items.length; i++)
                                  _Thumb(draft: _items[i], selected: i == _page, onTap: () => _goTo(i), onRemove: _sending ? null : () => _remove(i)),
                                if (_items.length < kChatMediaMaxItems)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6, left: 2),
                                    child: Material(
                                      color: Colors.white12,
                                      borderRadius: BorderRadius.circular(10),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: _sending ? null : _addMore,
                                        child: const SizedBox(width: 54, height: 54, child: Icon(AppIcons.plus, color: Colors.white, size: 24)),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(color: const Color(0xFF22262D), borderRadius: BorderRadius.circular(24)),
                                child: TextField(
                                  // A fresh field per item: each one keeps its own caption.
                                  key: ObjectKey(d),
                                  controller: d.caption,
                                  enabled: !_sending,
                                  minLines: 1,
                                  maxLines: 4,
                                  maxLength: 1000,
                                  textCapitalization: TextCapitalization.sentences,
                                  cursorColor: Colors.white,
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                  decoration: const InputDecoration(
                                    hintText: 'Add a caption…',
                                    hintStyle: TextStyle(color: Colors.white54),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    filled: false,
                                    isDense: true,
                                    counterText: '',
                                    contentPadding: EdgeInsets.symmetric(vertical: 13),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Semantics(
                              button: true,
                              label: 'Send',
                              child: Material(
                                color: AppColors.brand,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _sending ? null : _send,
                                  child: SizedBox(
                                    width: 50,
                                    height: 50,
                                    child: Center(
                                      child: _sending
                                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Icon(AppIcons.paperPlaneRight, color: Colors.white, size: 22),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One full-screen item: the photo, or the video (tap to pause / play).
class _Page extends StatelessWidget {
  const _Page({required this.draft, required this.onTap});
  final _Draft draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!draft.isVideo) {
      return Image.file(File(draft.file.path), fit: BoxFit.contain, errorBuilder: (_, _, _) => const Center(child: Icon(AppIcons.imageBroken, color: Colors.white54, size: 40)));
    }
    final c = draft.player;
    final ready = c != null && c.value.isInitialized;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (ready)
            Center(
              child: RepaintBoundary(
                key: draft.frameKey,
                child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
              ),
            )
          else if (draft.failed)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Can\'t preview this video here, but you can still send it.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14)),
            )
          else
            const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          if (ready && !c.value.isPlaying)
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: const Icon(AppIcons.play, color: Colors.white, size: 30),
            ),
        ],
      ),
    );
  }
}

/// A thumbnail in the strip: tap to look at it, X to leave it out.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.draft, required this.selected, required this.onTap, required this.onRemove});
  final _Draft draft;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final poster = draft.poster;
    final Widget still = !draft.isVideo
        ? Image.file(File(draft.file.path), fit: BoxFit.cover, cacheWidth: 160, errorBuilder: (_, _, _) => const SizedBox())
        : poster != null
            ? Image.memory(poster, fit: BoxFit.cover, cacheWidth: 160)
            : const ColoredBox(color: Color(0xFF2A2D33));
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 60,
        height: 62,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 6,
              child: GestureDetector(
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 54,
                  height: 54,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      still,
                      if (draft.isVideo) const Positioned(left: 4, bottom: 3, child: Icon(AppIcons.videoCamera, color: Colors.white, size: 14)),
                    ],
                  ),
                ),
              ),
            ),
            if (onRemove != null)
              Positioned(
                right: 0,
                top: 0,
                child: Semantics(
                  button: true,
                  label: 'Remove',
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: Colors.black87, shape: BoxShape.circle, border: Border.all(color: Colors.white70)),
                      child: const Icon(AppIcons.x, color: Colors.white, size: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
