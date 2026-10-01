import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/voice_wave.dart';
import 'chat_media.dart' show fmtMs;
import 'chat_wallpaper.dart';

/// A voice note, WhatsApp style: play / pause, a waveform that fills as it
/// plays (tap or drag it to seek), the length or the position, a 1x / 1.5x /
/// 2x speed chip, and on someone else's note their avatar with a mic badge.
/// Only one note plays at a time. The send [time] sits at the bottom right;
/// a reply's [quote] sits on top.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({
    super.key,
    required this.url,
    required this.ms,
    required this.mine,
    this.time,
    this.wave,
    this.seed,
    this.avatarUrl,
    this.avatarSeed,
    this.avatarName,
    this.quote,
  });
  final String url;
  final int ms;
  final bool mine;
  final String? time;
  /// Saved loudness bars (0..100); null for older notes.
  final List<int>? wave;
  /// Seeds the stand-in waveform when [wave] is null (the message id).
  final String? seed;
  final String? avatarUrl;
  final String? avatarSeed;
  final String? avatarName;
  final Widget? quote;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  /// The note that's playing now, so starting another pauses it.
  static _VoiceBubbleState? _current;
  static const _speeds = [1.0, 1.5, 2.0];

  AudioPlayer? _player;
  final _subs = <StreamSubscription<Object?>>[];
  Duration _at = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  bool _failed = false;
  double _speed = 1;
  /// While dragging the waveform: where the finger is (0..1).
  double? _scrub;
  /// Seek picked before the audio was loaded.
  Duration? _pendingSeek;

  late List<int> _bars = _barsFor(widget);

  static List<int> _barsFor(VoiceBubble w) => (w.wave != null && w.wave!.isNotEmpty) ? w.wave! : pseudoWave(w.seed ?? w.url);

  @override
  void didUpdateWidget(VoiceBubble old) {
    super.didUpdateWidget(old);
    if (old.wave != widget.wave || old.seed != widget.seed) _bars = _barsFor(widget);
  }

  @override
  void dispose() {
    if (_current == this) _current = null;
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  int get _totalMs {
    final d = _player?.duration?.inMilliseconds ?? 0;
    return widget.ms > 0 ? widget.ms : d;
  }

  Future<AudioPlayer?> _load() async {
    if (_player != null) return _player;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final p = AudioPlayer();
    try {
      await p.setUrl(widget.url);
    } catch (_) {
      await p.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return null;
    }
    if (!mounted) {
      await p.dispose();
      return null;
    }
    _player = p;
    _subs.add(p.positionStream.listen((d) {
      if (mounted && _scrub == null) setState(() => _at = d);
    }));
    _subs.add(p.playerStateStream.listen((s) {
      if (!mounted) return;
      if (s.processingState == ProcessingState.completed) {
        p.pause();
        p.seek(Duration.zero);
        setState(() {
          _playing = false;
          _at = Duration.zero;
        });
      } else if (s.playing != _playing) {
        setState(() => _playing = s.playing);
      }
    }));
    final seek = _pendingSeek;
    _pendingSeek = null;
    if (seek != null) await p.seek(seek);
    setState(() => _loading = false);
    return p;
  }

  Future<void> _toggle() async {
    final p = await _load();
    if (p == null || !mounted) return;
    if (p.playing) {
      await p.pause();
      return;
    }
    final other = _current;
    if (other != null && other != this) other._player?.pause();
    _current = this;
    await p.setSpeed(_speed);
    unawaited(p.play()); // completes when playback stops, not when it starts
  }

  Future<void> _seekTo(double frac) async {
    final total = _totalMs;
    if (total <= 0) return;
    final to = Duration(milliseconds: (total * frac.clamp(0.0, 1.0)).round());
    setState(() => _at = to);
    final p = _player;
    if (p == null) {
      _pendingSeek = to;
    } else {
      await p.seek(to);
    }
  }

  void _cycleSpeed() {
    final next = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
    setState(() => _speed = next);
    _player?.setSpeed(next);
  }

  String _speedLabel(double s) => '${s == s.roundToDouble() ? s.toInt() : s}×';

  @override
  Widget build(BuildContext context) {
    final total = _totalMs;
    final frac = _scrub ?? (total <= 0 ? 0.0 : (_at.inMilliseconds / total).clamp(0.0, 1.0));
    final started = _player != null && (_playing || _at > Duration.zero);
    final shown = _scrub != null ? Duration(milliseconds: (total * _scrub!).round()) : (started ? _at : Duration(milliseconds: total));
    final width = math.min(280.0, MediaQuery.sizeOf(context).width * 0.72);
    final fg = AppColors.textPrimary;

    final playButton = SizedBox(
      width: 38,
      height: 38,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _loading ? null : _toggle,
          child: Center(
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_failed ? AppIcons.arrowsClockwise : (_playing ? AppIcons.pauseFill : AppIcons.playFill), size: 26, color: fg.withValues(alpha: 0.8)),
          ),
        ),
      ),
    );

    final speedChip = GestureDetector(
      onTap: _cycleSpeed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: fg.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text(_speedLabel(_speed), maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
      ),
    );

    // Someone else's note: their face with a mic badge, swapped for the speed
    // chip once it's playing (as WhatsApp does). Mine: the chip on the right.
    Widget? lead;
    if (!widget.mine) {
      lead = started
          ? SizedBox(width: 44, height: 44, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: speedChip)))
          : SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(url: widget.avatarUrl, name: widget.avatarName, seed: widget.avatarSeed, size: 44),
                  Positioned(
                    right: -3,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                      child: const Icon(AppIcons.microphoneFill, size: 14, color: AppColors.brand),
                    ),
                  ),
                ],
              ),
            );
    }

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 5),
      decoration: BoxDecoration(
        color: ChatWallpaperStyle.of(context).bubbleFill(widget.mine),
        border: ChatWallpaperStyle.of(context).bubbleBorder(widget.mine),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.mine ? 18 : 4),
          bottomRight: Radius.circular(widget.mine ? 4 : 18),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.quote != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: widget.quote),
          // Play button, waveform and dot on one centred line (as WhatsApp);
          // the length and the send time on a line under the waveform.
          Row(
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 4)],
              playButton,
              const SizedBox(width: 4),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    // The bars sit inset by the dot's radius, so the dot
                    // starts on the first bar, not over it.
                    final track = box.maxWidth - 2 * VoiceWavePainter.thumbRadius;
                    double at(Offset p) => ((p.dx - VoiceWavePainter.thumbRadius) / track).clamp(0.0, 1.0);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _seekTo(at(d.localPosition)),
                      onHorizontalDragStart: (d) => setState(() => _scrub = at(d.localPosition)),
                      onHorizontalDragUpdate: (d) => setState(() => _scrub = at(d.localPosition)),
                      onHorizontalDragEnd: (_) {
                        final s = _scrub;
                        setState(() => _scrub = null);
                        if (s != null) _seekTo(s);
                      },
                      onHorizontalDragCancel: () => setState(() => _scrub = null),
                      child: SizedBox(
                        height: 32,
                        child: CustomPaint(
                          painter: VoiceWavePainter(
                            bars: _bars,
                            progress: frac,
                            played: fg.withValues(alpha: 0.8),
                            unplayed: fg.withValues(alpha: 0.25),
                            thumb: AppColors.brand,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.mine && started) ...[const SizedBox(width: 8), speedChip],
            ],
          ),
          Padding(
            // Under the waveform: past the lead, the play button and the dot's inset.
            padding: EdgeInsets.only(left: (lead != null ? 48 : 0) + 42 + VoiceWavePainter.thumbRadius, top: 1),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    fmtMs(shown.inMilliseconds),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                if (widget.time != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.time!, textAlign: TextAlign.end, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Waveform bars (0..100) with the first [progress] of them in [played].
class VoiceWavePainter extends CustomPainter {
  VoiceWavePainter({required this.bars, required this.progress, required this.played, required this.unplayed, this.thumb});
  final List<int> bars;
  final double progress;
  final Color played;
  final Color unplayed;
  final Color? thumb;

  /// The playhead dot; the bars are inset by this much at both ends so the
  /// dot sits exactly on the first bar at 0:00 and the last at the end.
  static const thumbRadius = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0) return;
    const r = thumbRadius;
    final track = size.width - 2 * r;
    final n = bars.length;
    final slot = track / n;
    final w = math.max(1.5, slot * 0.6);
    final mid = size.height / 2;
    final cut = r + progress * track;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w;
    for (var i = 0; i < n; i++) {
      final x = r + i * slot + slot / 2;
      final h = math.max(w, bars[i].clamp(0, 100) / 100 * (size.height - 4));
      paint.color = x <= cut ? played : unplayed;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
    if (thumb != null) {
      canvas.drawCircle(Offset(cut, mid), r, Paint()..color = thumb!);
    }
  }

  @override
  bool shouldRepaint(VoiceWavePainter old) =>
      old.progress != progress || old.bars != bars || old.played != played || old.unplayed != unplayed || old.thumb != thumb;
}
