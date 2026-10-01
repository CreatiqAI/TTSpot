import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/plate_blur.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../application/plate_hiding.dart';
import '../../domain/car_recognition.dart';
import '../../domain/plate_geometry.dart';

/// Check the plate: [photo] full screen with its blur boxes over it. Pinch
/// or drag the photo to zoom and pan; drag a box to move it, pinch it or
/// pull a corner to resize it; tap the photo to move the selected blur
/// there. Add another blur for a second plate, remove one, Reset to what the
/// recogniser found, Done to keep it. A photo that went up blurred with its
/// original kept gets "Show original": Done then puts the original back
/// (or a new blur of it) on Save. True when Done changed what gets blurred
/// (the form then shows the new copy).
Future<bool> showPlateEditor(BuildContext context, CarFormPhoto photo) async {
  final done = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => PlateEditorScreen(photo: photo)),
  );
  return done ?? false;
}

class PlateEditorScreen extends ConsumerStatefulWidget {
  const PlateEditorScreen({super.key, required this.photo});
  final CarFormPhoto photo;

  @override
  ConsumerState<PlateEditorScreen> createState() => _PlateEditorScreenState();
}

class _PlateEditorScreenState extends ConsumerState<PlateEditorScreen> {
  final _zoomer = TransformationController();
  double _zoom = 1;

  bool _loading = true;
  bool _loadFailed = false;
  bool _applying = false;

  /// Showing the kept original of a saved blurred photo ("Show original").
  bool _showingOriginal = false;

  /// Fetching the original or the blurred copy for the switch above.
  bool _switching = false;
  /// Moved, resized, added or removed a box since opening.
  bool _touched = false;

  ImageProvider? _image;
  (int, int) _px = (4, 3);
  List<PlateBox> _boxes = [];
  int? _selected;

  /// The editing area and the photo laid out in it, before any zoom.
  Size _area = Size.zero;
  Size _shown = Size.zero;

  // The box (or corner) being dragged: where it started and where the
  // fingers started, in screen pixels.
  PlateBox? _dragFrom;
  Offset _dragStart = Offset.zero;

  @override
  void initState() {
    super.initState();
    _zoomer.addListener(_onZoom);
    _load();
  }

  @override
  void dispose() {
    _zoomer.removeListener(_onZoom);
    _zoomer.dispose();
    super.dispose();
  }

  void _onZoom() {
    final z = _zoomer.value.getMaxScaleOnAxis();
    if ((z - _zoom).abs() > 0.01) setState(() => _zoom = z);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final p = widget.photo;
    final ok = await ref.read(plateHiderProvider).loadForEditor(p);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadFailed = !ok || p.original == null;
      if (_loadFailed) return;
      _image = MemoryImage(p.original!);
      _px = p.size ?? _px;
      _boxes = p.editorBoxes;
      _selected = _boxes.isEmpty ? null : 0;
      _showingOriginal = p.restored;
    });
  }

  /// The photo went up blurred and its original is kept: it can be shown.
  bool get _hasOriginal => widget.photo.canShowOriginal || widget.photo.restored;

  /// Show original / Keep blurred: swaps what the editor shows. Nothing
  /// changes on the car until Done (and then Save).
  Future<void> _toggleOriginal() async {
    final hider = ref.read(plateHiderProvider);
    final toOriginal = !_showingOriginal;
    setState(() => _switching = true);
    final loaded = toOriginal ? await hider.loadOriginal(widget.photo) : await hider.loadSavedCopy(widget.photo);
    if (!mounted) return;
    if (loaded == null) {
      setState(() => _switching = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(toOriginal ? 'Couldn\'t load the original. Check your connection and try again.' : 'Couldn\'t load the blurred photo. Try again.')));
      return;
    }
    _zoomer.value = Matrix4.identity();
    setState(() {
      _switching = false;
      _showingOriginal = toOriginal;
      _image = MemoryImage(loaded.$1);
      _px = loaded.$2;
      // The original comes back clean (tap the plate to blur it again); the
      // blurred copy needs nothing on top.
      _boxes = toOriginal && widget.photo.restored ? widget.photo.editorBoxes : [];
      _selected = _boxes.isEmpty ? null : 0;
      _touched = true;
    });
    HapticFeedback.selectionClick();
  }

  double get _aspect => _px.$2 == 0 ? 4 / 3 : _px.$1 / _px.$2;

  // ── editing ──

  void _select(int i) {
    if (_selected != i) setState(() => _selected = i);
  }

  void _set(int i, PlateBox b) => setState(() {
        _boxes[i] = b;
        _touched = true;
      });

  /// Screen pixels → fractions of the photo, at the current zoom.
  Offset _toFraction(Offset screenDelta) {
    final z = _zoom <= 0 ? 1.0 : _zoom;
    if (_shown.isEmpty) return Offset.zero;
    return Offset(screenDelta.dx / (_shown.width * z), screenDelta.dy / (_shown.height * z));
  }

  void _boxStart(int i, ScaleStartDetails d) {
    _select(i);
    _dragFrom = _boxes[i];
    _dragStart = d.focalPoint;
  }

  void _boxUpdate(int i, ScaleUpdateDetails d) {
    final from = _dragFrom;
    if (from == null || i >= _boxes.length) return;
    final f = _toFraction(d.focalPoint - _dragStart);
    final sized = d.pointerCount > 1 ? from.scaled(d.scale) : from;
    _set(i, sized.moved(f.dx, f.dy));
  }

  void _cornerStart(DragStartDetails d) {
    final i = _selected;
    if (i == null) return;
    _dragFrom = _boxes[i];
    _dragStart = d.globalPosition;
  }

  void _cornerUpdate(PlateCorner c, DragUpdateDetails d) {
    final i = _selected, from = _dragFrom;
    if (i == null || from == null || i >= _boxes.length) return;
    final f = _toFraction(d.globalPosition - _dragStart);
    _set(i, from.dragCorner(c, f.dx, f.dy));
  }

  void _dragEnd() => _dragFrom = null;

  /// A tap on the photo moves the selected blur there (or the first one
  /// there when there is none): tap the plate and the blur lands on it.
  void _tapPhoto(TapUpDetails d) {
    if (_shown.isEmpty) return;
    final fx = (d.localPosition.dx / _shown.width).clamp(0.0, 1.0);
    final fy = (d.localPosition.dy / _shown.height).clamp(0.0, 1.0);
    setState(() {
      _touched = true;
      if (_boxes.isEmpty) {
        _boxes.add(defaultPlateBox(aspect: _aspect).centredAt(fx, fy));
        _selected = 0;
        return;
      }
      final i = _selected ?? _boxes.length - 1;
      _boxes[i] = _boxes[i].centredAt(fx, fy);
      _selected = i;
    });
    HapticFeedback.selectionClick();
  }

  void _add() {
    if (_boxes.length >= kMaxPlateBoxes) return;
    double? cx, cy;
    if (_zoom > 1.05 && !_shown.isEmpty) {
      // Zoomed in: the new blur lands in the middle of what's on screen.
      final scene = _zoomer.toScene(Offset(_area.width / 2, _area.height / 2));
      cx = ((scene.dx - (_area.width - _shown.width) / 2) / _shown.width).clamp(0.0, 1.0);
      cy = ((scene.dy - (_area.height - _shown.height) / 2) / _shown.height).clamp(0.0, 1.0);
    }
    setState(() {
      _boxes.add(nextPlateBox(_boxes, aspect: _aspect, cx: cx, cy: cy));
      _selected = _boxes.length - 1;
      _touched = true;
    });
  }

  void _remove() {
    final i = _selected;
    if (i == null || i >= _boxes.length) return;
    setState(() {
      _boxes.removeAt(i);
      _selected = _boxes.isEmpty ? null : _boxes.length - 1;
      _touched = true;
    });
  }

  void _reset() {
    setState(() {
      // On a shown original there's nothing to go back to but no blur.
      _boxes = _showingOriginal && !widget.photo.restored ? <PlateBox>[] : List.of(widget.photo.found ?? const <PlateBox>[]);
      _selected = _boxes.isEmpty ? null : 0;
      _touched = false;
    });
    _zoomer.value = Matrix4.identity();
  }

  Future<void> _done() async {
    setState(() => _applying = true);
    final hider = ref.read(plateHiderProvider);
    final p = widget.photo;
    final ok = _showingOriginal
        ? await hider.showOriginal(p, _boxes)
        : p.restored
            ? await hider.keepBlurred(p, _boxes)
            : await hider.applyBoxes(p, _boxes);
    if (!mounted) return;
    if (!ok) {
      setState(() => _applying = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Couldn\'t blur this photo. Try again.')));
      return;
    }
    Navigator.of(context).pop(true);
  }

  // ── layout ──

  String get _hint {
    final p = widget.photo;
    if (_showingOriginal && _boxes.isEmpty) {
      return 'Your original photo, plate showing. Done puts it back without the blur when you save. Tap the plate to blur it again.';
    }
    if (_boxes.isEmpty && !_showingOriginal && (p.savedBlurred || p.restored)) {
      if (p.originalLost) return 'The original of this photo isn\'t kept (blurred before 2 Oct). If anything still shows, tap it to blur it.';
      return 'This photo went up blurred. Show original takes the blur off. If anything still shows, tap it to blur it.';
    }
    if (_boxes.isEmpty) return 'No blur on this photo. Tap the plate to blur it.';
    if (widget.photo.guessed && !_touched) return 'I couldn\'t look for the plate, so this blur is a guess. Drag it onto the plate.';
    return 'Drag the blur onto the plate. Pinch it or pull a corner to resize. Tap the photo to move it there.';
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_loading && !_loadFailed;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(AppIcons.x, color: Colors.white),
                      onPressed: _applying || _switching ? null : () => Navigator.of(context).pop(false),
                    ),
                    const Expanded(
                      child: Text(
                        'Check the plate',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: ready && !_applying && !_switching ? _reset : null,
                      style: TextButton.styleFrom(foregroundColor: Colors.white, disabledForegroundColor: Colors.white38),
                      child: const Text('Reset', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              Expanded(child: _canvasArea(ready)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (ready) ...[
                      Text(_hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
                      const SizedBox(height: 12),
                      if (_hasOriginal) ...[
                        _ToolButton(
                          icon: _showingOriginal ? AppIcons.eyeSlash : AppIcons.eye,
                          label: _showingOriginal ? 'Keep blurred' : 'Show original',
                          loading: _switching,
                          onTap: !_applying && !_switching ? _toggleOriginal : null,
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: _ToolButton(
                              icon: AppIcons.plus,
                              label: _boxes.isEmpty ? 'Add a blur' : 'Add another blur',
                              onTap: !_applying && _boxes.length < kMaxPlateBoxes ? _add : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ToolButton(
                              icon: AppIcons.trash,
                              label: 'Remove blur',
                              onTap: !_applying && _selected != null ? _remove : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    PrimaryButton(label: 'Done', loading: _applying, onPressed: ready && !_switching ? _done : null),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _canvasArea(bool ready) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
            SizedBox(height: 14),
            Text('Looking for the plate…', style: TextStyle(color: Colors.white70, fontSize: 13.5)),
          ],
        ),
      );
    }
    if (!ready) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.warning, color: Colors.white70, size: 30),
              const SizedBox(height: 12),
              const Text(
                'Couldn\'t load this photo. Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.35),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _load,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (_, c) {
        _area = c.biggest;
        // The photo at its own shape, as big as fits with a little air for
        // the corner handles.
        final maxW = math.max(1.0, c.maxWidth - 24), maxH = math.max(1.0, c.maxHeight - 24);
        final w = math.min(maxW, maxH * _aspect);
        _shown = Size(w, w / _aspect);
        return InteractiveViewer(
          transformationController: _zoomer,
          minScale: 1,
          maxScale: 6,
          clipBehavior: Clip.hardEdge,
          child: Center(child: SizedBox.fromSize(size: _shown, child: _canvas())),
        );
      },
    );
  }

  Widget _canvas() {
    final image = _image!;
    final w = _shown.width, h = _shown.height;
    final z = _zoom <= 0 ? 1.0 : _zoom;
    // The blur as it will go up: same strength relative to the photo.
    final outW = _px.$1 * math.min(1.0, 1280 / math.max(_px.$1, _px.$2));
    final minSigma = 10 * w / math.max(1.0, outW);
    Rect rectOf(PlateBox b) => Rect.fromLTRB(b.x0 * w, b.y0 * h, b.x1 * w, b.y1 * h);
    final order = [for (var i = 0; i < _boxes.length; i++) if (i != _selected) i, ?_selected];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTapUp: _applying ? null : _tapPhoto,
            child: Image(image: image, fit: BoxFit.fill, gaplessPlayback: true),
          ),
        ),
        // Live blur, exactly where each box is.
        for (final b in _boxes)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                clipper: _RectClip(rectOf(b)),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: plateBlurSigma(rectOf(b).height, min: minSigma),
                    sigmaY: plateBlurSigma(rectOf(b).height, min: minSigma),
                    tileMode: TileMode.clamp,
                  ),
                  child: Image(image: image, fit: BoxFit.fill, gaplessPlayback: true),
                ),
              ),
            ),
          ),
        // The frames; the selected one on top with its corner handles.
        for (final i in order) _frame(i, rectOf(_boxes[i]), z),
        if (_selected != null && _selected! < _boxes.length)
          for (final c in PlateCorner.values) _handle(c, rectOf(_boxes[_selected!]), z),
      ],
    );
  }

  Widget _frame(int i, Rect r, double z) {
    // A small box still gets a finger-sized grab area.
    final minHit = 44 / z;
    final padX = math.max(0.0, (minHit - r.width) / 2), padY = math.max(0.0, (minHit - r.height) / 2);
    final selected = i == _selected;
    return Positioned(
      left: r.left - padX,
      top: r.top - padY,
      width: r.width + padX * 2,
      height: r.height + padY * 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _applying ? null : () => _select(i),
        onScaleStart: _applying ? null : (d) => _boxStart(i, d),
        onScaleUpdate: _applying ? null : (d) => _boxUpdate(i, d),
        onScaleEnd: (_) => _dragEnd(),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padX, vertical: padY),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4 / z),
              border: Border.all(color: selected ? Colors.white : Colors.white.withValues(alpha: 0.7), width: (selected ? 2 : 1.4) / z),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 3 / z)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _handle(PlateCorner c, Rect r, double z) {
    final hit = 40 / z, dot = 16 / z;
    final at = switch (c) {
      PlateCorner.topLeft => r.topLeft,
      PlateCorner.topRight => r.topRight,
      PlateCorner.bottomLeft => r.bottomLeft,
      PlateCorner.bottomRight => r.bottomRight,
    };
    return Positioned(
      left: at.dx - hit / 2,
      top: at.dy - hit / 2,
      width: hit,
      height: hit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _applying ? null : _cornerStart,
        onPanUpdate: _applying ? null : (d) => _cornerUpdate(c, d),
        onPanEnd: (_) => _dragEnd(),
        child: Center(
          child: Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brand, width: 2.5 / z),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 3 / z)],
            ),
          ),
        ),
      ),
    );
  }
}

class _RectClip extends CustomClipper<Rect> {
  const _RectClip(this.rect);
  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_RectClip old) => old.rect != rect;
}

/// Add another blur / Remove blur: light on the black editor.
class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap, this.loading = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null || loading;
    return Opacity(
      opacity: on ? 1 : 0.4,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            // Scales down rather than truncating at large text sizes.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  else
                    Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(label, maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
