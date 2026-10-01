import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:image_picker/image_picker.dart' show ImagePicker;

import '../../../core/config/media.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/shutter_gesture.dart';
import 'widgets/media_send_preview.dart';

/// Opens the in-app chat camera, WhatsApp style: tap the shutter for a photo,
/// hold it for a video, or pick from the gallery. Whatever comes out goes
/// through the send preview (captions, video still) first. Returns what to
/// send, or null when closed.
Future<List<MediaSendItem>?> openChatCamera(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<List<MediaSendItem>>(
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => const ChatCameraScreen(),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ),
  );
}

enum _CamState { starting, ready, denied, unavailable }

enum _Flash { off, auto, on }

class ChatCameraScreen extends StatefulWidget {
  const ChatCameraScreen({super.key});

  @override
  State<ChatCameraScreen> createState() => _ChatCameraScreenState();
}

class _ChatCameraScreenState extends State<ChatCameraScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // 1080p keeps photos about as big as the gallery picks (1600 px); ~3 Mbit/s
  // keeps a full one-minute video near 23 MB, well under the chat cap.
  static const _preset = ResolutionPreset.veryHigh;
  static const _videoBitrate = 3000000;
  static const _audioBitrate = 96000;

  final _clock = Stopwatch()..start();
  Duration get _now => _clock.elapsed;
  late final _shutter = ShutterGesture(maxClip: kChatVideoMaxDuration);

  /// 0..1 over the longest video: drives the progress ring and the timer.
  late final _rec = AnimationController(vsync: this, duration: kChatVideoMaxDuration);

  List<CameraDescription>? _cams;
  CameraLensDirection _lens = CameraLensDirection.back;
  CameraController? _ctrl;
  _CamState _state = _CamState.starting;
  bool _micOff = false;
  bool _retryMic = false;
  _Flash _flash = _Flash.off;
  bool _torch = false;
  double _minZoom = 1, _maxZoom = 1, _zoom = 1, _zoomFrom = 1;
  bool _zooming = false;
  double _flipTurns = 0;
  bool _blink = false;

  // The finger on the shutter.
  int? _pointer;
  double _downY = 0;
  bool _stopOnUp = false;
  Timer? _holdTimer;
  Timer? _ticker;

  /// The gallery or the send preview is up: the camera is closed meanwhile.
  bool _covered = false;

  /// The app is in the background: the camera is closed meanwhile.
  bool _suspended = false;
  bool _leaving = false;

  /// A video cut short by going to the background, reviewed on return.
  XFile? _pendingClip;

  /// Files this screen made; whatever isn't sent is deleted.
  final _captured = <String>{};

  String? _toast;
  Timer? _toastTimer;

  // Opening and closing the camera run one at a time, in order.
  Future<void> _lane = Future.value();
  Future<void> _serial(Future<void> Function() f) {
    final next = _lane.then((_) => f()).catchError((Object _) {});
    _lane = next;
    return next;
  }

  void _set([VoidCallback? fn]) {
    fn?.call();
    if (mounted) setState(() {});
  }

  bool get _isBack => _lens == CameraLensDirection.back;
  bool get _live => _state == _CamState.ready && (_ctrl?.value.isInitialized ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _serial(_open);
  }

  @override
  void dispose() {
    _leaving = true;
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(const []);
    _holdTimer?.cancel();
    _ticker?.cancel();
    _toastTimer?.cancel();
    _rec.dispose();
    final c = _ctrl;
    _ctrl = null;
    final leftovers = {..._captured, ?_pendingClip?.path};
    () async {
      if (c != null) {
        if (c.value.isRecordingVideo) {
          try {
            leftovers.add((await c.stopVideoRecording()).path);
          } catch (_) {}
        }
        try {
          await c.dispose();
        } catch (_) {}
      }
      leftovers.forEach(_delete);
    }();
    super.dispose();
  }

  // ---- camera ---------------------------------------------------------------

  /// Opens the camera facing [_lens]. Runs on [_lane].
  Future<void> _open() async {
    if (!mounted || _suspended || _covered || _leaving || _ctrl != null) return;
    _set(() => _state = _CamState.starting);
    try {
      _cams ??= await availableCameras();
    } catch (_) {
      _cams = null;
      _set(() => _state = _CamState.unavailable);
      return;
    }
    final cams = _cams!;
    if (cams.isEmpty) {
      _set(() => _state = _CamState.unavailable);
      return;
    }
    final desc = cams.firstWhere((c) => c.lensDirection == _lens, orElse: () => cams.first);
    _lens = desc.lensDirection;
    // The mic is asked for with the camera; refused, the camera still works and videos are silent.
    final audio = !_micOff || _retryMic;
    _retryMic = false;
    final c = await _create(desc, audio: audio);
    if (c == null) return;
    if (!mounted || _suspended || _covered || _leaving) {
      await c.dispose().catchError((Object _) {});
      return;
    }
    // The screen is portrait only, so the preview and the files are too.
    try {
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}
    try {
      await c.setJpegImageQuality(85);
    } catch (_) {}
    try {
      _minZoom = await c.getMinZoomLevel();
      _maxZoom = await c.getMaxZoomLevel();
    } catch (_) {
      _minZoom = _maxZoom = 1;
    }
    _zoom = _minZoom;
    if (c.enableAudio && Platform.isIOS) {
      // Sets the audio up now, so a hold starts recording without a lag.
      try {
        await c.prepareForVideoRecording();
      } catch (_) {}
    }
    await _applyFlash(c);
    _set(() {
      _ctrl = c;
      _state = _CamState.ready;
    });
  }

  Future<CameraController?> _create(CameraDescription d, {required bool audio}) async {
    final c = CameraController(d, _preset, enableAudio: audio, videoBitrate: _videoBitrate, audioBitrate: audio ? _audioBitrate : null);
    try {
      await c.initialize();
      _micOff = !audio;
      return c;
    } on CameraException catch (e) {
      await c.dispose().catchError((Object _) {});
      if (audio && e.code.startsWith('AudioAccess')) return _create(d, audio: false);
      _set(() => _state = e.code.startsWith('CameraAccess') ? _CamState.denied : _CamState.unavailable);
      return null;
    } catch (_) {
      await c.dispose().catchError((Object _) {});
      _set(() => _state = _CamState.unavailable);
      return null;
    }
  }

  /// Frees the camera. A video being recorded is stopped and kept for review
  /// when [keepClip], else thrown away. Runs on [_lane].
  Future<void> _close({bool keepClip = false}) async {
    final c = _ctrl;
    if (c == null) return;
    _set(() => _ctrl = null);
    if (c.value.isRecordingVideo) {
      try {
        final f = await c.stopVideoRecording();
        if (keepClip) {
          _pendingClip = f;
        } else {
          _delete(f.path);
        }
      } catch (_) {}
    }
    if (_shutter.isVideo) _endVideo();
    try {
      await c.dispose();
    } catch (_) {}
  }

  Future<void> _applyFlash([CameraController? cam]) async {
    final c = cam ?? _ctrl;
    if (c == null || !_isBack) return;
    try {
      await c.setFlashMode(switch (_flash) {
        _Flash.off => FlashMode.off,
        _Flash.auto => FlashMode.auto,
        _Flash.on => FlashMode.always,
      });
    } catch (_) {}
  }

  // ---- app lifecycle --------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // The permission prompt makes the app inactive too: only act on a running camera.
        if (_ctrl?.value.isInitialized ?? false) _suspend();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _suspend();
      case AppLifecycleState.resumed:
        _resume();
      case AppLifecycleState.detached:
        break;
    }
  }

  void _suspend() {
    if (_suspended) return;
    _suspended = true;
    _holdTimer?.cancel();
    _pointer = null;
    _stopOnUp = false;
    if (_shutter.phase == ShutterPhase.pressed) _shutter.done();
    _serial(() => _close(keepClip: true));
  }

  void _resume() {
    if (!_suspended) return;
    _suspended = false;
    _serial(() async {
      final clip = _pendingClip;
      _pendingClip = null;
      if (clip != null && mounted) {
        _captured.add(clip.path);
        if (await _fits(clip)) {
          unawaited(_review([clip]));
          return;
        }
        _delete(clip.path);
      }
      await _open();
    });
  }

  // ---- shutter --------------------------------------------------------------

  void _onDown(PointerDownEvent e) {
    if (_pointer != null || !_live) return;
    _pointer = e.pointer;
    if (_shutter.phase == ShutterPhase.locked) {
      // Hands-free recording: the shutter is the stop button now.
      _stopOnUp = true;
      return;
    }
    _downY = e.position.dy;
    _shutter.down(_now);
    if (_shutter.phase != ShutterPhase.pressed) return;
    _holdTimer?.cancel();
    _holdTimer = Timer(_shutter.holdThreshold, _onHold);
    _set();
  }

  void _onHold() {
    final a = _shutter.holdCheck(_now);
    if (a == ShutterAction.none && _shutter.phase == ShutterPhase.pressed) {
      // The timer came in a hair early: look again next frame.
      _holdTimer = Timer(const Duration(milliseconds: 16), _onHold);
      return;
    }
    _act(a);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer || _shutter.phase != ShutterPhase.recording) return;
    _act(_shutter.move(e.position.dy - _downY));
    _set();
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _holdTimer?.cancel();
    if (_stopOnUp) {
      _stopOnUp = false;
      _act(_shutter.stopTapped(_now));
    } else {
      _act(_shutter.up(_now));
    }
    _set();
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _stopOnUp = false;
    _holdTimer?.cancel();
    _act(_shutter.cancel(_now));
    _set();
  }

  /// A screen-reader tap: a photo.
  void _semanticTap() {
    if (!_live || _shutter.phase != ShutterPhase.idle) return;
    _shutter.down(_now);
    _act(_shutter.up(_now));
  }

  void _act(ShutterAction a) {
    switch (a) {
      case ShutterAction.takePhoto:
        _takePhoto();
      case ShutterAction.startVideo:
        _startVideo();
      case ShutterAction.stopVideo:
        _stopVideo();
      case ShutterAction.lock:
        HapticFeedback.mediumImpact();
        _set();
      case ShutterAction.none:
        break;
    }
  }

  Future<void> _takePhoto() async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) {
      _set(_shutter.done);
      return;
    }
    HapticFeedback.mediumImpact();
    _set(() => _blink = true);
    Timer(const Duration(milliseconds: 110), () => _set(() => _blink = false));
    XFile f;
    try {
      f = await c.takePicture();
    } catch (_) {
      _set(_shutter.done);
      if (!_suspended) _show('Couldn\'t take the photo. Try again.');
      return;
    }
    _set(_shutter.done);
    _captured.add(f.path);
    if (!mounted || _suspended) return;
    await _review([f]);
  }

  Future<void> _startVideo() async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized || c.value.isRecordingVideo) {
      _set(_shutter.done);
      return;
    }
    HapticFeedback.heavyImpact();
    _set(); // the ring grows and turns red straight away
    try {
      if (_flash == _Flash.on && _isBack) {
        try {
          await c.setFlashMode(FlashMode.torch);
          _torch = true;
        } catch (_) {}
      }
      await c.startVideoRecording();
    } catch (_) {
      final torch = _torch;
      _endVideo();
      if (torch) await _applyFlash(c);
      _show('Couldn\'t start the video. Try again.');
      return;
    }
    if (!_shutter.isVideo || _ctrl != c) {
      // Discarded or closed while it was starting.
      try {
        _delete((await c.stopVideoRecording()).path);
      } catch (_) {}
      return;
    }
    _shutter.started(_now);
    _rec.forward(from: 0);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _act(_shutter.tick(_now)));
    _set();
  }

  Future<void> _stopVideo() async {
    _ticker?.cancel();
    _ticker = null;
    _rec.stop();
    final c = _ctrl;
    XFile? f;
    if (c != null && c.value.isRecordingVideo) {
      try {
        f = await c.stopVideoRecording();
      } catch (_) {}
    }
    HapticFeedback.lightImpact();
    final torch = _torch;
    _endVideo();
    if (torch) await _applyFlash(c);
    if (f != null) _captured.add(f.path);
    // Sent to the background meanwhile: that path keeps and reviews the clip.
    if (!mounted || _suspended) return;
    if (f == null) {
      _show('Couldn\'t save the video. Try again.');
      return;
    }
    if (!await _fits(f)) {
      _captured.remove(f.path);
      _delete(f.path);
      _show('That video is too big to send. Keep it under $kChatVideoMaxMb MB.');
      return;
    }
    await _review([f]);
  }

  /// X or back while recording: stop and throw the video away.
  Future<void> _discard() async {
    if (!_shutter.isVideo) return;
    _holdTimer?.cancel();
    _ticker?.cancel();
    _pointer = null;
    _stopOnUp = false;
    final c = _ctrl;
    final torch = _torch;
    _endVideo();
    if (c != null && c.value.isRecordingVideo) {
      try {
        _delete((await c.stopVideoRecording()).path);
      } catch (_) {}
    }
    if (torch) await _applyFlash(c);
    HapticFeedback.lightImpact();
    _show('Video discarded');
  }

  void _endVideo() {
    _ticker?.cancel();
    _ticker = null;
    _torch = false;
    _shutter.done();
    if (!mounted) return; // _rec is gone
    _rec
      ..stop()
      ..value = 0;
    setState(() {});
  }

  // ---- after the shot ------------------------------------------------------

  /// The send preview. Sent: this screen closes with the items. Cancelled:
  /// back to the camera to try again.
  Future<void> _review(List<XFile> files) async {
    if (!mounted || files.isEmpty) return;
    _covered = true;
    unawaited(_serial(_close));
    final items = await showMediaSendPreview(context, files);
    if (!mounted) return;
    if (items != null && items.isNotEmpty) {
      _leaving = true;
      for (final it in items) {
        _captured.remove(it.file.path);
      }
      Navigator.of(context).pop(items);
      return;
    }
    for (final f in files) {
      if (_captured.remove(f.path)) _delete(f.path);
    }
    _covered = false;
    if (!_suspended) unawaited(_serial(_open));
  }

  Future<void> _gallery() async {
    if (_covered || _shutter.phase != ShutterPhase.idle) return;
    _covered = true;
    unawaited(_serial(_close));
    var picked = const <XFile>[];
    try {
      picked = await ImagePicker().pickMultipleMedia(maxWidth: 1600, maxHeight: 1600, imageQuality: 85, limit: kChatMediaMaxItems);
    } catch (_) {}
    final keep = <XFile>[];
    var tooBig = false;
    for (final f in picked.take(kChatMediaMaxItems)) {
      if (isVideoFile(f) && !await _fits(f)) {
        tooBig = true;
        continue;
      }
      keep.add(f);
    }
    if (!mounted) return;
    if (tooBig) _show(keep.isEmpty ? 'That video is too big. Pick one under $kChatVideoMaxMb MB.' : 'Left out a video over $kChatVideoMaxMb MB.');
    if (keep.isNotEmpty) {
      await _review(keep);
      return;
    }
    _covered = false;
    if (!_suspended) unawaited(_serial(_open));
  }

  static Future<bool> _fits(XFile f) async {
    try {
      return await f.length() <= kChatVideoMaxMb * 1024 * 1024;
    } catch (_) {
      return false;
    }
  }

  static void _delete(String path) => File(path).delete().catchError((_) => File(path));

  // ---- controls --------------------------------------------------------------

  void _flip() {
    if (_shutter.phase != ShutterPhase.idle || (_cams?.length ?? 0) < 2 || _covered) return;
    HapticFeedback.selectionClick();
    _set(() {
      _flipTurns += 0.5;
      _lens = _isBack ? CameraLensDirection.front : CameraLensDirection.back;
    });
    _serial(() async {
      await _close();
      await _open();
    });
  }

  void _cycleFlash() {
    HapticFeedback.selectionClick();
    final c = _ctrl;
    if (_shutter.isVideo) {
      // While recording the flash is a torch.
      if (c == null) return;
      _set(() => _torch = !_torch);
      c.setFlashMode(_torch ? FlashMode.torch : FlashMode.off).catchError((Object _) {});
      return;
    }
    _set(() => _flash = _Flash.values[(_flash.index + 1) % _Flash.values.length]);
    _applyFlash();
    _show(switch (_flash) {
      _Flash.off => 'Flash off',
      _Flash.auto => 'Flash auto',
      _Flash.on => 'Flash on. Videos use the torch.',
    }, short: true);
  }

  void _zoomStart(ScaleStartDetails _) => _zoomFrom = _zoom;

  void _zoomUpdate(ScaleUpdateDetails d) {
    final c = _ctrl;
    if (c == null || d.pointerCount < 2 || _maxZoom <= _minZoom) return;
    final z = (_zoomFrom * d.scale).clamp(_minZoom, math.min(_maxZoom, 10.0)).toDouble();
    if ((z - _zoom).abs() < 0.01) return;
    _set(() {
      _zoom = z;
      _zooming = true;
    });
    c.setZoomLevel(z).catchError((Object _) {});
  }

  Future<void> _openSettings({bool forMic = false}) async {
    if (forMic) _retryMic = true;
    await Geolocator.openAppSettings();
  }

  void _show(String message, {bool short = false}) {
    _toastTimer?.cancel();
    _set(() => _toast = message);
    _toastTimer = Timer(Duration(milliseconds: short ? 1300 : 2600), () => _set(() => _toast = null));
  }

  // ---- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    final live = _live;
    final video = _shutter.isVideo;
    final blocked = _state == _CamState.denied || _state == _CamState.unavailable;
    final canFlip = (_cams?.length ?? 0) > 1;

    return PopScope(
      canPop: !video,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _discard();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (live && c != null)
                _preview(c)
              else if (blocked)
                _blockedBody()
              else
                const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))),
              // Shutter blink on a photo.
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _blink ? 0.85 : 0,
                  duration: Duration(milliseconds: _blink ? 30 : 160),
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
              // Shades so the white controls read on a bright scene.
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 140,
                child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black45, Colors.transparent])))),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 240,
                child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black54, Colors.transparent])))),
              ),
              Positioned(left: 0, right: 0, top: 0, child: _topBar(live: live, video: video)),
              if (!blocked) Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar(live: live, video: video, canFlip: canFlip)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(CameraController c) {
    final size = c.value.previewSize;
    Widget view = CameraPreview(c);
    if (size != null) {
      // Edge to edge: cover the screen, cropping the long sides.
      view = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: size.shortestSide, height: size.longestSide, child: view),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: _zoomStart,
      onScaleUpdate: _zoomUpdate,
      onScaleEnd: (_) => _set(() => _zooming = false),
      onDoubleTap: _flip,
      child: SizedBox.expand(child: view),
    );
  }

  Widget _topBar({required bool live, required bool video}) {
    final flashIcon = video
        ? (_torch ? AppIcons.lightningFill : AppIcons.lightningSlash)
        : switch (_flash) {
            _Flash.off => AppIcons.lightningSlash,
            _Flash.auto => AppIcons.lightningA,
            _Flash.on => AppIcons.lightningFill,
          };
    final flashOn = video ? _torch : _flash == _Flash.on;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _GlassButton(
                  icon: AppIcons.x,
                  tooltip: video ? 'Discard video' : 'Close',
                  onTap: video ? _discard : () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Center(
                    child: video ? AnimatedBuilder(animation: _rec, builder: (_, _) => _RecPill(elapsed: _shutter.recorded(_now), max: _shutter.maxClip)) : const SizedBox.shrink(),
                  ),
                ),
                if (live && _isBack)
                  _GlassButton(icon: flashIcon, tooltip: video ? (_torch ? 'Torch off' : 'Torch on') : 'Flash', onTap: _cycleFlash, highlight: flashOn)
                else
                  const SizedBox(width: _GlassButton.size),
              ],
            ),
            if (_micOff && live && !video)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _NoticePill(
                  icon: AppIcons.microphoneSlash,
                  text: 'Microphone is off, so videos record without sound.',
                  action: 'Settings',
                  onAction: () => _openSettings(forMic: true),
                ),
              ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: _toast == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      key: ValueKey(_toast),
                      padding: const EdgeInsets.only(top: 10),
                      child: _NoticePill(text: _toast!),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar({required bool live, required bool video, required bool canFlip}) {
    final phase = _shutter.phase;
    final hint = switch (phase) {
      ShutterPhase.locked => 'Tap to stop',
      // Held: the lock pill over the shutter says "slide up" itself.
      ShutterPhase.recording || ShutterPhase.busy => '',
      _ => 'Tap for photo, hold for video',
    };
    final showZoom = live && (_zooming || _zoom > _minZoom + 0.05);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedOpacity(
              opacity: showZoom ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _NoticePill(text: '${_zoom.toStringAsFixed(1)}×', compact: true),
              ),
            ),
            AnimatedOpacity(
              opacity: hint.isEmpty || !live ? 0 : 1,
              duration: const Duration(milliseconds: 160),
              child: Text(
                hint.isEmpty ? ' ' : hint,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600, shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Center(
                    child: video ? const SizedBox(width: 52) : _GlassButton(icon: AppIcons.images, tooltip: 'Gallery', onTap: _gallery, big: true),
                  ),
                ),
                Semantics(
                  button: true,
                  enabled: live,
                  label: 'Shutter. Tap for photo, hold for video',
                  onTap: live ? _semanticTap : null,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onDown,
                    onPointerMove: _onMove,
                    onPointerUp: _onUp,
                    onPointerCancel: _onCancel,
                    child: AnimatedBuilder(
                      animation: _rec,
                      builder: (_, _) => _ShutterButton(
                        phase: phase,
                        progress: _rec.value,
                        dragY: _shutter.dragY,
                        lockProgress: _shutter.lockProgress,
                        enabled: live,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: video || !canFlip
                        ? const SizedBox(width: 52)
                        : AnimatedRotation(
                            turns: _flipTurns,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            child: _GlassButton(icon: AppIcons.cameraRotate, tooltip: 'Flip camera', onTap: _flip, big: true),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _blockedBody() {
    final denied = _state == _CamState.denied;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
                child: const Icon(AppIcons.cameraSlash, size: 34, color: Colors.white),
              ),
              const SizedBox(height: 18),
              Text(
                denied ? 'Camera access is off' : 'Can\'t open the camera',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                denied
                    ? 'Allow TT Spot to use the camera, and the microphone for videos, in Settings to take photos and videos here.'
                    : 'Another app may be using it. Close it and try again.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14.5, height: 1.35),
              ),
              const SizedBox(height: 24),
              _PillButton(label: denied ? 'Open settings' : 'Try again', onTap: denied ? _openSettings : () => _serial(_open)),
              if (denied) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => _serial(_open),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
              const SizedBox(height: 2),
              TextButton.icon(
                onPressed: _gallery,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(AppIcons.images, size: 18),
                label: const Text('Choose from gallery', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round shutter. Idle: a white ring and disc. Pressed: the disc dips.
/// Recording: it grows, the ring turns red with the progress running round
/// it, and the disc becomes a red dot (a red stop square once locked).
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.phase, required this.progress, required this.dragY, required this.lockProgress, required this.enabled});
  final ShutterPhase phase;
  final double progress;
  final double dragY;
  final double lockProgress;
  final bool enabled;

  static const size = 80.0;

  @override
  Widget build(BuildContext context) {
    final locked = phase == ShutterPhase.locked;
    final held = phase == ShutterPhase.recording;
    final video = held || locked;
    final pressed = phase == ShutterPhase.pressed;
    final inner = video ? (locked ? 28.0 : 32.0) : (pressed ? 54.0 : 64.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (held)
            Positioned(
              bottom: size + 24 - dragY * 0.5,
              child: _LockHint(progress: lockProgress),
            ),
          Transform.translate(
            offset: Offset(0, held ? dragY * 0.5 : 0),
            child: AnimatedScale(
              scale: video ? 1.28 : 1,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: CustomPaint(
                painter: _RingPainter(progress: video ? progress : 0, video: video, color: enabled ? Colors.white : Colors.white38, red: AppColors.brand),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: inner,
                      height: inner,
                      decoration: BoxDecoration(
                        color: video ? AppColors.brand : (enabled ? Colors.white : Colors.white38),
                        borderRadius: BorderRadius.circular(locked ? 7 : inner / 2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.video, required this.color, required this.red});
  final double progress;
  final bool video;
  final Color color;
  final Color red;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.5;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - stroke / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = video ? red.withValues(alpha: 0.4) : color,
    );
    if (video && progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = red,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.video != video || old.color != color || old.red != red;
}

/// The pill over a held shutter: a lock and an up arrow, "slide up to lock".
class _LockHint extends StatelessWidget {
  const _LockHint({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => _Glass(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.lock, size: 18, color: Color.lerp(Colors.white, AppColors.brand, progress)),
              SizedBox(height: 6 + 6 * (1 - progress)),
              const Icon(AppIcons.caretUp, size: 14, color: Colors.white70),
            ],
          ),
        ),
      );
}

/// Recording time, top centre: a blinking red dot and m:ss.
class _RecPill extends StatefulWidget {
  const _RecPill({required this.elapsed, required this.max});
  final Duration elapsed;
  final Duration max;

  @override
  State<_RecPill> createState() => _RecPillState();
}

class _RecPillState extends State<_RecPill> with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  static String _clock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final left = widget.max - widget.elapsed;
    final ending = left <= const Duration(seconds: 10);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: ending ? AppColors.brand : Colors.black54, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.25, end: 1.0).animate(_blink),
            child: Container(width: 8, height: 8, decoration: BoxDecoration(color: ending ? Colors.white : AppColors.brand, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 7),
          Text(
            _clock(widget.elapsed),
            maxLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

/// Frosted dark glass behind a round control or a pill.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, required this.borderRadius, this.highlight = false});
  final Widget child;
  final BorderRadius borderRadius;
  final bool highlight;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: highlight ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.32),
              borderRadius: borderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: child,
          ),
        ),
      );
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.tooltip, required this.onTap, this.big = false, this.highlight = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool big;
  final bool highlight;

  static const size = 44.0;

  @override
  Widget build(BuildContext context) {
    final s = big ? 52.0 : size;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: _Glass(
          borderRadius: BorderRadius.circular(s / 2),
          highlight: highlight,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: s, height: s, child: Icon(icon, size: big ? 24 : 22, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A short glass message: a toast, the zoom level, the mic notice.
class _NoticePill extends StatelessWidget {
  const _NoticePill({required this.text, this.icon, this.action, this.onAction, this.compact = false});
  final String text;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) => _Glass(
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 5 : 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: compact ? 12.5 : 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onAction,
                  child: Text(action!, style: TextStyle(color: AppColors.brand, fontSize: 13.5, fontWeight: FontWeight.w800)),
                ),
              ],
            ],
          ),
        ),
      );
}

/// White pill button on the black screen.
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
            child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      );
}
