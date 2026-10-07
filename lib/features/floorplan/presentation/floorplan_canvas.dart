import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/floorplan.dart';

/// TT Spot partner gold (logo rings on the plan).
const kPlanPartnerGold = Color(0xFFD4A20C);

/// Ask the canvas to zoom to [rect] (image fractions). A new [token] = a new
/// request, so the same rect can be focused again.
@immutable
class FloorplanFocus {
  const FloorplanFocus(this.rect, this.token);
  final Rect rect;
  final int token;
}

/// One level's plan image with its pins, zoomable. Pins sit at fractions of
/// the image (0–1) and shrink back as you zoom in so they never cover the plan.
///
/// Booth pins with a size (w/h) are drawn as boxes at their real size, all in
/// one painter so 200+ booths stay smooth. Partner booths get a big round
/// logo with a gold ring.
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
    this.highlightPinIds = const {},
    this.partnerLogos = const {},
    this.focus,
  });

  final FloorLevel level;
  final bool Function(FloorPin pin)? pinVisible;
  final void Function(FloorPin pin)? onPinTap;

  /// Tap on the plan (not on a pin or booth box), as a fraction of the image.
  final void Function(Offset frac)? onTapPlan;

  /// Editor: a pin was held and dragged to a new fraction.
  final void Function(FloorPin pin, Offset frac)? onPinMoved;

  /// My marker, as a fraction of the image.
  final Offset? youAreHere;
  final String youLabel;
  final String? selectedPinId;

  /// Room kept clear around the plan (e.g. for the level switcher).
  final EdgeInsets padding;

  /// Pins drawn with a pulsing outline (an exhibitor's booths).
  final Set<String> highlightPinIds;

  /// Partner booths: pin id -> logo URL (null = partner without a logo).
  final Map<String, String?> partnerLogos;

  /// Zoom to this rect when the token changes.
  final FloorplanFocus? focus;

  @override
  State<FloorplanCanvas> createState() => _FloorplanCanvasState();
}

class _FloorplanCanvasState extends State<FloorplanCanvas> with TickerProviderStateMixin {
  final _tc = TransformationController();
  final _planKey = GlobalKey();
  final _labels = BoothLabelCache();
  late final AnimationController _zoom = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  Animation<Matrix4>? _zoomTween;

  String? _dragId;
  Offset? _dragFrac;
  Offset _dragGrab = Offset.zero;

  // Last layout, for focusing.
  Size _viewport = Size.zero;
  Offset _planOrigin = Offset.zero;
  Size _planSize = Size.zero;
  int? _focusedToken;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      final t = _zoomTween;
      if (t != null) _tc.value = t.value;
    });
    _syncPulse();
    if (widget.focus != null) _scheduleFocus();
  }

  @override
  void didUpdateWidget(covariant FloorplanCanvas old) {
    super.didUpdateWidget(old);
    if (old.level.id != widget.level.id) {
      _zoom.stop();
      _tc.value = Matrix4.identity();
    }
    if (widget.focus != null && widget.focus!.token != _focusedToken) _scheduleFocus();
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.highlightPinIds.isEmpty) {
      if (_pulse.isAnimating) _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  void _scheduleFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final f = widget.focus;
      if (f == null || f.token == _focusedToken || _planSize.isEmpty) return;
      _focusedToken = f.token;
      _animateTo(focusMatrix(rect: f.rect, viewport: _viewport, padding: widget.padding, planOrigin: _planOrigin, planSize: _planSize));
    });
  }

  void _animateTo(Matrix4 target) {
    _zoomTween = Matrix4Tween(begin: _tc.value.clone(), end: target).animate(CurvedAnimation(parent: _zoom, curve: Curves.easeOutCubic));
    _zoom.forward(from: 0);
  }

  @override
  void dispose() {
    _zoom.dispose();
    _pulse.dispose();
    _tc.dispose();
    _labels.dispose();
    super.dispose();
  }

  Offset? _fracFromGlobal(Offset global) {
    final box = _planKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(global);
    return Offset((local.dx / box.size.width).clamp(0.0, 1.0), (local.dy / box.size.height).clamp(0.0, 1.0));
  }

  /// The top booth box under [frac], with a finger-sized minimum hit area.
  FloorPin? _boxAt(List<FloorPin> boxes, Offset frac, double w, double h, double s) {
    // A box actually under the finger wins; otherwise the nearest centre
    // within a finger-sized area (small booths overlap at low zoom).
    for (var i = boxes.length - 1; i >= 0; i--) {
      final b = boxes[i];
      if (Rect.fromCenter(center: Offset(b.x, b.y), width: b.w!, height: b.h!).contains(frac)) return b;
    }
    final minW = 28 / (s * w);
    final minH = 28 / (s * h);
    FloorPin? best;
    var bestD = double.infinity;
    for (final b in boxes) {
      final r = Rect.fromCenter(center: Offset(b.x, b.y), width: math.max(b.w!, minW), height: math.max(b.h!, minH));
      if (!r.contains(frac)) continue;
      final d = (Offset(b.x * w, b.y * h) - Offset(frac.dx * w, frac.dy * h)).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = b;
      }
    }
    return best;
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
      _viewport = Size(c.maxWidth, c.maxHeight);
      _planSize = Size(w, h);
      _planOrigin = Offset(widget.padding.left + (availW - w) / 2, widget.padding.top + (availH - h) / 2);
      final onPinTap = widget.onPinTap;
      final onTapPlan = widget.onTapPlan;
      final onPinMoved = widget.onPinMoved;
      final pinVisible = widget.pinVisible;
      final visible = pinVisible == null ? level.pins : level.pins.where(pinVisible).toList();
      final boxes = [for (final p in visible) if (p.isBox) p];
      final logos = [for (final p in visible) if (widget.partnerLogos.containsKey(p.id)) p];
      final badges = [for (final p in visible) if (!p.isBox && !widget.partnerLogos.containsKey(p.id)) p];
      final highlighted = [for (final p in level.pins) if (widget.highlightPinIds.contains(p.id)) p];

      return InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 8,
        boundaryMargin: const EdgeInsets.all(120),
        onInteractionStart: (_) => _zoom.stop(),
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
                    final dragging = _dragId;
                    final dragFrac = _dragFrac;
                    return Stack(
                      key: _planKey,
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: onTapPlan == null && (onPinTap == null || boxes.isEmpty)
                                ? null
                                : (d) {
                                    final f = Offset((d.localPosition.dx / w).clamp(0.0, 1.0), (d.localPosition.dy / h).clamp(0.0, 1.0));
                                    final tap = widget.onPinTap;
                                    final hit = tap == null ? null : _boxAt(boxes, f, w, h, s);
                                    if (tap != null && hit != null) {
                                      tap(hit);
                                      return;
                                    }
                                    widget.onTapPlan?.call(f);
                                  },
                            onLongPressStart: onPinMoved == null || boxes.isEmpty
                                ? null
                                : (d) {
                                    final f = Offset(d.localPosition.dx / w, d.localPosition.dy / h);
                                    final hit = _boxAt(boxes, f, w, h, s);
                                    if (hit == null) return;
                                    HapticFeedback.mediumImpact();
                                    setState(() {
                                      _dragId = hit.id;
                                      _dragGrab = f - Offset(hit.x, hit.y);
                                      _dragFrac = Offset(hit.x, hit.y);
                                    });
                                  },
                            onLongPressMoveUpdate: onPinMoved == null || boxes.isEmpty
                                ? null
                                : (d) {
                                    if (_dragId == null) return;
                                    final f = Offset(d.localPosition.dx / w, d.localPosition.dy / h) - _dragGrab;
                                    setState(() => _dragFrac = Offset(f.dx.clamp(0.0, 1.0), f.dy.clamp(0.0, 1.0)));
                                  },
                            onLongPressEnd: onPinMoved == null || boxes.isEmpty
                                ? null
                                : (d) {
                                    final id = _dragId;
                                    final f = _dragFrac;
                                    setState(() {
                                      _dragId = null;
                                      _dragFrac = null;
                                    });
                                    if (id == null || f == null) return;
                                    final p = boxes.where((b) => b.id == id).firstOrNull;
                                    if (p != null) widget.onPinMoved?.call(p, f);
                                  },
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
                        if (boxes.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: BoothBoxPainter(
                                    boxes: boxes,
                                    scale: s,
                                    partnerIds: widget.partnerLogos.keys.toSet(),
                                    selectedId: widget.selectedPinId,
                                    dragId: dragging,
                                    dragFrac: dragFrac,
                                    labels: _labels,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (highlighted.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(painter: _HighlightPainter(pins: highlighted, scale: s, pulse: _pulse)),
                            ),
                          ),
                        for (final p in badges) _positioned(p, w, h, k, showAllLabels || p.kind.alwaysLabelled),
                        for (final p in logos) _logo(p, w, h, k, dragging == p.id ? dragFrac : null),
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

  /// A partner's round logo, standing on top of its booth (or on the pin).
  Widget _logo(FloorPin p, double w, double h, double k, Offset? drag) {
    final fx = drag?.dx ?? p.x;
    final fy = drag?.dy ?? p.y;
    final ax = fx * w;
    final ay = p.isBox ? (fy - p.h! / 2) * h : fy * h;
    return Positioned(
      left: ax - PartnerLogoMarker.width / 2,
      top: ay - PartnerLogoMarker.height,
      child: Transform.scale(
        scale: k,
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPinTap == null ? null : () => widget.onPinTap!(p),
          // While booths are highlighted, other partners fade so they don't cover them.
          child: Opacity(
            opacity: widget.highlightPinIds.isEmpty || widget.highlightPinIds.contains(p.id) ? 1 : 0.3,
            child: PartnerLogoMarker(url: widget.partnerLogos[p.id], selected: widget.selectedPinId == p.id),
          ),
        ),
      ),
    );
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
                    _dragGrab = Offset.zero;
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

/// The InteractiveViewer matrix that centres [rect] (image fractions) in the
/// padded viewport, zoomed so it fills about 60% of it (1x to 6x).
Matrix4 focusMatrix({required Rect rect, required Size viewport, required EdgeInsets padding, required Offset planOrigin, required Size planSize}) {
  final r = Rect.fromLTWH(planOrigin.dx + rect.left * planSize.width, planOrigin.dy + rect.top * planSize.height, rect.width * planSize.width, rect.height * planSize.height);
  final rw = math.max(r.width, 40.0);
  final rh = math.max(r.height, 40.0);
  final availW = math.max(1.0, viewport.width - padding.horizontal);
  final availH = math.max(1.0, viewport.height - padding.vertical);
  final s = math.min(availW / (rw * 1.7), availH / (rh * 1.7)).clamp(1.0, 6.0).toDouble();
  final centre = Offset(padding.left + availW / 2, padding.top + availH / 2);
  final t = centre - r.center * s;
  return Matrix4.translationValues(t.dx, t.dy, 0)..multiply(Matrix4.diagonal3Values(s, s, 1));
}

/// Booth codes laid out once and reused every frame.
class BoothLabelCache {
  final _cache = <String, TextPainter>{};

  TextPainter of(String text) => _cache.putIfAbsent(text, () {
        final tp = TextPainter(
          text: TextSpan(text: text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF101010), height: 1)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        return tp;
      });

  void dispose() {
    for (final tp in _cache.values) {
      tp.dispose();
    }
    _cache.clear();
  }
}

/// Every booth box on a level in one pass. Lives in plan space (it zooms
/// with the plan); strokes and labels are divided by [scale] so they stay
/// the same size on screen.
class BoothBoxPainter extends CustomPainter {
  BoothBoxPainter({
    required this.boxes,
    required this.scale,
    required this.partnerIds,
    required this.labels,
    this.selectedId,
    this.dragId,
    this.dragFrac,
  });

  final List<FloorPin> boxes;
  final double scale;
  final Set<String> partnerIds;
  final BoothLabelCache labels;
  final String? selectedId;
  final String? dragId;
  final Offset? dragFrac;

  static const linkedFill = Color(0x478B3FD9); // booth purple, 28%
  static const linkedStroke = Color(0xCC8B3FD9);
  static const plainFill = Color(0x33FFFFFF);
  static const plainStroke = Color(0x998B3FD9);
  static const partnerFill = Color(0x59D4A20C);
  static const partnerStroke = Color(0xFFD4A20C);

  /// Booths narrower than this on screen hide their code.
  static const minLabelWidth = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scale <= 0 ? 1.0 : scale;
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / s;
    final strong = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF101010)
      ..strokeWidth = 2.5 / s;
    final drag = dragId;
    final dragAt = dragFrac;
    final selected = selectedId;
    for (final b in boxes) {
      final moving = drag != null && dragAt != null && b.id == drag;
      final cx = (moving ? dragAt.dx : b.x) * size.width;
      final cy = (moving ? dragAt.dy : b.y) * size.height;
      final bw = b.w! * size.width;
      final bh = b.h! * size.height;
      final rect = Rect.fromCenter(center: Offset(cx, cy), width: bw, height: bh);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(math.min(bw, bh) * 0.18));
      final partner = partnerIds.contains(b.id);
      final linked = b.exhibitorId != null;
      fill.color = partner ? partnerFill : (linked ? linkedFill : plainFill);
      stroke.color = partner ? partnerStroke : (linked ? linkedStroke : plainStroke);
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);
      if (moving || b.id == selected) canvas.drawRRect(rr, strong);

      // Booth code once the box is big enough on screen.
      final screenW = bw * s;
      final screenH = bh * s;
      final code = b.label.trim();
      if (code.isEmpty || screenW < minLabelWidth || screenH < 9) continue;
      final tp = labels.of(code);
      final fit = math.min(1.0, math.min((screenW - 3) / tp.width, (screenH - 2) / tp.height));
      if (fit < 0.55) continue;
      final k = fit / s;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(k, k);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant BoothBoxPainter old) =>
      old.scale != scale ||
      !identical(old.boxes, boxes) && !_sameBoxes(old.boxes, boxes) ||
      old.selectedId != selectedId ||
      old.dragId != dragId ||
      old.dragFrac != dragFrac ||
      old.partnerIds.length != partnerIds.length ||
      !old.partnerIds.containsAll(partnerIds);

  static bool _sameBoxes(List<FloorPin> a, List<FloorPin> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}

/// Pulsing outline around highlighted booths (and rings around plain pins).
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({required this.pins, required this.scale, required this.pulse}) : super(repaint: pulse);
  final List<FloorPin> pins;
  final double scale;
  final Animation<double> pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scale <= 0 ? 1.0 : scale;
    final t = pulse.value;
    final solid = Paint()
      ..style = PaintingStyle.stroke
      ..color = AppColors.brand
      ..strokeWidth = 2.5 / s;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..color = AppColors.brand.withValues(alpha: 0.6 * (1 - t))
      ..strokeWidth = 3 / s;
    final tint = Paint()..color = AppColors.brand.withValues(alpha: 0.18);
    for (final p in pins) {
      final c = Offset(p.x * size.width, p.y * size.height);
      if (p.isBox) {
        final rect = Rect.fromCenter(center: c, width: p.w! * size.width, height: p.h! * size.height);
        final rr = RRect.fromRectAndRadius(rect, Radius.circular(math.min(rect.width, rect.height) * 0.18));
        canvas.drawRRect(rr, tint);
        canvas.drawRRect(rr.inflate(1.5 / s), solid);
        canvas.drawRRect(rr.inflate((3 + 12 * t) / s), glow);
      } else {
        canvas.drawCircle(c, (20 + 16 * t) / s, glow);
        canvas.drawCircle(c, 20 / s, solid);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter old) => old.scale != scale || !identical(old.pins, pins);
}

/// A partner booth's logo: big, round, gold ring, a short stem to the booth.
class PartnerLogoMarker extends StatelessWidget {
  const PartnerLogoMarker({super.key, required this.url, this.selected = false});
  final String? url;
  final bool selected;

  static const width = 52.0;
  static const height = 60.0;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: kPlanPartnerGold.withValues(alpha: 0.18),
      child: const Center(child: Icon(AppIcons.storefront, size: 22, color: Color(0xFF8A6A00))),
    );
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          Container(
            width: width,
            height: width,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: selected ? AppColors.ink : kPlanPartnerGold,
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Container(
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              padding: const EdgeInsets.all(1.5),
              child: ClipOval(
                child: url == null || url!.isEmpty
                    ? fallback
                    : CachedNetworkImage(
                        imageUrl: url!,
                        fit: BoxFit.cover,
                        memCacheWidth: 160,
                        placeholder: (_, _) => fallback,
                        errorWidget: (_, _, _) => fallback,
                      ),
              ),
            ),
          ),
          Container(width: 3, height: height - width, color: selected ? AppColors.ink : kPlanPartnerGold),
        ],
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
