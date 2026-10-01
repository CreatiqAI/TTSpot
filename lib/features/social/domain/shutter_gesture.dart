// The chat camera's shutter, WhatsApp style, as a pure state machine so the
// tap-versus-hold decision can be unit tested without a camera.
//
// * Tap: a photo.
// * Press and hold for [ShutterGesture.holdThreshold]: a video starts, and it
//   stops when the finger lifts.
// * Slide up while holding: locks the recording hands-free (a stop button
//   ends it).
//
// The screen feeds in pointer events and timer ticks with a monotonic clock
// (`now`), and acts on the returned [ShutterAction].

/// What the camera should do after an event.
enum ShutterAction { none, takePhoto, startVideo, stopVideo, lock }

enum ShutterPhase {
  /// Nothing happening.
  idle,

  /// Finger down, not yet held long enough: lifting now takes a photo.
  pressed,

  /// Held past the threshold: recording, stops on release.
  recording,

  /// Slid up while recording: hands-free until the stop button.
  locked,

  /// Taking a photo or finishing a video; input is ignored until [ShutterGesture.done].
  busy,
}

class ShutterGesture {
  ShutterGesture({
    this.holdThreshold = const Duration(milliseconds: 500),
    this.minClip = const Duration(seconds: 1),
    required this.maxClip,
    this.lockDistance = 80,
  });

  /// A press this long becomes a video. Anything shorter is a photo.
  final Duration holdThreshold;

  /// Shortest video kept. Letting go sooner keeps recording until it gets
  /// there, so a quick hold never makes an empty or broken file.
  final Duration minClip;

  /// Longest video; it stops itself here.
  final Duration maxClip;

  /// Slide up this far (logical px) while recording to lock.
  final double lockDistance;

  ShutterPhase _phase = ShutterPhase.idle;
  Duration _downAt = Duration.zero;
  Duration? _recAt;
  bool _stopQueued = false;
  double _dragY = 0;

  ShutterPhase get phase => _phase;

  /// Recording, held or locked (also while the recorder is still starting).
  bool get isVideo => _phase == ShutterPhase.recording || _phase == ShutterPhase.locked;

  /// The recorder is running (its start has been confirmed).
  bool get isRolling => isVideo && _recAt != null;

  /// The finger is up but the clip is still short of [minClip]; it stops by itself.
  bool get stopQueued => _stopQueued;

  /// Upward slide while recording, 0 or negative (px).
  double get dragY => _dragY;

  /// 0..1, how close a held recording is to locking.
  double get lockProgress => (-_dragY / lockDistance).clamp(0.0, 1.0);

  /// Length of the clip so far.
  Duration recorded(Duration now) {
    final at = _recAt;
    if (at == null || !isVideo) return Duration.zero;
    final d = now - at;
    if (d.isNegative) return Duration.zero;
    return d > maxClip ? maxClip : d;
  }

  /// Finger down on the shutter.
  ShutterAction down(Duration now) {
    if (_phase != ShutterPhase.idle) return ShutterAction.none;
    _phase = ShutterPhase.pressed;
    _downAt = now;
    _recAt = null;
    _stopQueued = false;
    _dragY = 0;
    return ShutterAction.none;
  }

  /// The hold timer fired: still down after [holdThreshold] starts a video.
  ShutterAction holdCheck(Duration now) {
    if (_phase != ShutterPhase.pressed || now - _downAt < holdThreshold) return ShutterAction.none;
    _phase = ShutterPhase.recording;
    return ShutterAction.startVideo;
  }

  /// The recorder confirmed it is running.
  void started(Duration now) {
    if (isVideo) _recAt = now;
  }

  /// Finger moved; [dy] is the vertical offset from where it went down
  /// (negative = up).
  ShutterAction move(double dy) {
    if (_phase != ShutterPhase.recording || _stopQueued) return ShutterAction.none;
    _dragY = dy < 0 ? dy : 0;
    if (_dragY <= -lockDistance) {
      _phase = ShutterPhase.locked;
      _dragY = 0;
      return ShutterAction.lock;
    }
    return ShutterAction.none;
  }

  /// Finger lifted.
  ShutterAction up(Duration now) {
    switch (_phase) {
      case ShutterPhase.pressed:
        // Shorter than the hold threshold (or the video never started): a photo.
        _phase = ShutterPhase.busy;
        return ShutterAction.takePhoto;
      case ShutterPhase.recording:
        _dragY = 0;
        return _stop(now);
      case ShutterPhase.idle:
      case ShutterPhase.locked:
      case ShutterPhase.busy:
        return ShutterAction.none;
    }
  }

  /// The system took the touch (a call, a dialog): a press does nothing, a
  /// held recording stops and is kept.
  ShutterAction cancel(Duration now) {
    switch (_phase) {
      case ShutterPhase.pressed:
        _phase = ShutterPhase.idle;
        return ShutterAction.none;
      case ShutterPhase.recording:
        _dragY = 0;
        return _stop(now);
      case ShutterPhase.idle:
      case ShutterPhase.locked:
      case ShutterPhase.busy:
        return ShutterAction.none;
    }
  }

  /// The stop button of a locked recording.
  ShutterAction stopTapped(Duration now) => _phase == ShutterPhase.locked ? _stop(now) : ShutterAction.none;

  /// Call regularly while recording: stops at [maxClip], and finishes a
  /// queued stop once the clip reaches [minClip].
  ShutterAction tick(Duration now) {
    if (!isVideo) return ShutterAction.none;
    final at = _recAt;
    if (at == null) return ShutterAction.none;
    final len = now - at;
    if (len >= maxClip || (_stopQueued && len >= minClip)) {
      _phase = ShutterPhase.busy;
      return ShutterAction.stopVideo;
    }
    return ShutterAction.none;
  }

  ShutterAction _stop(Duration now) {
    final at = _recAt;
    if (at == null || now - at < minClip) {
      _stopQueued = true;
      return ShutterAction.none;
    }
    _phase = ShutterPhase.busy;
    return ShutterAction.stopVideo;
  }

  /// The photo or video is finished (or failed): ready for the next one.
  void done() {
    _phase = ShutterPhase.idle;
    _recAt = null;
    _stopQueued = false;
    _dragY = 0;
  }
}
