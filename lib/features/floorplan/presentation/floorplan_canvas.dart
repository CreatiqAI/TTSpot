import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/floorplan.dart';

/// One level's plan image with its pins, zoomable. Pins sit at fractions of
/// the image (0–1) and shrink back as you zoom in so they never cover the plan.
///
/// Used by the member viewer (tap a pin, tap to drop "I'm here") and by the
/// organizer editor (tap to add, hold a pin and drag to move).
class FloorplanCanvas extends StatefulWidget {
  const FloorplanCanvas({
    super.key,
    required this.level,
    this.pinVisible,
    this.onPinTap,
    this.onTapPlan,
    this.onPinMoved,
    this.youAreHere,
    this.youLabel = 'You',
    this.selectedPinId,
    this.padding = EdgeInsets.zero,
  });

  final FloorLevel level;
  final bool Function(FloorPin pin)? pinVisible;
  final void Function(FloorPin pin)? onPinTap;

  /// Tap on the plan (not on a pin), as a fraction of the image.
  final void Function(Offset frac)? onTapPlan;

  /// Editor: a pin was held and dragged to a new fraction.
  final void Function(FloorPin pin, Offset frac)? onPinMoved;

  /// My marker, as a fraction of the image.
  final Offset? youAreHere;
  final String youLabel;
  final String? selectedPinId;

  /// Room kept clear around the plan (e.g. for the level switcher).
  final EdgeInsets padding;

  @override
  State<FloorplanCanvas> createState() => _FloorplanCanvasState();
}

class _FloorplanCanvasState extends State<FloorplanCanvas> {
  final _tc = TransformationController();
  final _planKey = GlobalKey();
  String? _dragId;
  Offset? _dragFrac;

  @override
  void didUpdateWidget(covariant FloorplanCanvas old) {
    super.didUpdateWidget(old);
    if (old.level.id != widget.level.id) _tc.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Offset? _fracFromGlobal(Offset global) {
    final box = _planKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(global);
    return Offset((local.dx / box.size.width).clamp(0.0, 1.0), (local.dy / box.size.height).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    return LayoutBuilder(builder: (context, c) {
      final availW = math.max(1.0, c.maxWidth - widget.padding.horizontal);
      final availH = math.max(1.0, c.maxHeight - widget.padding.vertical);
      final aspect = level.aspect;
      var w = availW;
      var h = w / aspect;
      if (h > availH) {
        h = availH;
        w = h * aspect;
      }
      return InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 6,
        boundaryMargin: const EdgeInsets.all(120),
        child: SizedBox(
          width: c.maxWidth,
          height: c.maxHeight,
          child: Padding(
            padding: widget.padding,
            child: Center(
              child: SizedBox(
                width: w,
                height: h,
                child: ValueListenableBuilder<Matrix4>(
                  valueListenable: _tc,
                  builder: (context, m, _) {
                    final s = m.getMaxScaleOnAxis();
                    // Pins grow a little with zoom (s^0.3) instead of 1:1.
                    final k = math.pow(s, -0.7).toDouble();
                    final showAllLabels = s >= 1.8;
                    final pins = level.pins.where((p) => widget.pinVisible?.call(p) ?? true).toList();
                    return Stack(
                      key: _planKey,
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: widget.onTapPlan == null ? null : (d) => widget.onTapPlan!(Offset((d.localPosition.dx / w).clamp(0.0, 1.0), (d.localPosition.dy / h).clamp(0.0, 1.0))),
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border)),
                              child: level.hasImage
                                  ? CachedNetworkImage(
                                      imageUrl: level.imageUrl!,
                                      fit: BoxFit.fill,
                                      placeholder: (_, _) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                      errorWidget: (_, _, _) => Center(child: Icon(AppIcons.imageBroken, color: AppColors.textMuted, size: 32)),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ),
                        for (final p in pins) _positioned(p, w, h, k, showAllLabels || p.kind.alwaysLabelled),
                        if (widget.youAreHere != null)
                          Positioned(
                            left: widget.youAreHere!.dx * w - 40,
                            top: widget.youAreHere!.dy * h - 40,
                            child: IgnorePointer(child: Transform.scale(scale: k, child: YouAreHereMarker(label: widget.youLabel))),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _positioned(FloorPin p, double w, double h, double k, bool showLabel) {
    final dragging = _dragId == p.id && _dragFrac != null;
    final fx = dragging ? _dragFrac!.dx : p.x;
    final fy = dragging ? _dragFrac!.dy : p.y;
    const box = PinBadge.box;
    return Positioned(
      left: fx * w - box / 2,
      top: fy * h - box / 2,
      child: Transform.scale(
        scale: dragging ? k * 1.25 : k,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPinTap == null ? null : () => widget.onPinTap!(p),
          onLongPressStart: widget.onPinMoved == null
              ? null
              : (d) {
                  HapticFeedback.mediumImpact();
                  setState(() {
                    _dragId = p.id;
                    _dragFrac = Offset(p.x, p.y);
                  });
                },
          onLongPressMoveUpdate: widget.onPinMoved == null
              ? null
              : (d) {
                  final f = _fracFromGlobal(d.globalPosition);
                  if (f != null) setState(() => _dragFrac = f);
                },
          onLongPressEnd: widget.onPinMoved == null
              ? null
              : (d) {
                  final f = _dragFrac;
                  setState(() {
                    _dragId = null;
                    _dragFrac = null;
                  });
                  if (f != null) widget.onPinMoved!(p, f);
                },
          child: PinBadge(pin: p, showLabel: showLabel || dragging, selected: widget.selectedPinId == p.id || dragging),
        ),
      ),
    );
  }
}

/// A round kind-coloured icon with its label floating above.
class PinBadge extends StatelessWidget {
  const PinBadge({super.key, required this.pin, this.showLabel = true, this.selected = false});
  final FloorPin pin;
  final bool showLabel;
  final bool selected;

  /// Hit box; the visible circle is smaller and centred in it.
  static const box = 44.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: pin.kind.color,
              shape: BoxShape.circle,
              border: Border.all(color: selected ? AppColors.ink : Colors.white, width: selected ? 3 : 2),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Icon(pin.kind.icon, size: 16, color: Colors.white),
          ),
          if (showLabel)
            Positioned(
              bottom: box - 4,
              left: -70,
              right: -70,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: pin.kind.color.withValues(alpha: 0.5)),
                    boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4)],
                  ),
                  child: Text(
                    pin.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF101010), height: 1.1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pulsing "You are here" dot. 80×80 box, dot in the middle.
class YouAreHereMarker extends StatefulWidget {
  const YouAreHereMarker({super.key, this.label = 'You'});
  final String label;

  @override
  State<YouAreHereMarker> createState() => _YouAreHereMarkerState();
}

class _YouAreHereMarkerState extends State<YouAreHereMarker> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Container(
              width: 22 + 50 * _c.value,
              height: 22 + 50 * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.brand.withValues(alpha: 0.35 * (1 - _c.value))),
            ),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.brand,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6)],
            ),
          ),
          Positioned(
            top: 58,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(999)),
              child: Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
