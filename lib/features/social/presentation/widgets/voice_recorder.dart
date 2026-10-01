import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/voice_wave.dart';

/// Longest voice note; it sends itself when it gets there.
const kVoiceNoteMax = Duration(minutes: 2);

/// Anything shorter is dropped (a stray tap on the mic).
const kVoiceNoteMin = Duration(milliseconds: 700);

/// A finished recording, ready to upload.
class VoiceNote {
  const VoiceNote({required this.path, required this.ms, required this.wave});
  final String path;
  final int ms;
  /// ~50 bars of 0..100 for messages.audio_wave.
  final List<int> wave;
}

enum VoiceRecMode {
  idle,
  /// Finger is down, the mic is warming up.
  starting,
  /// Recording while the finger stays on the mic.
  holding,
  /// Recording hands-free: tapped the mic, or slid up to lock.
  locked,
}

/// Voice notes like WhatsApp.
///
/// * Tap the mic: records straight away, locked (trash / pause / send bar).
/// * Hold the mic: records while held, release sends. Slide left to cancel,
///   slide up to lock.
///
/// The gesture state lives here rather than in the mic widget, because the
/// mic is swapped out for the locked bar while the finger may still be down.
class VoiceRecorder extends ChangeNotifier {
  VoiceRecorder({required this.onReady, required this.onHint, this.canStart});

  /// Called with a recording to send (at least [kVoiceNoteMin] long).
  final Future<void> Function(VoiceNote note) onReady;

  /// A short message for a toast: too short, no mic permission.
  final void Function(String message) onHint;

  /// Return false to ignore the mic (e.g. while something is uploading).
  final bool Function()? canStart;

  /// Slide this far left while holding to cancel.
  static const cancelDistance = 100.0;

  /// Slide this far up while holding to lock.
  static const lockDistance = 80.0;

  /// A press shorter than this is a tap: it locks instead of sending.
  static const tapTime = Duration(milliseconds: 300);

  AudioRecorder? _rec;
  VoiceRecMode _mode = VoiceRecMode.idle;
  bool _paused = false;
  final _watch = Stopwatch();
  final List<double> _levels = [];
  double _dragX = 0;
  double _dragY = 0;
  Offset _origin = Offset.zero;
  bool _pressed = false;
  DateTime _pressAt = DateTime.now();
  Timer? _tick;
  StreamSubscription<Amplitude>? _amp;
  String? _path;
  bool _disposed = false;

  VoiceRecMode get mode => _mode;
  bool get active => _mode != VoiceRecMode.idle;
  bool get locked => _mode == VoiceRecMode.locked;
  /// Finger on the mic (or about to be recording with it).
  bool get holding => _mode == VoiceRecMode.holding || _mode == VoiceRecMode.starting;
  bool get paused => _paused;
  Duration get elapsed => _watch.elapsed;
  /// Mic loudness so far, 0..1, one every ~100 ms.
  List<double> get levels => _levels;
  double get dragX => _dragX;
  double get dragY => _dragY;
  /// 0..1, how close a held recording is to being cancelled / locked.
  double get cancelProgress => (-_dragX / cancelDistance).clamp(0.0, 1.0);
  double get lockProgress => (-_dragY / lockDistance).clamp(0.0, 1.0);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- the mic button's pointer events --------------------------------------

  Future<void> pressDown(Offset globalPosition) async {
    if (_mode != VoiceRecMode.idle || canStart?.call() == false) return;
    _pressed = true;
    _pressAt = DateTime.now();
    _origin = globalPosition;
    _dragX = _dragY = 0;
    _watch.reset();
    _levels.clear();
    _mode = VoiceRecMode.starting;
    _notify();
    final ok = await _begin();
    if (_disposed) return;
    if (!ok) {
      _mode = VoiceRecMode.idle;
      _notify();
      return;
    }
    if (_mode != VoiceRecMode.starting) return;
    HapticFeedback.mediumImpact();
    if (_dragX <= -cancelDistance) {
      // Slid away while the mic was still starting.
      await discard();
      return;
    }
    // Let go already (a tap, or the permission prompt took the finger): lock.
    _mode = _pressed ? VoiceRecMode.holding : VoiceRecMode.locked;
    _dragX = _dragY = 0;
    _notify();
  }

  void pressMove(Offset globalPosition) {
    if (!holding) return;
    final d = globalPosition - _origin;
    // One direction at a time, like WhatsApp: left cancels, up locks.
    if (-d.dx >= -d.dy) {
      _dragX = math.min(0, d.dx);
      _dragY = 0;
    } else {
      _dragY = math.min(0, d.dy);
      _dragX = 0;
    }
    if (_mode == VoiceRecMode.holding) {
      if (_dragX <= -cancelDistance) {
        HapticFeedback.heavyImpact();
        discard();
        return;
      }
      if (_dragY <= -lockDistance) {
        HapticFeedback.mediumImpact();
        _mode = VoiceRecMode.locked;
        _dragX = _dragY = 0;
      }
    }
    _notify();
  }

  void pressUp() {
    _pressed = false;
    if (_mode != VoiceRecMode.holding) return;
    // Greyed out ("Release to cancel"): letting go there cancels too.
    if (cancelProgress > 0.7) {
      HapticFeedback.heavyImpact();
      discard();
      return;
    }
    final tap = DateTime.now().difference(_pressAt) < tapTime && _dragX > -12 && _dragY > -12;
    if (tap) {
      _mode = VoiceRecMode.locked;
      _dragX = _dragY = 0;
      _notify();
      return;
    }
    send();
  }

  /// The system took the pointer (a call, a permission prompt): drop a held
  /// recording, keep a locked one.
  void pressCancel() {
    _pressed = false;
    if (_mode == VoiceRecMode.holding) discard();
  }

  // ---- locked bar ------------------------------------------------------------

  Future<void> togglePause() async {
    final rec = _rec;
    if (_mode != VoiceRecMode.locked || rec == null) return;
    try {
      if (_paused) {
        await rec.resume();
        _watch.start();
        _paused = false;
      } else {
        await rec.pause();
        _watch.stop();
        _paused = true;
      }
    } catch (_) {}
    _notify();
  }

  /// Stops and hands the note to [onReady] (or drops it if it's too short).
  Future<void> send() async {
    if (!active) return;
    final wasHolding = _mode == VoiceRecMode.holding;
    final note = await _stop();
    if (note == null) return;
    if (note.ms < kVoiceNoteMin.inMilliseconds) {
      _delete(note.path);
      onHint(wasHolding ? 'Hold to record, release to send' : 'Too short to send');
      return;
    }
    await onReady(note);
  }

  /// Stops and throws the recording away.
  Future<void> discard() async {
    if (!active) return;
    final note = await _stop();
    if (note != null) _delete(note.path);
  }

  // ---- internals -----------------------------------------------------------

  Future<bool> _begin() async {
    final rec = _rec ??= AudioRecorder();
    try {
      if (!await rec.hasPermission(request: false)) {
        // First time: ask, but don't start recording off the tap that raised
        // the prompt. Once allowed, the next tap records.
        if (await rec.hasPermission()) {
          onHint('Microphone on. Tap the mic to record.');
        } else {
          onHint('Allow the microphone to send voice notes.');
        }
        return false;
      }
      if (_disposed) return false;
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100), path: path);
      _path = path;
    } catch (_) {
      onHint('Couldn\'t start the microphone. Try again.');
      return false;
    }
    _levels.clear();
    _paused = false;
    _watch
      ..reset()
      ..start();
    _amp = rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
      if (_paused || !active) return;
      _levels.add(dbfsToLevel(a.current));
      _notify();
    }, onError: (_) {});
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_watch.elapsed >= kVoiceNoteMax) {
        send();
        return;
      }
      _notify();
    });
    return true;
  }

  Future<VoiceNote?> _stop() async {
    _mode = VoiceRecMode.idle;
    _paused = false;
    _dragX = _dragY = 0;
    _tick?.cancel();
    _amp?.cancel();
    _amp = null;
    _watch.stop();
    final ms = _watch.elapsedMilliseconds;
    // Dead silence means the mic gave no levels: save no wave, the bubble draws a stand-in.
    final bars = downsampleWave(_levels);
    final wave = bars.any((v) => v > 0) ? bars : const <int>[];
    _notify();
    String? path;
    try {
      path = await _rec?.stop();
    } catch (_) {}
    path ??= _path;
    _path = null;
    if (path == null) return null;
    return VoiceNote(path: path, ms: ms, wave: wave);
  }

  static void _delete(String path) => File(path).delete().catchError((_) => File(path));

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    _amp?.cancel();
    final path = _path;
    _rec?.dispose().whenComplete(() {
      if (path != null) _delete(path);
    });
    super.dispose();
  }
}

String _clock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// The mic at the right of the composer. Tap to start a locked recording,
/// hold to record (slide left to cancel, up to lock, release to send).
class VoiceMicButton extends StatelessWidget {
  const VoiceMicButton({super.key, required this.recorder});
  final VoiceRecorder recorder;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Voice note. Tap to record, or hold and release to send',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => recorder.pressDown(e.position),
        onPointerMove: (e) => recorder.pressMove(e.position),
        onPointerUp: (_) => recorder.pressUp(),
        onPointerCancel: (_) => recorder.pressCancel(),
        child: ListenableBuilder(
          listenable: recorder,
          builder: (context, _) {
            final hold = recorder.holding;
            final cancelling = recorder.cancelProgress > 0.7;
            final bg = !hold ? AppColors.surfaceGray : (cancelling ? AppColors.textMuted : AppColors.brand);
            return SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (hold)
                    Positioned(
                      bottom: 62 - recorder.dragY * 0.5,
                      child: _LockHint(progress: recorder.lockProgress, hidden: recorder.dragX < -8),
                    ),
                  Transform.translate(
                    offset: Offset(recorder.dragX * 0.6, recorder.dragY * 0.6),
                    child: AnimatedScale(
                      scale: hold ? 1.5 : 1,
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                        child: Icon(
                          cancelling ? AppIcons.trash : (hold ? AppIcons.microphoneFill : AppIcons.microphone),
                          size: hold ? 16 : 20,
                          color: hold ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The pill above a held mic: a lock and an up arrow, "slide up to lock".
class _LockHint extends StatelessWidget {
  const _LockHint({required this.progress, required this.hidden});
  final double progress;
  final bool hidden;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: hidden ? 0 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.border),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.lock, size: 18, color: Color.lerp(AppColors.textSecondary, AppColors.brand, progress)),
              SizedBox(height: 6 + 6 * (1 - progress)),
              Icon(AppIcons.caretUp, size: 14, color: AppColors.textMuted),
            ],
          ),
        ),
      );
}

/// What replaces [+] [Message…] [camera] while the mic is held: a blinking
/// red dot, the timer, and "‹ Slide to cancel" drifting with the finger,
/// greying out as it nears the cancel point.
class VoiceHoldStrip extends StatelessWidget {
  const VoiceHoldStrip({super.key, required this.recorder});
  final VoiceRecorder recorder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: recorder,
        builder: (context, _) {
          final c = recorder.cancelProgress;
          final near = c > 0.7;
          final hint = Color.lerp(AppColors.textSecondary, AppColors.textMuted, c)!;
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 42),
            child: Row(
              children: [
                const SizedBox(width: 8),
                _BlinkDot(color: near ? AppColors.textMuted : AppColors.brand, blinking: !near),
                const SizedBox(width: 8),
                Text(
                  _clock(recorder.elapsed),
                  maxLines: 1,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: near ? AppColors.textMuted : AppColors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Transform.translate(
                    offset: Offset(recorder.dragX * 0.5, 0),
                    child: Opacity(
                      opacity: 1 - c * 0.55,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(AppIcons.caretLeft, size: 14, color: hint),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              near ? 'Release to cancel' : 'Slide to cancel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: hint),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Room for the enlarged mic to sit over.
                const SizedBox(width: 16),
              ],
            ),
          );
        },
      );
}

/// The locked recording bar: timer and a live waveform on top; trash, pause /
/// resume and send underneath. Paused, the waveform shows the whole take.
class VoiceLockedBar extends StatelessWidget {
  const VoiceLockedBar({super.key, required this.recorder});
  final VoiceRecorder recorder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: recorder,
        builder: (context, _) {
          final paused = recorder.paused;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const SizedBox(width: 6),
                  _BlinkDot(color: AppColors.brand, blinking: !paused),
                  const SizedBox(width: 8),
                  Text(
                    _clock(recorder.elapsed),
                    maxLines: 1,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: CustomPaint(painter: LiveWavePainter(levels: recorder.levels, whole: paused, color: AppColors.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      recorder.discard();
                    },
                    icon: Icon(AppIcons.trash, size: 24, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  Material(
                    color: Colors.transparent,
                    shape: CircleBorder(side: BorderSide(color: AppColors.brand, width: 2)),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: recorder.togglePause,
                      child: Tooltip(
                        message: paused ? 'Resume' : 'Pause',
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(paused ? AppIcons.microphoneFill : AppIcons.pauseFill, size: 20, color: AppColors.brand),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Material(
                    color: AppColors.brand,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: recorder.send,
                      child: const Tooltip(
                        message: 'Send',
                        child: SizedBox(width: 48, height: 48, child: Icon(AppIcons.paperPlaneRight, size: 22, color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
}

/// Recording waveform. Live: the newest sample at the right edge, older ones
/// scrolling off to the left. [whole]: the full take squeezed to fit.
class LiveWavePainter extends CustomPainter {
  LiveWavePainter({required List<double> levels, required this.whole, required this.color}) : levels = List.of(levels);
  final List<double> levels;
  final bool whole;
  final Color color;

  static const _bar = 3.0;
  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = (size.width / (_bar + _gap)).floor();
    if (n <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _bar;
    final mid = size.height / 2;
    final List<double> bars;
    if (whole && levels.isNotEmpty) {
      bars = [for (final v in downsampleWave(levels, bars: math.min(n, math.max(levels.length, 1)))) v / 100];
    } else {
      bars = levels.length > n ? levels.sublist(levels.length - n) : levels;
    }
    // Live: right-aligned so it scrolls; whole: left-aligned like a bubble.
    final start = whole ? 0.0 : size.width - bars.length * (_bar + _gap);
    for (var i = 0; i < bars.length; i++) {
      final h = math.max(2.0, bars[i].clamp(0.0, 1.0) * (size.height - _bar));
      final x = start + i * (_bar + _gap) + _bar / 2;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
    // Dots where nothing has been said yet, so the bar never looks empty.
    if (!whole) {
      final dot = Paint()..color = color.withValues(alpha: 0.35);
      for (var x = _bar / 2; x < start; x += _bar + _gap) {
        canvas.drawCircle(Offset(x, mid), 1.1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(LiveWavePainter old) => old.levels.length != levels.length || old.whole != whole || old.color != color;
}

class _BlinkDot extends StatefulWidget {
  const _BlinkDot({required this.color, required this.blinking});
  final Color color;
  final bool blinking;

  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    if (widget.blinking) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_BlinkDot old) {
    super.didUpdateWidget(old);
    if (widget.blinking && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.blinking && _c.isAnimating) {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: widget.blinking ? Tween(begin: 0.25, end: 1.0).animate(_c) : const AlwaysStoppedAnimation(1),
        child: Container(width: 10, height: 10, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
      );
}
