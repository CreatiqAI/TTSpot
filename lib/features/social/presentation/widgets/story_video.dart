import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Plays a video moment in the viewer. Reports the length once it knows it,
/// so the progress bar can match, and obeys [paused] for hold-to-pause.
class StoryVideo extends StatefulWidget {
  const StoryVideo({super.key, required this.url, required this.paused, required this.onReady, required this.onEnded, this.posterUrl});
  final String url;
  final String? posterUrl;
  final bool paused;
  final ValueChanged<Duration> onReady;
  final VoidCallback onEnded;

  @override
  State<StoryVideo> createState() => _StoryVideoState();
}

class _StoryVideoState extends State<StoryVideo> {
  VideoPlayerController? _c;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      c.setLooping(false);
      c.addListener(_tick);
      _c = c;
      widget.onReady(c.value.duration);
      if (!widget.paused) c.play();
      setState(() {});
    } catch (_) {
      // Poster stays; the timer still moves on.
      widget.onReady(const Duration(seconds: 5));
    }
  }

  void _tick() {
    final c = _c;
    if (c == null || !mounted) return;
    if (!_ended && c.value.isInitialized && !c.value.isPlaying && c.value.position >= c.value.duration - const Duration(milliseconds: 150)) {
      _ended = true;
      widget.onEnded();
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant StoryVideo old) {
    super.didUpdateWidget(old);
    final c = _c;
    if (c == null) return;
    if (widget.paused && c.value.isPlaying) c.pause();
    if (!widget.paused && !c.value.isPlaying && !_ended) c.play();
  }

  @override
  void dispose() {
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !c.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (widget.posterUrl != null) Image.network(widget.posterUrl!, fit: BoxFit.contain),
          const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        ],
      );
    }
    return Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)));
  }
}
