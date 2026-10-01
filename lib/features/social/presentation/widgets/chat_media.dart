import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/video_viewer.dart';

String fmtMs(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// The send time as a dark pill, over the bottom-right of a photo or video.
class ChatTimePill extends StatelessWidget {
  const ChatTimePill(this.time, {super.key});
  final String time;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text(time, maxLines: 1, softWrap: false, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

/// A video message: a still of the video with a play button, its length and
/// the send [time]. The still is the [poster] captured when it was sent; older
/// videos without one load their first frame (only once the bubble is built).
/// Tap to open it full screen, where it plays.
class VideoBubble extends StatefulWidget {
  const VideoBubble({super.key, required this.url, this.time, this.poster, this.ms});
  final String url;
  final String? time;
  final String? poster;
  final int? ms;

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  // Shapes already measured, so a bubble scrolled back into view keeps its size.
  static final _ratios = <String, double>{};

  // Only for videos without a poster: holds the first frame, and plays full screen.
  VideoPlayerController? _c;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  // One flight per bubble, so two bubbles of the same video never share a tag.
  final _hero = Object();
  // While the full-screen viewer plays [_c], it is disposed only once the viewer closes.
  bool _lent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream == null && _c == null) _load();
  }

  @override
  void didUpdateWidget(VideoBubble old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.poster != widget.poster) {
      _unload();
      _load();
    }
  }

  @override
  void dispose() {
    _unload();
    super.dispose();
  }

  void _load() {
    final poster = widget.poster;
    if (poster != null) {
      // Read the poster's shape as it loads (the bubble shows it as it arrives).
      final stream = CachedNetworkImageProvider(poster).resolve(createLocalImageConfiguration(context));
      final listener = ImageStreamListener((info, _) {
        final r = info.image.width / info.image.height;
        if (mounted && _ratios[widget.url] != r) setState(() => _ratios[widget.url] = r);
      }, onError: (_, _) {});
      stream.addListener(listener);
      _stream = stream;
      _listener = listener;
    } else {
      _firstFrame();
    }
  }

  void _unload() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    _stream = null;
    _listener = null;
    if (!_lent) _c?.dispose();
    _c = null;
  }

  Future<void> _firstFrame() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c = c;
    try {
      await c.initialize();
      // Some players draw nothing until the first seek; 100 ms in is a real frame.
      await c.seekTo(const Duration(milliseconds: 100));
    } catch (_) {
      return; // the play button still opens it; the viewer says if it can't play
    }
    if (!mounted || _c != c) return;
    setState(() => _ratios[widget.url] = c.value.aspectRatio);
  }

  void _open() {
    final c = _c;
    final lend = c != null && c.value.isInitialized;
    _lent = lend;
    showVideoViewer(
      context,
      url: widget.url,
      posterUrl: widget.poster,
      heroTag: _hero,
      controller: lend ? c : null,
      aspectRatio: _ratios[widget.url],
    ).whenComplete(() {
      if (!lend) return;
      _lent = false;
      // The bubble went away while the video was full screen: let the viewer finish closing first.
      if (_c != c) Future<void>.delayed(const Duration(milliseconds: 600), c.dispose);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final frame = c != null && c.value.isInitialized;
    final ratio = (_ratios[widget.url] ?? 3 / 4).clamp(0.5, 2.0);
    final ms = widget.ms ?? (frame ? c.value.duration.inMilliseconds : null);
    final still = widget.poster != null
        ? CachedNetworkImage(imageUrl: widget.poster!, fit: BoxFit.cover, fadeInDuration: const Duration(milliseconds: 120), errorWidget: (_, _, _) => const SizedBox())
        : frame
            ? FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: 100 * c.value.aspectRatio, height: 100, child: VideoPlayer(c)))
            : const SizedBox();
    return GestureDetector(
      onTap: _open,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        constraints: const BoxConstraints(maxWidth: 240, maxHeight: 320),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: const Color(0xFF2A2D33), borderRadius: BorderRadius.circular(14)),
        child: AspectRatio(
          aspectRatio: ratio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(tag: _hero, flightShuttleBuilder: videoHeroShuttle, child: still),
              // Dark glass with a white ring: reads on light and dark frames alike.
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(AppIcons.play, color: Colors.white, size: 24),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.videoCamera, color: Colors.white, size: 13),
                      if (ms != null && ms > 0) ...[
                        const SizedBox(width: 4),
                        Text(fmtMs(ms), maxLines: 1, softWrap: false, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ),
              ),
              if (widget.time != null) Positioned(right: 8, bottom: 8, child: ChatTimePill(widget.time!)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The red "recording" strip that replaces the composer while you hold the mic.
class RecordingBar extends StatelessWidget {
  const RecordingBar({super.key, required this.elapsed, required this.cancelling});
  final Duration elapsed;
  final bool cancelling;

  @override
  Widget build(BuildContext context) => Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: cancelling ? AppColors.surfaceGray : AppColors.brand, borderRadius: BorderRadius.circular(24)),
        child: Row(
          children: [
            Icon(AppIcons.record, color: cancelling ? AppColors.textSecondary : Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(fmtMs(elapsed.inMilliseconds), style: TextStyle(color: cancelling ? AppColors.textSecondary : Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
            const Spacer(),
            Text(cancelling ? 'Release to cancel' : '← Slide to cancel · release to send', style: TextStyle(color: cancelling ? AppColors.textSecondary : Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
