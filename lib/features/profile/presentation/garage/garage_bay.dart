import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/car.dart';
import '../../domain/garage_look.dart';
import 'collector_card.dart';
import 'garage_pager.dart';
import 'garage_scenery.dart';

/// The roller door plays once per app session; after that the garage opens
/// with the door up and just a flicker of the ceiling light.
bool _doorPlayedThisSession = false;

/// How big things are on this screen: 1 on a 390-wide phone, smaller on
/// small phones, bigger on tablets (by the shortest side, so turning the
/// phone doesn't change it).
double garageScale(Size size) => (size.shortestSide / 390).clamp(0.82, 1.3);

/// Where everything stands in the full-screen bay, from the screen size and
/// what floats over it: the top bar ([EdgeInsets.top]) and the collapsed
/// panel ([EdgeInsets.bottom]). The car stands on the floor just above the
/// panel, as wide as ~88 % of the screen when the room allows, never cropped.
class BayLayout {
  factory BayLayout(Size size, EdgeInsets insets) {
    final w = size.width, h = size.height;
    final top = insets.top;
    final panelTop = math.max(top + 60, h - insets.bottom);
    final visible = panelTop - top;
    // A strip of floor shows between the tyres and the panel.
    final gap = (visible * 0.07).clamp(12.0, 44.0);
    final floor = panelTop - gap;
    final room = math.max(48.0, floor - top - 12);
    final carW = w * 0.88;
    // The cut-out's slot: wide cars fill the width, tall ones the room.
    final box = math.min(carW / 1.35, room);
    // A car without a cut-out stands as its card, as big as the room allows.
    final cardH = math.min(room - 4, (w * 0.8) / kCollectorAspect);
    return BayLayout._(
      w: w,
      h: h,
      top: top,
      panelTop: panelTop,
      floor: floor,
      box: box,
      side: (w - carW) / 2,
      cardW: cardH * kCollectorAspect,
      cardH: cardH,
      k: garageScale(size),
    );
  }

  const BayLayout._({
    required this.w,
    required this.h,
    required this.top,
    required this.panelTop,
    required this.floor,
    required this.box,
    required this.side,
    required this.cardW,
    required this.cardH,
    required this.k,
  });

  final double w;
  final double h;

  /// Just under the top bar.
  final double top;

  /// The collapsed panel's top edge.
  final double panelTop;

  /// The line the tyres stand on, from the top.
  final double floor;

  /// Height of the cut-out's slot.
  final double box;

  /// Space left and right of the cut-out's slot.
  final double side;
  final double cardW;
  final double cardH;
  final double k;

  /// Where the back wall meets the floor, as a fraction of the height:
  /// a little under half-way up a car's slot.
  double get floorAt => ((floor - box * 0.42) / h).clamp(0.25, 0.85);
}

/// Concept A, "roller door", full screen: a dark garage bay (back wall, big
/// outlined bay number, epoxy floor with yellow bay lines) from edge to edge,
/// under the floating top bar and over the car's panel. The first visit rolls
/// the shutter up over the whole screen, the light tube flickers on and the
/// car fades in on the floor with its reflection and a streak of light across
/// it. Swipe, the arrows or the dots move to the next car. Cars with a good
/// cut-out stand in the bay; the rest stand there as their collector card.
/// The owner's last bay is empty, to park another car.
class GarageBayStage extends StatefulWidget {
  const GarageBayStage({
    super.key,
    required this.cars,
    required this.index,
    required this.onIndex,
    required this.onOpen,
    this.insets = EdgeInsets.zero,
    this.lift,
    this.door,
    this.onLongPress,
    this.onAdd,
    this.parking = const {},
  });

  final List<Car> cars;
  /// The settled page; the stage moves there when it changes from outside.
  final int index;
  final ValueChanged<int> onIndex;
  final ValueChanged<Car> onOpen;

  /// What floats over the bay: the top bar (top) and the collapsed panel (bottom).
  final EdgeInsets insets;

  /// How far the panel has been pulled up past its collapsed height, in px:
  /// the bay rises with it and the car shrinks to stay in view.
  final ValueListenable<double>? lift;

  /// Where the roller door is (0 shut, 1 up), for the panel to follow.
  final ValueNotifier<double>? door;
  final ValueChanged<Car>? onLongPress;
  /// Shows the empty "Park another car" bay at the end (owner only).
  final VoidCallback? onAdd;
  /// Cars whose cut-out is being made: "Parking your car…".
  final Set<String> parking;

  /// The door will roll on the next bay that opens (the first this session).
  static bool get doorWillPlay => !_doorPlayedThisSession;

  @visibleForTesting
  static void debugResetDoor() => _doorPlayedThisSession = false;

  @override
  State<GarageBayStage> createState() => _GarageBayStageState();
}

class _GarageBayStageState extends State<GarageBayStage> with TickerProviderStateMixin {
  late final GaragePager _pager = GaragePager(vsync: this, index: widget.index);
  late final bool _fullIntro;
  late final AnimationController _intro;
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  bool _openHaptic = false;
  bool _topHaptic = false;
  static const _noLift = AlwaysStoppedAnimation<double>(0);

  /// Where the streak of light is (0–1, 0 = none). The car itself draws it,
  /// on its own pixels only (see [_Shine]).
  final _shine = ValueNotifier<double>(0);

  void _updateShine() {
    final t = _sweep.isAnimating ? _sweep.value : _introSweep;
    _shine.value = (t <= 0 || t >= 1) ? 0 : t;
  }

  // Timeline of the first visit, in ms (from the concept): door rolls 650–1800,
  // tube flickers 1150–2150, light spills 1550–2750, car fades 1550–2000,
  // a streak crosses the car 2250–3550.
  static const _fullMs = 3600.0;
  static const _quickMs = 900.0;

  int get _count => widget.cars.length + (widget.onAdd != null ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _pager.count = math.max(1, _count);
    _fullIntro = !_doorPlayedThisSession;
    _doorPlayedThisSession = true;
    _intro = AnimationController(vsync: this, duration: Duration(milliseconds: (_fullIntro ? _fullMs : _quickMs).round()));
    if (_fullIntro) _intro.addListener(_doorHaptics);
    _intro.addListener(_updateShine);
    _intro.addListener(_reportDoor);
    _sweep.addListener(_updateShine);
    _intro.forward();
  }

  @override
  void didUpdateWidget(GarageBayStage old) {
    super.didUpdateWidget(old);
    _pager.count = math.max(1, _count);
    final want = widget.index.clamp(0, _pager.count - 1);
    if (want != _pager.target) {
      _pager.animateTo(want);
      _sweep.forward(from: 0.2);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _sweep.dispose();
    _shine.dispose();
    _pager.dispose();
    super.dispose();
  }

  void _reportDoor() {
    final d = widget.door;
    if (d != null && d.value != _door) d.value = _door;
  }

  void _doorHaptics() {
    final ms = _intro.value * _fullMs;
    if (!_openHaptic && ms >= 650) {
      _openHaptic = true;
      HapticFeedback.mediumImpact();
    }
    if (!_topHaptic && ms >= 1800) {
      _topHaptic = true;
      HapticFeedback.heavyImpact();
    }
  }

  double _interval(double fromMs, double toMs, {Curve curve = Curves.linear}) {
    final total = _fullIntro ? _fullMs : _quickMs;
    final t = ((_intro.value * total - fromMs) / (toMs - fromMs)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  /// 0 = shut, 1 = rolled all the way up.
  double get _door => _fullIntro ? _interval(650, 1800, curve: const Cubic(0.7, 0, 0.25, 1)) : 1;
  double get _tube => _flicker(_fullIntro ? _interval(1150, 2150) : _interval(0, 760));
  double get _wash => _fullIntro ? _interval(1550, 2750, curve: Curves.easeOut) : _interval(80, 900, curve: Curves.easeOut);
  double get _carIn => _fullIntro ? _interval(1550, 2000, curve: Curves.easeOut) : _interval(0, 280, curve: Curves.easeOut);
  double get _introSweep => _fullIntro ? _interval(2250, 3550) : 0;
  bool get _introRunning => _intro.isAnimating && _fullIntro && _door < 1;

  /// The tube's start-up stutter (keyframes from the concept).
  static double _flicker(double t) {
    const keys = [(0.0, 0.0), (0.08, 0.85), (0.12, 0.1), (0.20, 1.0), (0.26, 0.25), (0.34, 1.0), (1.0, 1.0)];
    for (var i = 1; i < keys.length; i++) {
      if (t <= keys[i].$1) {
        final a = keys[i - 1], b = keys[i];
        return a.$2 + (b.$2 - a.$2) * ((t - a.$1) / (b.$1 - a.$1));
      }
    }
    return 1;
  }

  void _skip() {
    if (!_intro.isAnimating) return;
    _openHaptic = true;
    _topHaptic = true;
    HapticFeedback.lightImpact();
    _intro.value = 1;
    _sweep.forward(from: 0);
  }

  void _go(int page) {
    final p = page.clamp(0, _pager.count - 1);
    if (p == widget.index) return;
    _pager.animateTo(p);
    garageSwipeHaptic();
    _sweep.forward(from: 0.2);
    widget.onIndex(p);
  }

  @override
  Widget build(BuildContext context) {
    final lift = widget.lift ?? _noLift;
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, c) {
          final g = BayLayout(c.biggest, widget.insets);
          final w = g.w, h = g.h;
          final slots = <Widget>[];
          final heights = <double>[];
          for (var i = 0; i < widget.cars.length; i++) {
            final car = widget.cars[i];
            final parking = widget.parking.contains(car.id);
            slots.add(_BaySlot(
              key: ValueKey(car.id),
              car: car,
              parking: parking,
              layout: g,
              onTap: () => widget.onOpen(car),
              onLongPress: widget.onLongPress == null ? null : () => widget.onLongPress!(car),
            ));
            heights.add(!parking && garageLookFor(car) == GarageLook.card ? g.cardH : g.box);
          }
          if (widget.onAdd != null) {
            slots.add(_EmptyBay(key: const ValueKey('add'), layout: g, onAdd: widget.onAdd!));
            heights.add(g.box);
          }
          final arrowY = g.floor - math.min(g.box, g.cardH) / 2 - 22;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _pager.dragStart(),
            onHorizontalDragUpdate: (d) => _pager.dragUpdate(-(d.primaryDelta ?? 0) / w),
            onHorizontalDragEnd: (d) {
              final target = _pager.dragEnd(-(d.primaryVelocity ?? 0) / w);
              if (target != widget.index) {
                garageSwipeHaptic();
                _sweep.forward(from: 0.2);
                widget.onIndex(target);
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Under the bay when it rises with the panel.
                const ColoredBox(color: GarageColors.floorBottom),
                // The bay itself never moves sideways: one picture.
                ValueListenableBuilder<double>(
                  valueListenable: lift,
                  builder: (_, up, child) => Transform.translate(offset: Offset(0, -_rise(g, up)), child: child),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      BayBackdrop(floorAt: g.floorAt, lineInset: 34 * g.k),
                      // BAY 0n, big and outlined on the back wall.
                      Positioned(
                        left: 26,
                        top: g.top + 14,
                        child: Text(
                          'BAY',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(fontSize: 11 * g.k, fontWeight: FontWeight.w700, letterSpacing: 3, color: Colors.white.withValues(alpha: 0.28)),
                        ),
                      ),
                      Positioned(
                        right: 22,
                        top: g.top + 4,
                        child: AnimatedBuilder(
                          animation: _pager.position,
                          builder: (_, _) => AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: BayNumber(key: ValueKey(_pager.page), text: bayNumber(_pager.page), size: ((g.panelTop - g.top) * 0.3).clamp(90.0, 250.0)),
                          ),
                        ),
                      ),
                      // Ceiling tube and the light it spills.
                      AnimatedBuilder(
                        animation: _intro,
                        builder: (_, _) => CeilingLight(
                          top: g.top + 4,
                          inset: math.max(50.0, w * 0.14),
                          tube: _tube,
                          wash: _wash,
                          washCenter: Alignment(0, (g.top / h) * 2 - 1.05),
                          floorPoolHeight: g.box * 0.9,
                          floorPoolBottom: h - g.floor - g.box * 0.45,
                          floorPoolWidth: math.min(w * 0.95, 300 * g.k * 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                // The cars: the current one in the bay, its neighbours sliding in and out.
                _ShineScope(
                  notifier: _shine,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_pager.position, _intro, lift]),
                    builder: (_, _) {
                      final pos = _pager.position.value;
                      final carIn = _carIn;
                      final up = _rise(g, lift.value);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          for (var i = 0; i < slots.length; i++)
                            if ((i - pos).abs() < 1.15) _placed(slots[i], i - pos, g, heights[i], carIn, up),
                        ],
                      );
                    },
                  ),
                ),
                if (_count > 1) ...[
                  _arrow(left: true, top: arrowY, lift: lift),
                  _arrow(left: false, top: arrowY, lift: lift),
                ],
                // The roller door over the whole screen, then a tap-to-skip layer while it plays.
                AnimatedBuilder(
                  animation: _intro,
                  builder: (_, child) {
                    final t = _door;
                    if (t >= 1) return const SizedBox.shrink();
                    return FractionalTranslation(translation: Offset(0, -1.02 * t), child: child);
                  },
                  child: RepaintBoundary(child: _RollerDoor(k: g.k)),
                ),
                AnimatedBuilder(
                  animation: _intro,
                  builder: (_, _) => _introRunning
                      ? Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _skip))
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// How far the bay rises for a panel pulled up by [up] px: with it, but
  /// never so far that the car would stand under the top bar.
  static double _rise(BayLayout g, double up) => math.min(up, (g.floor - g.top) * 0.6);

  /// One bay's content at offset [d] pages from the middle. When the panel
  /// is pulled up by [up] px the car rides up with the floor and shrinks to
  /// fit between the top bar and the panel ([height]: how tall it stands).
  Widget _placed(Widget child, double d, BayLayout g, double height, double carIn, double up) {
    final a = d.abs();
    final opacity = ((1 - a * 1.5).clamp(0.0, 1.0)) * carIn;
    final room = g.floor - up - g.top - 8;
    final fit = height <= 0 ? 1.0 : (room / height).clamp(0.45, 1.0);
    final scale = (1 - 0.18 * a.clamp(0.0, 1.0)) * fit;
    final cx = g.w / 2, cy = g.floor;
    final m = Matrix4.translationValues(d * g.w * 1.1 + cx, cy - up, 0)
      ..multiply(Matrix4.diagonal3Values(scale, scale, 1))
      ..multiply(Matrix4.translationValues(-cx, -cy, 0));
    return Positioned.fill(
      key: child.key,
      child: IgnorePointer(
        ignoring: a > 0.5,
        child: Transform(
          transform: m,
          child: Opacity(opacity: opacity, child: child),
        ),
      ),
    );
  }

  Widget _arrow({required bool left, required double top, required ValueListenable<double> lift}) {
    return Positioned(
      left: left ? 8 : null,
      right: left ? null : 8,
      top: top,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pager.position, _intro, lift]),
        builder: (_, _) {
          final page = _pager.page;
          final enabled = left ? page > 0 : page < _count - 1;
          // Out of the way once the panel is pulled up (swiping still works).
          final shown = (1 - lift.value / 60).clamp(0.0, 1.0) * (_door >= 1 ? 1 : 0);
          return IgnorePointer(
            ignoring: shown < 0.5,
            child: Opacity(
              opacity: (enabled ? 1.0 : 0.35) * shown,
              child: _RoundButton(
                icon: left ? AppIcons.caretLeft : AppIcons.caretRight,
                tooltip: left ? 'Previous car' : 'Next car',
                onTap: enabled ? () => _go(page + (left ? -1 : 1)) : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// What stands in one bay: the cut-out with its reflection, the collector
/// card, or "Parking your car…" while the cut-out is made.
class _BaySlot extends StatelessWidget {
  const _BaySlot({super.key, required this.car, required this.parking, required this.layout, required this.onTap, this.onLongPress});
  final Car car;
  final bool parking;
  final BayLayout layout;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    if (parking) return _Parking(car: car, layout: layout);
    if (garageLookFor(car) == GarageLook.cutout) {
      return _CutoutCar(car: car, layout: layout, onTap: onTap, onLongPress: onLongPress);
    }
    return _StandingCard(car: car, layout: layout, onTap: onTap, onLongPress: onLongPress);
  }
}

/// The car cut out of its photo, standing on the floor with a contact shadow
/// and its reflection in the epoxy. Fades in once the PNG has loaded; if it
/// can't load, the car's card stands there instead.
class _CutoutCar extends StatefulWidget {
  const _CutoutCar({required this.car, required this.layout, required this.onTap, this.onLongPress});
  final Car car;
  final BayLayout layout;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_CutoutCar> createState() => _CutoutCarState();
}

class _CutoutCarState extends State<_CutoutCar> {
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    (_, _) => _update(() => _ready = true),
    onError: (_, _) => _update(() => _failed = true),
  );
  bool _ready = false;
  bool _failed = false;
  /// A cached image answers inside addListener, mid-build: no setState then.
  bool _resolving = false;

  void _update(VoidCallback change) {
    if (_resolving) {
      change();
    } else if (mounted) {
      setState(change);
    }
  }

  ImageProvider get _provider => garageCutoutProvider(widget.car)!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_CutoutCar old) {
    super.didUpdateWidget(old);
    if (old.car.cutoutUrl != widget.car.cutoutUrl) {
      _ready = false;
      _failed = false;
      _resolve();
    }
  }

  void _resolve() {
    final next = _provider.resolve(createLocalImageConfiguration(context));
    if (next.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _resolving = true;
    _stream = next..addListener(_listener);
    _resolving = false;
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.layout;
    if (_failed) {
      return _StandingCard(car: widget.car, layout: g, onTap: widget.onTap, onLongPress: widget.onLongPress);
    }
    return AnimatedOpacity(
      opacity: _ready ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      child: StandingCutout(
        image: _provider,
        stageWidth: g.w,
        stageHeight: g.h,
        box: g.box,
        bottom: g.h - g.floor,
        side: g.side,
        shadowHeight: g.box * 0.2,
        semanticLabel: widget.car.title,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        wrap: (car) => _Shine(child: car),
      ),
    );
  }
}

/// A car without a cut-out: its collector card standing in the bay, with a
/// faint reflection on the floor.
class _StandingCard extends StatelessWidget {
  const _StandingCard({required this.car, required this.layout, required this.onTap, this.onLongPress});
  final Car car;
  final BayLayout layout;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final g = layout;
    final left = (g.w - g.cardW) / 2;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: left,
          width: g.cardW,
          top: g.floor,
          height: g.cardH,
          child: IgnorePointer(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x29FFFFFF), Color(0x00FFFFFF)],
                stops: [0, 0.3],
              ).createShader(r),
              child: Transform.flip(flipY: true, child: CollectorCard(car: car, index: 0, width: g.cardW, showBay: false, shadow: false)),
            ),
          ),
        ),
        Positioned(
          left: left,
          width: g.cardW,
          bottom: g.h - g.floor,
          height: g.cardH,
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            child: _Shine(child: CollectorCard(car: car, index: 0, width: g.cardW, showBay: false)),
          ),
        ),
      ],
    );
  }
}

/// "Parking your car…": a shimmering silhouette while the cut-out is made.
class _Parking extends StatefulWidget {
  const _Parking({required this.car, required this.layout});
  final Car car;
  final BayLayout layout;

  @override
  State<_Parking> createState() => _ParkingState();
}

class _ParkingState extends State<_Parking> with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.layout;
    final box = g.box * 0.82;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: g.side,
          right: g.side,
          bottom: g.h - g.floor,
          height: box,
          child: AnimatedBuilder(
            animation: _shimmer,
            builder: (_, child) => ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [Color(0xFF2A2E36), Color(0xFF59606C), Color(0xFF2A2E36)],
                stops: const [0.35, 0.5, 0.65],
                transform: _SlideX(_shimmer.value * 2.4 - 1.2),
              ).createShader(r),
              child: child,
            ),
            child: Image.asset(carPlaceholderAsset(widget.car.bodyStyle), fit: BoxFit.contain, alignment: Alignment.bottomCenter),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: math.max(g.top + 8, g.floor - box - 44),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: GarageColors.chip, borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Text(
                'Parking your car…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: GarageColors.text),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The owner's last bay: empty, with a painted spot on the floor and a big
/// plus in the middle of the room.
class _EmptyBay extends StatelessWidget {
  const _EmptyBay({super.key, required this.layout, required this.onAdd});
  final BayLayout layout;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final g = layout;
    final spotTop = g.floor - g.box * 0.5;
    final plus = 68 * g.k;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: g.side,
          right: g.side,
          top: spotTop,
          height: g.floor - spotTop + (g.panelTop - g.floor) * 0.7,
          child: const IgnorePointer(child: CustomPaint(painter: _SpotPainter())),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: g.top + 8,
          bottom: g.h - g.floor + g.box * 0.12,
          child: Center(
            // Never spills out of a short room (a small phone, big text).
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    button: true,
                    label: 'Park another car',
                    child: GestureDetector(
                      onTap: onAdd,
                      child: Container(
                        width: plus,
                        height: plus,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.24), width: 1.2),
                        ),
                        child: Icon(AppIcons.plus, color: GarageColors.text, size: 28 * g.k),
                      ),
                    ),
                  ),
                  SizedBox(height: 14 * g.k),
                  Text(
                    'PARK ANOTHER CAR',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
                    style: TextStyle(fontFamily: AppFonts.display, fontSize: 28 * g.k, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: Colors.white.withValues(alpha: 0.88)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GarageColors.button,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(icon, size: 18, color: GarageColors.text),
          ),
        ),
      );
}

/// Carries the streak position ([_GarageBayStageState._shine]) down to the
/// cars in the bay.
class _ShineScope extends InheritedNotifier<ValueNotifier<double>> {
  const _ShineScope({required super.notifier, required super.child});
}

/// The streak of light that crosses a car after it lands or moves. Drawn on
/// the car's own pixels (srcATop over its cut-out or card), so it follows the
/// car's shape and never shows as a box over the wall and floor.
class _Shine extends StatelessWidget {
  const _Shine({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.dependOnInheritedWidgetOfExactType<_ShineScope>()?.notifier?.value ?? 0;
    if (t <= 0 || t >= 1) return child;
    final strength = t < 0.2 ? t / 0.2 : 1 - (t - 0.2) / 0.8;
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (r) => LinearGradient(
        begin: const Alignment(-1, -0.35),
        end: const Alignment(1, 0.35),
        colors: [const Color(0x00FFFFFF), Color.fromRGBO(255, 255, 255, 0.5 * strength), const Color(0x00FFFFFF)],
        stops: const [0.4, 0.5, 0.6],
        transform: _Slide((t * 2.4 - 1.2) * r.width),
      ).createShader(r),
      child: child,
    );
  }
}

/// Moves a gradient sideways by [dx] px.
class _Slide extends GradientTransform {
  const _Slide(this.dx);
  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(dx, 0, 0);
}

/// The corrugated roller shutter with the TT Spot logo, as big as the screen.
class _RollerDoor extends StatelessWidget {
  const _RollerDoor({required this.k});
  final double k;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 6))]),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _ShutterPainter()),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x14FFFFFF), Color(0x00FFFFFF), Color(0x59000000)],
                stops: [0, 0.4, 1],
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/brand/logo_dark.png', width: 170 * k, filterQuality: FilterQuality.medium, opacity: const AlwaysStoppedAnimation(0.92)),
                SizedBox(height: 6 * k),
                Text(
                  'PRIVATE GARAGE',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(fontSize: 12 * k, fontWeight: FontWeight.w700, letterSpacing: 4.5, color: Colors.white.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 84 * k,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFF15161A),
                  borderRadius: BorderRadius.circular(4),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShutterPainter extends CustomPainter {
  const _ShutterPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // One slat every 13 px: a lit face, a dark seam, a bright lip.
    const slat = 13.0;
    final face = Paint()
      ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A3E46), Color(0xFF30333A)])
          .createShader(const Rect.fromLTWH(0, 0, 1, 9));
    final seam = Paint()..color = const Color(0xFF1D1F24);
    final lip = Paint()..color = const Color(0xFF41454E);
    for (var y = 0.0; y < size.height; y += slat) {
      canvas.save();
      canvas.translate(0, y);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 9), face);
      canvas.restore();
      canvas.drawRect(Rect.fromLTWH(0, y + 9, size.width, 2), seam);
      canvas.drawRect(Rect.fromLTWH(0, y + 11, size.width, 2), lip);
    }
    // The bottom rail.
    canvas.drawRect(Rect.fromLTWH(0, size.height - 10, size.width, 10), Paint()..color = const Color(0xFF15161A));
  }

  @override
  bool shouldRepaint(_ShutterPainter old) => false;
}

/// A painted parking spot on the floor of the empty bay.
class _SpotPainter extends CustomPainter {
  const _SpotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..moveTo(w * 0.2, 0)
      ..lineTo(w * 0.8, 0)
      ..lineTo(w * 0.94, h)
      ..lineTo(w * 0.06, h)
      ..close();
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 8, m.length)), p);
        d += 14;
      }
    }
  }

  @override
  bool shouldRepaint(_SpotPainter old) => false;
}

class _SlideX extends GradientTransform {
  const _SlideX(this.dx);
  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(bounds.width * dx, 0, 0);
}
