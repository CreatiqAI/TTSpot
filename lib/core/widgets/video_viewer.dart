import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_icons.dart';

/// Full-screen video on black. It starts playing straight away; tap for the
/// controls (play / pause, a scrubber with elapsed and total time, mute,
/// close), pull it up or down to close, like the photo viewer.
///
/// [posterUrl] shows until the first frame is ready. [heroTag] flies the
/// still in from the bubble that opened it. Pass [controller] to play a
/// video that is already loaded (it is borrowed: paused and rewound on close,
/// never disposed here).
Future<void> showVideoViewer(
  BuildContext context, {
  required String url,
  String? posterUrl,
  Object? heroTag,
  VideoPlayerController? controller,
  double? aspectRatio,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      // See-through, so the chat shows as the black fades on a pull.
      opaque: false,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => VideoViewer(url: url, posterUrl: posterUrl, heroTag: heroTag, controller: controller, aspectRatio: aspectRatio),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

/// The Hero flight between a rounded video bubble and the full-screen video:
/// the corners square off on the way out and round again on the way back.
Widget videoHeroShuttle(BuildContext _, Animation<double> anim, HeroFlightDirection dir, BuildContext from, BuildContext to) {
  final hero = (dir == HeroFlightDirection.push ? to.widget : from.widget) as Hero;
  return AnimatedBuilder(
    animation: anim,
    builder: (_, child) => ClipRRect(borderRadius: BorderRadius.circular(14 * (1 - anim.value)), child: child),
    child: hero.child,
  );
}

class VideoViewer extends StatefulWidget {
  const VideoViewer({super.key, required this.url, this.posterUrl, this.heroTag, this.controller, this.aspectRatio});
  final String url;
  final String? posterUrl;
  final Object? heroTag;
  final VideoPlayerController? controller;
  final double? aspectRatio;

  @override
  State<VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<VideoViewer> with SingleTickerProviderStateMixin {
  late final VideoPlayerController _c = widget.controller ?? VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool get _borrowed => widget.controller != null;
  bool _failed = false;
  bool _controls = true;
  bool _muted = false;
  Timer? _hide;

  // Scrubbing: where the thumb is, and whether to carry on playing after.
  double? _scrubMs;
  bool _playAfterScrub = false;

  /// Released past this far, or flung faster than [_flingAt], it closes;
  /// otherwise the video springs back.
  static const _closeAt = 110.0;
  static const _flingAt = 800.0;
  final _pull = ValueNotifier<double>(0);
  late final _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  Animation<double>? _settleTo;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      final to = _settleTo;
      if (to != null) _pull.value = to.value;
    });
    _c.addListener(_onTick);
    _start();
  }

  Future<void> _start() async {
    try {
      if (!_c.value.isInitialized) await _c.initialize();
      if (!mounted) return;
      await _c.setLooping(false);
      await _c.setVolume(1);
      // A borrowed controller sits on the bubble's still, a little way in: start from the top.
      if (_borrowed || _c.value.position >= _c.value.duration - const Duration(milliseconds: 200)) await _c.seekTo(Duration.zero);
      await _c.play();
      _scheduleHide();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
    if (mounted) setState(() {});
  }

  void _retry() {
    setState(() => _failed = false);
    _start();
  }

  void _onTick() {
    if (!mounted) return;
    // At the end: stop with the controls up, ready to play again.
    if (_ended && !_controls) _controls = true;
    setState(() {});
  }

  bool get _ended {
    final v = _c.value;
    return v.isInitialized && !v.isPlaying && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 120);
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.removeListener(_onTick);
    if (_borrowed) {
      // Hand it back the way the bubble had it: still, with sound, on its first frame.
      _c.pause();
      _c.setVolume(1);
      _c.seekTo(const Duration(milliseconds: 100));
    } else {
      _c.dispose();
    }
    _settle.dispose();
    _pull.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 2600), () {
      if (mounted && _c.value.isPlaying && _scrubMs == null) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  Future<void> _playPause() async {
    if (!_c.value.isInitialized) return;
    if (_c.value.isPlaying) {
      await _c.pause();
      _hide?.cancel();
    } else {
      if (_ended) await _c.seekTo(Duration.zero);
      await _c.play();
      _scheduleHide();
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _c.setVolume(_muted ? 0 : 1);
    _scheduleHide();
  }

  // ---- pull to close
  void _dragUpdate(DragUpdateDetails d) {
    if (_closing) return;
    _settle.stop();
    if (_controls) setState(() => _controls = false);
    _pull.value += d.delta.dy;
  }

  void _dragEnd(DragEndDetails d) {
    if (_closing) return;
    final pull = _pull.value;
    final v = d.velocity.pixelsPerSecond.dy;
    // Speed along the pull, so a flick back towards the middle does not close.
    final away = pull == 0 ? v.abs() : v * pull.sign;
    if (pull.abs() > _closeAt || away > _flingAt) {
      _closing = true;
      Navigator.of(context).pop();
    } else {
      _settleTo = Tween(begin: pull, end: 0.0).chain(CurveTween(curve: Curves.easeOutBack)).animate(_settle);
      _settle.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    final ready = v.isInitialized;
    final ratio = ready ? v.aspectRatio : (widget.aspectRatio ?? 9 / 16);
    final reach = MediaQuery.sizeOf(context).height * 0.4;
    double progress(double pull) => (pull.abs() / reach).clamp(0.0, 1.0);

    Widget media = AspectRatio(
      aspectRatio: ratio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.posterUrl != null) CachedNetworkImage(imageUrl: widget.posterUrl!, fit: BoxFit.cover, fadeInDuration: Duration.zero, errorWidget: (_, _, _) => const SizedBox()),
          if (ready) VideoPlayer(_c),
        ],
      ),
    );
    if (widget.heroTag != null) media = Hero(tag: widget.heroTag!, flightShuttleBuilder: videoHeroShuttle, child: media);

    final totalMs = v.duration.inMilliseconds;
    final atMs = _scrubMs ?? v.position.inMilliseconds.clamp(0, totalMs > 0 ? totalMs : 0).toDouble();
    final playing = v.isPlaying;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // The black, fading as the video comes away.
            Positioned.fill(
              child: ValueListenableBuilder<double>(
                valueListenable: _pull,
                builder: (_, pull, _) => ColoredBox(color: Colors.black.withValues(alpha: 1 - progress(pull))),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                onVerticalDragUpdate: _dragUpdate,
                onVerticalDragEnd: _dragEnd,
                child: ValueListenableBuilder<double>(
                  valueListenable: _pull,
                  builder: (_, pull, child) => Transform.translate(
                    offset: Offset(0, pull),
                    child: Transform.scale(scale: 1 - 0.2 * progress(pull), child: child),
                  ),
                  child: Center(child: media),
                ),
              ),
            ),
            if (!ready && !_failed) const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            if (_failed)
              Center(
                child: GestureDetector(
                  onTap: _retry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.arrowsClockwise, color: Colors.white, size: 26),
                        SizedBox(height: 6),
                        Text('Could not play this video. Tap to retry.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            // Controls: fade in and out; while hidden they let taps through to the video.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_controls,
                child: AnimatedOpacity(
                  opacity: _controls ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Stack(
                    children: [
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              _RoundButton(icon: AppIcons.x, tooltip: 'Close', onTap: () => Navigator.of(context).pop()),
                              const Spacer(),
                              _RoundButton(icon: _muted ? AppIcons.speakerSlash : AppIcons.speakerHigh, tooltip: _muted ? 'Unmute' : 'Mute', onTap: _toggleMute),
                            ],
                          ),
                        ),
                      ),
                      if (ready)
                        Center(
                          child: GestureDetector(
                            onTap: _playPause,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                              child: Icon(_ended ? AppIcons.arrowCounterClockwise : (playing ? AppIcons.pause : AppIcons.play), color: Colors.white, size: 32),
                            ),
                          ),
                        ),
                      if (ready)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black54, Colors.transparent])),
                            child: SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                                child: Row(
                                  children: [
                                    _TimeLabel(atMs.round()),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 3,
                                          activeTrackColor: Colors.white,
                                          inactiveTrackColor: Colors.white24,
                                          thumbColor: Colors.white,
                                          overlayColor: Colors.white24,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                                        ),
                                        child: Slider(
                                          value: totalMs <= 0 ? 0.0 : atMs.clamp(0.0, totalMs.toDouble()),
                                          max: totalMs <= 0 ? 1 : totalMs.toDouble(),
                                          onChangeStart: (x) {
                                            _hide?.cancel();
                                            _playAfterScrub = _c.value.isPlaying;
                                            _c.pause();
                                            setState(() => _scrubMs = x);
                                          },
                                          onChanged: (x) {
                                            setState(() => _scrubMs = x);
                                            _c.seekTo(Duration(milliseconds: x.round()));
                                          },
                                          onChangeEnd: (x) async {
                                            await _c.seekTo(Duration(milliseconds: x.round()));
                                            if (!mounted) return;
                                            setState(() => _scrubMs = null);
                                            if (_playAfterScrub) {
                                              await _c.play();
                                              _scheduleHide();
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                    _TimeLabel(totalMs),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: IconButton(tooltip: tooltip, icon: Icon(icon, color: Colors.white, size: 22), onPressed: onTap),
      );
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel(this.ms);
  final int ms;

  @override
  Widget build(BuildContext context) {
    final s = (ms / 1000).round(); // same rounding as the bubble's length chip
    return Text(
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
      maxLines: 1,
      softWrap: false,
      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
    );
  }
}
