import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';

String fmtMs(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// A voice note bubble: play / pause, a progress bar, and the length.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({super.key, required this.url, required this.ms, required this.mine});
  final String url;
  final int ms;
  final bool mine;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _pos;
  StreamSubscription<PlayerState>? _state;
  Duration _at = Duration.zero;
  bool _playing = false;
  bool _loading = false;

  @override
  void dispose() {
    _pos?.cancel();
    _state?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_player == null) {
      setState(() => _loading = true);
      final p = AudioPlayer();
      try {
        await p.setUrl(widget.url);
      } catch (_) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      _player = p;
      _pos = p.positionStream.listen((d) {
        if (mounted) setState(() => _at = d);
      });
      _state = p.playerStateStream.listen((s) {
        if (!mounted) return;
        if (s.processingState == ProcessingState.completed) {
          p.seek(Duration.zero);
          p.pause();
          setState(() {
            _playing = false;
            _at = Duration.zero;
          });
        } else {
          setState(() => _playing = s.playing);
        }
      });
      if (mounted) setState(() => _loading = false);
    }
    final p = _player!;
    if (p.playing) {
      await p.pause();
    } else {
      await p.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.textPrimary;
    final total = widget.ms <= 0 ? (_player?.duration?.inMilliseconds ?? 1) : widget.ms;
    final frac = (_at.inMilliseconds / total).clamp(0.0, 1.0);
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
      decoration: BoxDecoration(
        color: widget.mine ? AppColors.surfaceGray : AppColors.surface,
        border: widget.mine ? null : Border.all(color: AppColors.border),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.mine ? 18 : 4),
          bottomRight: Radius.circular(widget.mine ? 4 : 18),
        ),
      ),
      child: Row(
        children: [
          Material(
            color: AppColors.surface,
            shape: CircleBorder(side: BorderSide(color: widget.mine ? Colors.transparent : AppColors.border)),
            elevation: widget.mine ? 1 : 0,
            shadowColor: Colors.black26,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _loading ? null : _toggle,
              child: SizedBox(
                width: 36,
                height: 36,
                child: _loading
                    ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_playing ? AppIcons.pause : AppIcons.play, size: 18, color: AppColors.textPrimary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: frac, minHeight: 4, backgroundColor: fg.withValues(alpha: 0.12), color: fg.withValues(alpha: 0.75)),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(AppIcons.record, size: 12, color: fg.withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Text(_playing ? fmtMs(_at.inMilliseconds) : fmtMs(total), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg.withValues(alpha: 0.85))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A video message: poster frame with a play button, tap to play inline,
/// tap again to pause. Long-press for full screen.
class VideoBubble extends StatefulWidget {
  const VideoBubble({super.key, required this.url});
  final String url;

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
