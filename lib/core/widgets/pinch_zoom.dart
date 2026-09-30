import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Instagram-style pinch on a photo inside a page: two fingers lift the
/// photo out over everything (the page dims behind it), it follows the
/// fingers, and when a finger lets go it springs back into its place.
///
/// Built on raw pointer events, so one-finger gestures (scrolling, swiping
/// between photos, taps, double-tap like) pass through untouched. While a
/// pinch is on, [PinchZoom.active] is true; the scroll views around the photo
/// use [PinchLockScrollPhysics] so the pinch doesn't drag or fling them.
class PinchZoom extends StatefulWidget {
  const PinchZoom({super.key, required this.child, this.maxScale = 4});

  final Widget child;
  final double maxScale;

  /// True while any photo is pinched (only one can be at a time).
  static final active = ValueNotifier<bool>(false);

  @override
  State<PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<PinchZoom> with SingleTickerProviderStateMixin {
  final _pointers = <int, Offset>{};
  OverlayEntry? _entry;

  /// Where the photo sat on screen when the pinch began; the lifted copy is
  /// drawn there and transformed.
  Rect _rect = Rect.zero;
  Offset _startFocal = Offset.zero;
  double _startSpan = 1;
  double _scale = 1;
  Offset _shift = Offset.zero;

  // Spring back: from wherever the fingers left it to the photo's place now
  // (the page may have moved a hair under the pinch).
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
    ..addListener(_onBack)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _end();
    });
  double _fromScale = 1;
  Offset _fromShift = Offset.zero;
  Offset _toShift = Offset.zero;

  bool get _zooming => _entry != null;

  // A finger that lands on the photo starts a global watch: once the page
  // under it is scrolling, Flutter stops hit-testing new touches into the
  // list, so a second finger that lands a beat later would never reach this
  // widget. The watch sees it anyway, and every move and lift after it.
  void _down(PointerDownEvent e) {
    if (_pointers.isEmpty) GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
    _add(e);
  }

  void _route(PointerEvent e) {
    if (e is PointerDownEvent) {
      if (!_pointers.containsKey(e.pointer) && _pointers.isNotEmpty && _onPhoto(e.position)) _add(e);
    } else if (e is PointerMoveEvent) {
      _move(e);
    } else if (e is PointerUpEvent || e is PointerCancelEvent) {
      _up(e);
    }
  }

  bool _onPhoto(Offset p) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).inflate(24).contains(p);
  }

  void _add(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && !_zooming && !PinchZoom.active.value) _start();
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (!_zooming || _back.isAnimating || _pointers.length < 2) return;
    final (focal, span) = _measure();
    _scale = (span / _startSpan).clamp(1.0, widget.maxScale);
    _shift = focal - _startFocal;
    _entry!.markNeedsBuild();
  }

  void _up(PointerEvent e) {
    if (_pointers.remove(e.pointer) == null) return;
    if (_pointers.isEmpty) GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    if (_zooming && _pointers.length < 2 && !_back.isAnimating) _release();
  }

  (Offset, double) _measure() {
    final p = _pointers.values.take(2).toList();
    return ((p[0] + p[1]) / 2, (p[0] - p[1]).distance);
  }

  void _start() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _rect = box.localToGlobal(Offset.zero) & box.size;
    final (focal, span) = _measure();
    _startFocal = focal;
    _startSpan = span < 1 ? 1 : span;
    _scale = 1;
    _shift = Offset.zero;
    PinchZoom.active.value = true;
    _entry = OverlayEntry(builder: _lifted);
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    setState(() {});
  }

  void _release() {
    final box = context.findRenderObject() as RenderBox?;
    final now = box != null && box.attached ? box.localToGlobal(Offset.zero) : _rect.topLeft;
    _fromScale = _scale;
    _fromShift = _shift;
    _toShift = now - _rect.topLeft;
    _back.forward(from: 0);
  }

  void _onBack() {
    final t = Curves.easeOutCubic.transform(_back.value);
    _scale = _fromScale + (1 - _fromScale) * t;
    _shift = Offset.lerp(_fromShift, _toShift, t)!;
    _entry?.markNeedsBuild();
  }

  void _end() {
    _entry?.remove();
    _entry = null;
    PinchZoom.active.value = false;
    if (mounted) setState(() {});
  }

  Widget _lifted(BuildContext context) {
    // Scale about the point first pinched, then follow the fingers.
    final focal = _startFocal - _rect.topLeft;
    final m = Matrix4.diagonal3Values(_scale, _scale, 1)
      ..setTranslationRaw(_shift.dx + focal.dx * (1 - _scale), _shift.dy + focal.dy * (1 - _scale), 0);
    final dim = ((_scale - 1) / 1.2).clamp(0.0, 1.0) * 0.6;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: dim))),
          Positioned.fromRect(rect: _rect, child: Transform(transform: m, child: widget.child)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (_pointers.isNotEmpty) GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    if (_zooming) {
      _entry!.remove();
      _entry = null;
      PinchZoom.active.value = false;
    }
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _down,
        // The lifted copy stands in for the photo while it's out.
        child: Opacity(opacity: _zooming ? 0 : 1, child: widget.child),
      );
}

/// Scroll physics that hold still while a photo is pinched ([PinchZoom]):
/// finger movement doesn't scroll and letting go doesn't fling.
///
/// On a PageView pass `pageSnapping: false` and
/// `physics: const PinchLockScrollPhysics(parent: PageScrollPhysics())`,
/// else PageView puts its own page physics outside this one.
class PinchLockScrollPhysics extends ScrollPhysics {
  const PinchLockScrollPhysics({super.parent});

  @override
  PinchLockScrollPhysics applyTo(ScrollPhysics? ancestor) => PinchLockScrollPhysics(parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      PinchZoom.active.value ? 0 : super.applyPhysicsToUserOffset(position, offset);

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) =>
      super.createBallisticSimulation(position, PinchZoom.active.value ? 0 : velocity);
}
