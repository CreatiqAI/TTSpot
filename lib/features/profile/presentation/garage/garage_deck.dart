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

/// Concept C, "collector cards", full screen: every car as a silver-framed
/// card in a cover-flow deck, as big as the room between the top bar and the
/// panel allows. The side cards turn away in 3D; a band of light slides over
/// the front card with the finger, or with the phone's tilt when nobody
/// touches it. The cards deal in when the deck opens.
class GarageCardDeck extends StatefulWidget {
  const GarageCardDeck({
    super.key,
    required this.cars,
    required this.index,
    required this.onIndex,
    required this.onOpen,
    this.insets = EdgeInsets.zero,
    this.lift,
    this.todayId,
    this.onLongPress,
    this.onAdd,
  });

  final List<Car> cars;
  final int index;
  final ValueChanged<int> onIndex;
  final ValueChanged<Car> onOpen;

  /// What floats over the deck: the top bar (top) and the collapsed panel (bottom).
  final EdgeInsets insets;

  /// How far the panel has been pulled up past its collapsed height, in px:
  /// the deck shrinks to stay in view above it.
  final ValueListenable<double>? lift;
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
  static const _noLift = AlwaysStoppedAnimation<double>(0);

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
    final lift = widget.lift ?? _noLift;
    return ClipRect(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.1,
            colors: [GarageColors.deckCenter, GarageColors.deckEdge],
            stops: [0, 0.8],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;
            final k = (c.biggest.shortestSide / 390).clamp(0.82, 1.3);
            final top = widget.insets.top;
            final panelTop = math.max(top + 60, h - widget.insets.bottom);
            final margin = 14 * k;
            // The front card fills the room between the top bar and the
            // panel (the side cards fan out past the edges).
            final cardW = math.max(60.0, math.min(math.min(w * 0.7, 380 * k), (panelTop - top - margin * 2) * kCollectorAspect));
            final cardH = cardW / kCollectorAspect;
            final cardTop = top + (panelTop - top - cardH) / 2;
            final cy = cardTop + cardH / 2;
            // Two of each card: the front one catches the light (sheen),
            // the ones at the sides don't, so a tilt only repaints one card.
            Widget card(int i, {required bool front}) => i < widget.cars.length
                ? CollectorCard(
                    key: ValueKey(widget.cars[i].id),
                    car: widget.cars[i],
                    index: i,
                    width: cardW,
                    today: widget.cars[i].id == widget.todayId,
                    sheen: front ? _sheen : null,
                  )
                : _AddCard(key: const ValueKey('add'), width: cardW);
            final fronts = [for (var i = 0; i < _count; i++) card(i, front: true)];
            final sides = [for (var i = 0; i < _count; i++) card(i, front: false)];
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
                // Pulled up, the panel takes room from the bottom: the deck
                // shrinks into what is left, centred in it.
                child: ValueListenableBuilder<double>(
                  valueListenable: lift,
                  builder: (_, lifted, child) {
                    final up = math.min(lifted, (panelTop - top) * 0.6);
                    final room = panelTop - up - top - margin * 2;
                    final s = (room / cardH).clamp(0.45, 1.0);
                    final cy2 = top + (panelTop - up - top) / 2;
                    final m = Matrix4.translationValues(w / 2, cy2, 0)
                      ..multiply(Matrix4.diagonal3Values(s, s, 1))
                      ..multiply(Matrix4.translationValues(-w / 2, -cy, 0));
                    return Transform(transform: m, child: child);
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      AnimatedBuilder(
                        animation: Listenable.merge([_pager.position, _deal]),
                        builder: (_, _) {
                          final pos = _pager.position.value;
                          final order = [for (var i = 0; i < _count; i++) if ((i - pos).abs() < 2.3) i]
                            ..sort((a, b) => (b - pos).abs().compareTo((a - pos).abs()));
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (final i in order) _placed(i, (i - pos).abs() < 0.5 ? fronts[i] : sides[i], i - pos, cardW, cardH, cardTop, w),
                            ],
                          );
                        },
                      ),
                      if (_count > 1) ...[
                        _arrow(left: true, top: cy - 22, lift: lift),
                        _arrow(left: false, top: cy - 22, lift: lift),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _placed(int i, Widget card, double d, double cardW, double cardH, double top, double w) {
    final a = d.abs();
    final s = d.sign;
    // Rest pose for this distance from the front.
    // Side cards sit back (z, away from the viewer), turned 30 degrees with
    // their outer edge towards the viewer, like a fanned deck.
    double tx, ty, tz, scale, rot, opacity;
    if (a <= 1) {
      tx = d * cardW * 0.7;
      ty = 18 * a;
      tz = 120 * a;
      scale = 1 - 0.18 * a;
      rot = d * 0.52;
      opacity = 1 - 0.25 * a;
    } else {
      final e = a - 1;
      tx = s * (cardW * 0.7 + e * cardW * 0.45);
      ty = 18 + 12 * e;
      tz = 120 + 120 * e;
      scale = 0.82 - 0.12 * e;
      rot = s * 0.52;
      opacity = (0.75 * (1.3 - e) / 1.3).clamp(0.0, 1.0);
    }
    // Dealt in one after another: from below, turned, smaller, faded.
    final dealN = math.min(_count, 5);
    final totalMs = _dealMs + _stagger * math.max(0, dealN - 1);
    final startMs = _stagger * math.min(i, dealN - 1);
    final dt = const Cubic(0.3, 0.7, 0.2, 1).transform(((_deal.value * totalMs - startMs) / _dealMs).clamp(0.0, 1.0));
    final spin = (i.isOdd ? 7 : -7) * math.pi / 180 * (1 - dt);
    final m = Matrix4.identity()
      ..setEntry(3, 2, 1 / 1100)
      ..translateByDouble(tx, ty + 90 * (1 - dt), tz, 1)
      ..rotateZ(spin)
      ..rotateY(rot)
      ..scaleByDouble(scale * (0.86 + 0.14 * dt), scale * (0.86 + 0.14 * dt), 1, 1);
    final front = a < 0.5;
    return Positioned(
      key: ValueKey(i),
      left: (w - cardW) / 2,
      top: top,
      width: cardW,
      height: cardH,
      // The transform goes outside the opacity: hit testing then follows the
      // card to where it's drawn (a box checks taps against its own layout
      // rect before any transform inside it).
      child: Transform(
        alignment: Alignment.center,
        transform: m,
        child: Opacity(
          opacity: (opacity * dt).clamp(0.0, 1.0),
          // Same tree front or side, so a card turning to the front isn't rebuilt.
          child: _FrontTilt(
            sheen: _sheen,
            lean: front ? 1 : 0,
            child: GestureDetector(onTap: front ? () => _tapFront(i) : () => _go(i), onLongPress: front ? () => _longPress(i) : null, child: card),
          ),
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

  Widget _arrow({required bool left, required double top, required ValueListenable<double> lift}) {
    return Positioned(
      left: left ? 6 : null,
      right: left ? null : 6,
      top: top,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pager.position, lift]),
        builder: (_, _) {
          final page = _pager.page;
          final enabled = left ? page > 0 : page < _count - 1;
          // Out of the way once the panel is pulled up (swiping still works).
          final shown = (1 - lift.value / 60).clamp(0.0, 1.0);
          return IgnorePointer(
            ignoring: shown < 0.5,
            child: Opacity(
            opacity: (enabled ? 1 : 0.35) * shown,
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
            ),
          );
        },
      ),
    );
  }
}

/// The front card leans a few degrees towards the light ([lean] 1); the side
/// cards hold still (0).
class _FrontTilt extends StatelessWidget {
  const _FrontTilt({required this.sheen, required this.lean, required this.child});
  final ValueListenable<double> sheen;
  final double lean;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: sheen,
        child: child,
        builder: (_, p, child) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0011)
            ..rotateY((p - 0.5) * 0.14 * lean),
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
