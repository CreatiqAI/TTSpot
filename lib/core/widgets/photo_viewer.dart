import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_icons.dart';

/// Full-screen photos on black: pinch or double-tap to zoom, swipe between
/// them. Tap once to close (once the double-tap window has passed, so a
/// double-tap still zooms; a zoomed photo zooms back out first), pull the
/// photo away (down or up, or sideways off the only, first or last photo),
/// or X or back.
Future<void> showPhotoViewer(BuildContext context, List<String> urls, {int initial = 0}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      // See-through, so the page underneath shows as the black fades on a pull.
      opaque: false,
      pageBuilder: (_, _, _) => PhotoViewer(urls: urls, initial: initial),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.urls, this.initial = 0, this.imageFor});
  final List<String> urls;
  final int initial;

  /// The picture for a url; cached network images by default (tests pass
  /// in-memory ones).
  final ImageProvider Function(String url)? imageFor;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

/// What a one-finger drag does, picked on its first move.
enum _Drag { pages, away }

class _PhotoViewerState extends State<PhotoViewer> with SingleTickerProviderStateMixin {
  late final _pages = PageController(initialPage: widget.initial);
  late int _page = widget.initial;
  // While a photo is zoomed, a drag pans it instead of turning the page or closing.
  bool _zoomed = false;

  /// Released past this far from the middle, or flung away faster than
  /// [_flingAt], the viewer closes; otherwise the photo springs back.
  static const _closeAt = 110.0;
  static const _flingAt = 800.0;

  // How far the photo has been pulled from the middle, and the animation
  // that springs it back or carries it off.
  final _pull = ValueNotifier<Offset>(Offset.zero);
  late final _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Animation<Offset>? _settleTo;

  _Drag? _drag;
  // A page turn in progress, fed to the PageView's own scroll position so
  // snapping and flings feel exactly like a normal swipe.
  Drag? _pageDrag;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      final to = _settleTo;
      if (to != null) _pull.value = to.value;
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    _pull.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _animatePull(Offset to, Curve curve) {
    _settleTo = Tween(begin: _pull.value, end: to).chain(CurveTween(curve: curve)).animate(_settle);
    _settle.forward(from: 0);
  }

  /// First move of a drag: sideways turns the page when there is one that
  /// way. Up, down, or sideways past the only, first or last photo pulls
  /// the photo away.
  _Drag _pick(DragUpdateDetails d) {
    final sideways = d.delta.dx.abs() > d.delta.dy.abs();
    final page = _pages.hasClients ? (_pages.page ?? _page.toDouble()) : _page.toDouble();
    final more = d.delta.dx < 0 ? page < widget.urls.length - 1.01 : page > 0.01;
    if (sideways && more && _pages.hasClients) {
      _pageDrag = _pages.position.drag(
        DragStartDetails(globalPosition: d.globalPosition, localPosition: d.localPosition, sourceTimeStamp: d.sourceTimeStamp),
        () => _pageDrag = null,
      );
      return _Drag.pages;
    }
    _settle.stop();
    return _Drag.away;
  }

  void _dragStart(DragStartDetails d) => _drag = null;

  void _dragUpdate(DragUpdateDetails d) {
    if (_closing) return;
    switch (_drag ??= _pick(d)) {
      case _Drag.pages:
        _pageDrag?.update(DragUpdateDetails(
          sourceTimeStamp: d.sourceTimeStamp,
          delta: Offset(d.delta.dx, 0),
          primaryDelta: d.delta.dx,
          globalPosition: d.globalPosition,
          localPosition: d.localPosition,
        ));
      case _Drag.away:
        _pull.value += d.delta;
    }
  }

  void _dragEnd(DragEndDetails d) {
    final drag = _drag;
    _drag = null;
    if (drag == _Drag.pages) {
      final vx = d.velocity.pixelsPerSecond.dx;
      _pageDrag?.end(DragEndDetails(velocity: Velocity(pixelsPerSecond: Offset(vx, 0)), primaryVelocity: vx));
      _pageDrag = null;
    } else if (drag == _Drag.away) {
      _letGo(d.velocity.pixelsPerSecond);
    }
  }

  void _dragCancel() {
    final drag = _drag;
    _drag = null;
    _pageDrag?.cancel();
    _pageDrag = null;
    if (drag == _Drag.away) _letGo(Offset.zero);
  }

  /// Far enough, or flung away from the middle: close. Otherwise spring back.
  void _letGo(Offset velocity) {
    if (_closing) return;
    final pull = _pull.value;
    final dist = pull.distance;
    // Speed along the pull, so a flick back towards the middle does not close.
    final away = dist == 0 ? velocity.distance : (velocity.dx * pull.dx + velocity.dy * pull.dy) / dist;
    if (dist > _closeAt || away > _flingAt) {
      _close(dist == 0 ? velocity : pull);
    } else {
      _animatePull(Offset.zero, Curves.easeOutBack);
    }
  }

  /// A single tap on the photo (not part of a double-tap): close.
  void _tapClose() {
    if (_closing || _drag != null) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  /// The photo carries on the way it was going while the viewer fades out.
  void _close(Offset direction) {
    _closing = true;
    final dir = direction.distance == 0 ? const Offset(0, 1) : direction / direction.distance;
    _animatePull(_pull.value + dir * MediaQuery.sizeOf(context).height * 0.5, Curves.easeOutCubic);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.urls.length > 1;
    // 0 in place, 1 pulled 40% of the screen height away.
    final reach = MediaQuery.sizeOf(context).height * 0.4;
    double progress(Offset pull) => (pull.distance / reach).clamp(0.0, 1.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // The black, fading as the photo comes away.
            Positioned.fill(
              child: ValueListenableBuilder<Offset>(
                valueListenable: _pull,
                builder: (_, pull, _) => ColoredBox(color: Colors.black.withValues(alpha: 1 - progress(pull))),
              ),
            ),
            RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              // Zoomed in, the photo's own pan takes every drag.
              gestures: _zoomed
                  ? const <Type, GestureRecognizerFactory>{}
                  : {
                      _PullRecognizer: GestureRecognizerFactoryWithHandlers<_PullRecognizer>(
                        () => _PullRecognizer(debugOwner: this),
                        (r) => r
                          // The phone's own touch slop, as the zoom uses; its pan
                          // waits for twice that, so this drag always wins.
                          ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
                          // The first update carries the slop, so its direction picks the drag.
                          ..dragStartBehavior = DragStartBehavior.down
                          ..onStart = _dragStart
                          ..onUpdate = _dragUpdate
                          ..onEnd = _dragEnd
                          ..onCancel = _dragCancel,
                      ),
                    },
              child: ValueListenableBuilder<Offset>(
                valueListenable: _pull,
                builder: (_, pull, child) => Transform.translate(
                  offset: pull,
                  child: Transform.scale(scale: 1 - 0.2 * progress(pull), child: child),
                ),
                child: PageView.builder(
                  controller: _pages,
                  // Swipes come through the pull recognizer above, which turns
                  // pages itself; the clamp keeps a turn inside the photos.
                  physics: const NeverScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                  itemCount: widget.urls.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => _ZoomablePhoto(
                    image: widget.imageFor?.call(widget.urls[i]) ?? CachedNetworkImageProvider(widget.urls[i]),
                    onZoom: (z) {
                      if (z != _zoomed) setState(() => _zoomed = z);
                    },
                    onTap: _tapClose,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<Offset>(
              valueListenable: _pull,
              // The X and the counter get out of the way as soon as a pull starts.
              builder: (_, pull, child) => Opacity(opacity: (1 - progress(pull) * 4).clamp(0.0, 1.0), child: child),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      // Dark backings so both stay readable over a white photo.
                      DecoratedBox(
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: IconButton(
                          tooltip: 'Close',
                          icon: const Icon(AppIcons.x, color: Colors.white, size: 22),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const Spacer(),
                      if (many)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                          child: Text('${_page + 1}/${widget.urls.length}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      const SizedBox(width: 8),
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

/// A one-finger drag that claims the gesture after the touch slop, as a
/// scroll does, so it wins over the zoom's own pan (which waits twice as
/// long). A second finger landing before then hands the gesture to the
/// pinch instead.
class _PullRecognizer extends PanGestureRecognizer {
  _PullRecognizer({super.debugOwner});

  final _down = <int>{};
  bool _claimed = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_down.isNotEmpty) {
      if (!_claimed) resolve(GestureDisposition.rejected);
      return;
    }
    _down.add(event.pointer);
    super.addAllowedPointer(event);
  }

  @override
  void acceptGesture(int pointer) {
    _claimed = true;
    super.acceptGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _down.clear();
    _claimed = false;
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) =>
      globalDistanceMoved.abs() > computeHitSlop(pointerDeviceKind, gestureSettings);
}

/// One photo: pinch to zoom, double-tap to zoom in on a spot and back out.
/// Tells the viewer when it is zoomed, so drags pan instead. A single tap
/// (no second tap within the double-tap timeout) zooms a zoomed photo back
/// out, else asks the viewer to close.
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.image, required this.onZoom, required this.onTap});
  final ImageProvider image;
  final ValueChanged<bool> onZoom;
  final VoidCallback onTap;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _zoom = TransformationController();
  Offset _tapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      final z = _zoom.value.getMaxScaleOnAxis() > 1.01;
      if (z == _zoomed) return;
      _zoomed = z;
      widget.onZoom(z);
    });
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  /// Double-tap: zoom in 2.5x on that spot, or back out.
  void _toggleZoom() {
    if (_zoomed) {
      _zoom.value = Matrix4.identity();
      return;
    }
    const s = 2.5;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-_tapAt.dx * (s - 1), -_tapAt.dy * (s - 1), 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  /// Single tap: out of a zoom first, else close.
  void _tap() {
    if (_zoomed) {
      _zoom.value = Matrix4.identity();
      return;
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        // With a double-tap handler beside it, onTap only fires once the
        // double-tap timeout passes without a second tap.
        onTap: _tap,
        onDoubleTapDown: (d) => _tapAt = d.localPosition,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _zoom,
          maxScale: 5,
          child: SizedBox.expand(
            child: Image(
              image: widget.image,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, prog) => prog == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              errorBuilder: (_, _, _) => const Center(child: Icon(AppIcons.imageBroken, color: Colors.white54, size: 40)),
            ),
          ),
        ),
      );
}
