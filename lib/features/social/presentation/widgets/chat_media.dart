import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';

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

/// A video message: poster frame with a play button, tap to play inline,
/// tap again to pause. Long-press for full screen. The send [time], when
/// given, sits in a pill at the bottom right.
class VideoBubble extends StatefulWidget {
  const VideoBubble({super.key, required this.url, this.time});
  final String url;
  final String? time;

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  VideoPlayerController? _c;
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await c.initialize();
      c.setLooping(false);
      c.addListener(() {
        if (mounted) setState(() {});
      });
      _c = c;
      await c.play();
    } catch (_) {
      _failed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toggle() {
    final c = _c;
    if (c == null) {
      _failed = false;
      _init();
      return;
    }
    c.value.isPlaying ? c.pause() : c.play();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ratio = c != null && c.value.isInitialized ? c.value.aspectRatio : 3 / 4;
    return GestureDetector(
      onTap: _toggle,
      onLongPress: c == null ? null : () => _fullScreen(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        constraints: const BoxConstraints(maxWidth: 240, maxHeight: 320),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: const Color(0xFF2A2D33), borderRadius: BorderRadius.circular(14)),
        child: AspectRatio(
          aspectRatio: ratio.clamp(0.5, 2.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (c != null && c.value.isInitialized) VideoPlayer(c),
              if (c == null || !c.value.isPlaying)
                Center(
                  child: _loading
                      ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), shape: BoxShape.circle),
                              child: Icon(_failed ? AppIcons.arrowsClockwise : AppIcons.play, color: AppColors.ink, size: 24),
                            ),
                            if (_failed) ...[
                              const SizedBox(height: 8),
                              const Text('Could not load. Tap to retry', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ],
                          ],
                        ),
                ),
              if (c != null && c.value.isInitialized)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: Text('${fmtMs(c.value.position.inMilliseconds)} / ${fmtMs(c.value.duration.inMilliseconds)}', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ),
                )
              else
                const Positioned(left: 8, bottom: 8, child: Icon(AppIcons.record, color: Colors.white70, size: 14)),
              if (widget.time != null) Positioned(right: 8, bottom: 8, child: ChatTimePill(widget.time!)),
            ],
          ),
        ),
      ),
    );
  }

  void _fullScreen(BuildContext context) {
    final c = _c!;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
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
