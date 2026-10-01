import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/car.dart';
import 'collector_card.dart';
import 'garage_pager.dart';

/// Concept C, "collector cards": every car as a silver-framed card in a
/// cover-flow deck. The side cards turn away in 3D; a band of light slides
/// over the front card with the finger, or with the phone's tilt when nobody
/// touches it. The cards deal in when the deck opens.
class GarageCardDeck extends StatefulWidget {
  const GarageCardDeck({
    super.key,
    required this.cars,
    required this.index,
    required this.onIndex,
    required this.height,
    required this.onOpen,
    this.todayId,
    this.onLongPress,
    this.onAdd,
  });

  final List<Car> cars;
  final int index;
  final ValueChanged<int> onIndex;
  final double height;
  final ValueChanged<Car> onOpen;
  final String? todayId;
  final ValueChanged<Car>? onLongPress;
  /// Adds a "Park another car" card at the end (owner only).
  final VoidCallback? onAdd;

  @override
  State<GarageCardDeck> createState() => _GarageCardDeckState();
}

class _GarageCardDeckState extends State<GarageCardDeck> with TickerProviderStateMixin {
  late final GaragePager _pager = GaragePager(vsync: this, index: widget.index);
  late final AnimationController _deal;
  final _sheen = ValueNotifier<double>(0.5);
  final _tilt = TiltTracker(smoothing: 0.1);
  StreamSubscription<Offset>? _tiltSub;
  late final AppLifecycleListener _life;
  bool _touching = false;
  bool _active = false;
  bool _dragged = false;

  static const _dealMs = 700;
  static const _stagger = 120;

  int get _count => widget.cars.length + (widget.onAdd != null ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _pager.count = math.max(1, _count);
    final dealt = math.min(_count, 5);
    _deal = AnimationController(vsync: this, duration: Duration(milliseconds: _dealMs + _stagger * math.max(0, dealt - 1)))..forward();
    _life = AppLifecycleListener(onResume: _syncTilt, onPause: _stopTilt);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTilt();
  }

  @override
  void didUpdateWidget(GarageCardDeck old) {
    super.didUpdateWidget(old);
    _pager.count = math.max(1, _count);
    final want = widget.index.clamp(0, _pager.count - 1);
    if (want != _pager.target) _pager.animateTo(want);
  }

  @override
  void dispose() {
    _life.dispose();
    _stopTilt();
    _tilt.dispose();
    _sheen.dispose();
    _deal.dispose();
    _pager.dispose();
    super.dispose();
  }

  /// Tilt only while this page is on screen (a pushed page turns tickers off).
  void _syncTilt() {
    final on = TickerMode.valuesOf(context).enabled;
    if (on == _active && (!on || _tiltSub != null)) return;
    _active = on;
    if (on) {
      _tilt.start();
      _tiltSub ??= _tilt.stream.listen((o) {
        if (_touching) return;
        final v = (0.5 + o.dx * 0.45).clamp(0.0, 1.0);
        if ((v - _sheen.value).abs() > 0.004) _sheen.value = v;
      });
    } else {
      _stopTilt();
    }
  }

  void _stopTilt() {
    _tiltSub?.cancel();
    _tiltSub = null;
    _tilt.stop();
    _active = false;
  }

  void _go(int page) {
    final p = page.clamp(0, _pager.count - 1);
    if (p == widget.index) return;
    _pager.animateTo(p);
    garageSwipeHaptic();
    widget.onIndex(p);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.4),
              radius: 1.05,
              colors: [GarageColors.deckCenter, GarageColors.deckEdge],
              stops: [0, 0.75],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final h = widget.height;
              final cardW = math.min(252.0, math.min(w * 0.6, (h - 44) * kCollectorAspect));
              final cardH = cardW / kCollectorAspect;
              final top = math.max(12.0, (h - cardH) / 2 - 6);
              final cards = [
                for (var i = 0; i < widget.cars.length; i++)
                  CollectorCard(
                    key: ValueKey(widget.cars[i].id),
                    car: widget.cars[i],
                    index: i,
                    width: cardW,
                    today: widget.cars[i].id == widget.todayId,
                    sheen: _sheen,
                  ),
                if (widget.onAdd != null) _AddCard(key: const ValueKey('add'), width: cardW),
              ];
              return Listener(
                onPointerDown: (e) {
                  _touching = true;
                  _sheen.value = (e.localPosition.dx / w).clamp(0.0, 1.0);
                },
                onPointerMove: (e) => _sheen.value = (e.localPosition.dx / w).clamp(0.0, 1.0),
                onPointerUp: (_) => _touching = false,
                onPointerCancel: (_) => _touching = false,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    _dragged = true;
                    _pager.dragStart();
                  },
                  onHorizontalDragUpdate: (d) => _pager.dragUpdate(-(d.primaryDelta ?? 0) / (cardW * 0.8)),
                  onHorizontalDragEnd: (d) {
                    _dragged = false;
                    final target = _pager.dragEnd(-(d.primaryVelocity ?? 0) / (cardW * 0.8));
                    if (target != widget.index) {
                      garageSwipeHaptic();
                      widget.onIndex(target);
                    }
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedBuilder(
                        animation: Listenable.merge([_pager.position, _deal]),
                        builder: (_, _) {
                          final pos = _pager.position.value;
                          final order = [for (var i = 0; i < cards.length; i++) if ((i - pos).abs() < 2.3) i]
                            ..sort((a, b) => (b - pos).abs().compareTo((a - pos).abs()));
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (final i in order) _placed(i, cards[i], i - pos, cardW, cardH, top, w),
                            ],
                          );
                        },
                      ),
                      if (_count > 1) ...[
                        _arrow(left: true, top: top + cardH / 2 - 22),
                        _arrow(left: false, top: top + cardH / 2 - 22),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _placed(int i, Widget card, double d, double cardW, double cardH, double top, double w) {
    final a = d.abs();
    final s = d.sign;
    // Rest pose for this distance from the front.
    double tx, ty, scale, rot, opacity;
    if (a <= 1) {
      tx = d * cardW * 0.7;
      ty = 18 * a;
      scale = 1 - 0.18 * a;
      rot = -d * 0.52;
      opacity = 1 - 0.25 * a;
    } else {
      final e = a - 1;
      tx = s * (cardW * 0.7 + e * cardW * 0.45);
      ty = 18 + 12 * e;
      scale = 0.82 - 0.12 * e;
      rot = -s * 0.52;
      opacity = (0.75 * (1.3 - e) / 1.3).clamp(0.0, 1.0);
    }
    // Dealt in one after another: from below, turned, smaller, faded.
    final dealN = math.min(_count, 5);
    final totalMs = _dealMs + _stagger * math.max(0, dealN - 1);
    final startMs = _stagger * math.min(i, dealN - 1);
    final dt = const Cubic(0.3, 0.7, 0.2, 1).transform(((_deal.value * totalMs - startMs) / _dealMs).clamp(0.0, 1.0));
    final spin = (i.isOdd ? 7 : -7) * math.pi / 180 * (1 - dt);
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0011)
      ..translateByDouble(tx, ty + 90 * (1 - dt), 0, 1)
      ..rotateZ(spin)
      ..rotateY(rot)
      ..scaleByDouble(scale * (0.86 + 0.14 * dt), scale * (0.86 + 0.14 * dt), 1, 1);
    final front = a < 0.5;
    return Positioned(
      left: (w - cardW) / 2,
      top: top,
      width: cardW,
      height: cardH,
      child: Opacity(
        opacity: (opacity * dt).clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: m,
          child: front
              ? _FrontTilt(sheen: _sheen, child: GestureDetector(onTap: () => _tapFront(i), onLongPress: () => _longPress(i), child: card))
              : GestureDetector(onTap: () => _go(i), child: card),
        ),
      ),
    );
  }

  void _tapFront(int i) {
    if (_dragged) return;
    if (i >= widget.cars.length) {
      widget.onAdd?.call();
    } else {
      widget.onOpen(widget.cars[i]);
    }
  }

  void _longPress(int i) {
    if (i < widget.cars.length) widget.onLongPress?.call(widget.cars[i]);
  }

  Widget _arrow({required bool left, required double top}) {
    return Positioned(
      left: left ? 6 : null,
      right: left ? null : 6,
      top: top,
      child: AnimatedBuilder(
        animation: _pager.position,
        builder: (_, _) {
          final page = _pager.page;
          final enabled = left ? page > 0 : page < _count - 1;
          return Opacity(
            opacity: enabled ? 1 : 0.35,
            child: Semantics(
              button: true,
              label: left ? 'Previous car' : 'Next car',
              child: GestureDetector(
                onTap: enabled ? () => _go(page + (left ? -1 : 1)) : null,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0x990A0B0E),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: Icon(left ? AppIcons.caretLeft : AppIcons.caretRight, size: 18, color: GarageColors.text),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The front card leans a few degrees towards the light.
class _FrontTilt extends StatelessWidget {
  const _FrontTilt({required this.sheen, required this.child});
  final ValueListenable<double> sheen;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: sheen,
        child: child,
        builder: (_, p, child) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0011)
            ..rotateY((p - 0.5) * 0.14),
          child: child,
        ),
      );
}

/// The owner's last card: an empty silver frame to park another car.
class _AddCard extends StatelessWidget {
  const _AddCard({super.key, required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    final s = width / 252;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Container(
        width: width,
        height: width / kCollectorAspect,
        padding: EdgeInsets.all(8 * s),
        decoration: BoxDecoration(gradient: GarageColors.silver, borderRadius: BorderRadius.circular(22 * s)),
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFF15171C), borderRadius: BorderRadius.circular(15 * s)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56 * s,
                height: 56 * s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                ),
                child: Icon(AppIcons.plus, color: GarageColors.text, size: 24 * s),
              ),
              SizedBox(height: 12 * s),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12 * s),
                child: Text(
                  'PARK ANOTHER CAR',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: AppFonts.display, fontSize: 22 * s, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.white.withValues(alpha: 0.85)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
