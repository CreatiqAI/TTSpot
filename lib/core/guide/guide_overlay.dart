import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/titi.dart';
import 'guide.dart';

// The TiTi guide on screen: a dim with a spotlight hole, TiTi and a speech
// card. Inserted into the root overlay by GuideController.showOnce.
//
// Motion (docs/titi-guides-plan.md): dim fades in, TiTi rises from below with
// one springy settle (no idle wobble, ever), the hole glides between steps,
// and on the way out TiTi drops and the dim fades (~280 ms).

/// The card is always white, whatever the app theme.
const _ink = AppColors.ink;
const _body = Color(0xFF6B6B6B);
const _dotOff = Color(0xFFDADADA);

/// One spotlight: a rect (in overlay coordinates) and its corner radius.
@immutable
class _Hole {
  const _Hole(this.rect, this.radius, [this.target]);
  final Rect rect;
  final double radius;

  /// The target itself (no padding). Only on a settled hole, not mid-glide:
  /// that's where a "tap it" step lets touches through.
  final Rect? target;

  bool get isOpen => rect.width >= 2 && rect.height >= 2;

  _Hole get collapsed => _Hole(Rect.fromCenter(center: rect.center, width: 0, height: 0), 0);

  static _Hole? lerp(_Hole? a, _Hole? b, double t) {
    if (a == null && b == null) return null;
    a ??= b!.collapsed;
    b ??= a.collapsed;
    if (t >= 1) return b;
    return _Hole(Rect.lerp(a.rect, b.rect, t)!, lerpDouble(a.radius, b.radius, t)!);
  }

  bool near(_Hole? o) =>
      o != null &&
      (rect.left - o.rect.left).abs() < 0.5 &&
      (rect.top - o.rect.top).abs() < 0.5 &&
      (rect.right - o.rect.right).abs() < 0.5 &&
      (rect.bottom - o.rect.bottom).abs() < 0.5 &&
      (radius - o.radius).abs() < 0.5;
}

/// The guide overlay. [onEnd] runs once, when the guide starts leaving;
/// [onRemove] after the exit animation (remove the entry there).
class GuideOverlay extends StatefulWidget {
  const GuideOverlay({super.key, required this.guide, required this.onEnd, required this.onRemove});
  final Guide guide;
  final ValueChanged<GuideResult> onEnd;
  final VoidCallback onRemove;

  /// Widest the speech card gets.
  static const maxCardWidth = 340.0;

  @override
  State<GuideOverlay> createState() => GuideOverlayState();
}

class GuideOverlayState extends State<GuideOverlay> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final AnimationController _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 350), value: 1);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final Ticker _measure = createTicker(_onTick);

  // Frames cost a lot over native views (the Mapbox map composes with the
  // platform thread every frame), so nothing here runs forever: the
  // per-frame measuring stops [_activeFor] after a step starts (then a
  // cheap timer keeps an eye on the target), and the ring pulses
  // [_pulseCycles] times then rests.
  static const _activeFor = Duration(milliseconds: 900);
  static const _pulseCycles = 3;
  Timer? _idleMeasure;
  Timer? _settle;

  int _index = 0;
  _Hole? _from;
  _Hole? _to;
  bool _ending = false;
  bool _reduce = false;
  bool _started = false;
  bool _laidOut = false;
  Size _screen = Size.zero;

  int? _tapPointer;
  Offset? _tapDown;

  GuideStep get _step => widget.guide.steps[_index];
  int get _count => widget.guide.steps.length;
  bool get _last => _index == _count - 1;

  /// The hole as drawn right now (mid-glide too), or null when there is none.
  _Hole? get _shown {
    final h = _Hole.lerp(_from, _to, _reduce ? 1 : Curves.easeInOutCubic.transform(_move.value));
    return h != null && h.isOpen ? h : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _wake();
    // Let the system send Back to the app while TiTi is up (Android
    // predictive back would otherwise close the app on a root page).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _laidOut = true;
      if (mounted) const NavigationNotification(canHandlePop: true).dispatch(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screen = MediaQuery.sizeOf(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (!_started || reduce != _reduce) {
      _reduce = reduce;
      _enter.duration = Duration(milliseconds: reduce ? 180 : 500);
      _exit.duration = Duration(milliseconds: reduce ? 150 : 280);
      _move.duration = reduce ? Duration.zero : const Duration(milliseconds: 350);
      if (reduce) {
        _pulse.stop();
        _pulse.value = 0.5;
      } else {
        _pulseAFew();
      }
    }
    if (!_started) {
      _started = true;
      _to = _measureHole(_step);
      _from = _to;
      _enter.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(_step));
    }
  }

  @override
  void dispose() {
    // Taken away without the exit (the overlay went, e.g. the app's root
    // rebuilt during start-up): the member never really saw it.
    if (!_ending) {
      _ending = true;
      widget.onEnd(GuideResult.notShown);
    }
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _idleMeasure?.cancel();
    _settle?.cancel();
    _measure.dispose();
    _enter.dispose();
    _exit.dispose();
    _move.dispose();
    _pulse.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ measuring

  /// Every frame: the target may still be sliding in, scrolling, or pushed up
  /// by the keyboard.
  /// Per-frame measuring for a moment (the target may still be moving in),
  /// then a light check every 400 ms.
  void _wake() {
    _idleMeasure?.cancel();
    _settle?.cancel();
    if (!_measure.isActive) _measure.start();
    _settle = Timer(_activeFor, () {
      if (!mounted) return;
      if (_measure.isActive) _measure.stop();
      _idleMeasure = Timer.periodic(const Duration(milliseconds: 400), (_) => _onTick(Duration.zero));
    });
  }

  /// A few slow breaths of the ring, then it rests half-way.
  void _pulseAFew() {
    if (_reduce) return;
    var n = 0;
    _pulse.stop();
    _pulse.value = 0;
    void run() {
      if (!mounted) return;
      _pulse.animateTo(n.isEven ? 1 : 0, curve: Curves.linear).whenComplete(() {
        if (!mounted) return;
        n++;
        if (n < _pulseCycles * 2) {
          run();
        } else {
          _pulse.animateTo(0.5);
        }
      });
    }

    run();
  }

  void _onTick(Duration _) {
    if (!mounted || _ending) return;
    final h = _measureHole(_step);
    if (h == null ? _to == null : h.near(_to)) return;
    setState(() => _to = h);
  }

  _Hole? _measureHole(GuideStep s) {
    final key = s.target;
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize || ro.size.isEmpty) return null;
    Rect r;
    try {
      r = MatrixUtils.transformRect(ro.getTransformTo(null), Offset.zero & ro.size);
    } catch (_) {
      return null;
    }
    // The root overlay sits at the origin; shift anyway if it doesn't (only
    // once laid out: our own box doesn't exist during the first build).
    final me = _laidOut ? context.findRenderObject() : null;
    if (me is RenderBox && me.hasSize && me.attached) r = r.shift(-me.localToGlobal(Offset.zero));
    final screen = Offset.zero & _screen;
    if (!r.isFinite || r.isEmpty) return null;
    // A tall target (a card grid) that runs on under the bottom tab bar or
    // off screen: spotlight only the part you can see above the bar.
    final floor = math.min(_tabBarTop() ?? _screen.height, _screen.height);
    if (r.top < floor - 40 && r.bottom > floor) r = Rect.fromLTRB(r.left, r.top, r.right, floor - 10);
    if (!screen.contains(r.center)) return null;
    final target = r;
    r = r.inflate(s.padding);
    if (s.circle) {
      final side = math.max(r.width, r.height);
      return _Hole(Rect.fromCenter(center: r.center, width: side, height: side), side / 2, target);
    }
    return _Hole(r, math.min(s.radius, r.shortestSide / 2), target);
  }

  /// Top of the bottom tab bar on screen (from its guide keys), or null.
  double? _tabBarTop() {
    final ro = GuideTabKeys.home.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    try {
      final top = ro.localToGlobal(Offset.zero).dy;
      // The keyed boxes sit on the buttons; the bar's glass starts a little higher.
      return top > _screen.height / 2 ? top - 14 : null;
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------- actions

  void _go(int i) {
    setState(() {
      _from = _Hole.lerp(_from, _to, Curves.easeInOutCubic.transform(_move.value));
      _index = i;
      _to = _measureHole(_step);
      _tapPointer = null;
    });
    _move.forward(from: 0);
    _wake();
    _pulseAFew();
    _reveal(_step);
  }

  /// The target is built but scrolled away (or under the tab bar): scroll it
  /// into view, then the spotlight follows it there.
  void _reveal(GuideStep s) {
    final ctx = s.target?.currentContext;
    if (!mounted || ctx == null || !ctx.mounted) return;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return;
    Rect r;
    try {
      r = MatrixUtils.transformRect(ro.getTransformTo(null), Offset.zero & ro.size);
    } catch (_) {
      return;
    }
    // Bottom chrome (a tab bar, a comment box) covers the last part of most
    // pages, so "in view" means clear of the bottom quarter.
    final floor = math.min(_tabBarTop() ?? _screen.height, _screen.height * 0.78);
    final tall = r.height > _screen.height * 0.45;
    final visible = r.top >= 60 && (tall ? r.top < _screen.height * 0.5 : r.bottom <= floor);
    if (visible || Scrollable.maybeOf(ctx) == null) return;
    Scrollable.ensureVisible(ctx, alignment: 0.4, duration: const Duration(milliseconds: 380), curve: Curves.easeInOutCubic).whenComplete(() {
      if (mounted && !_ending) _wake();
    });
  }

  void _next() {
    if (_ending) return;
    HapticFeedback.selectionClick();
    if (_last) {
      close(GuideResult.finished);
    } else {
      _go(_index + 1);
    }
  }

  /// Ends the guide with [result]: the caller hears at once, the overlay
  /// animates out and then removes itself.
  void close(GuideResult result) {
    if (_ending || !mounted) return;
    setState(() => _ending = true);
    widget.onEnd(result);
    _exit.forward().whenComplete(() {
      if (mounted) widget.onRemove();
    });
  }

  Future<bool> _onBack() async {
    if (_ending || !mounted) return false;
    close(GuideResult.skipped);
    return true;
  }

  /// Fallback for apps without a Router (the router path is BackButtonListener).
  @override
  Future<bool> didPopRoute() async {
    if (_ending || !mounted) return false;
    return _onBack();
  }

  /// "Tap it" steps: the tap reaches the real widget (the hit area lets it
  /// through); when it lifts inside the hole, the guide ends after the tap
  /// has been delivered.
  void _onPointer(PointerEvent e) {
    if (_ending || !mounted || !_step.tapTarget) return;
    final hole = _shown?.target;
    final p = _toLocal(e.position);
    if (e is PointerDownEvent) {
      if (hole != null && hole.contains(p)) {
        _tapPointer = e.pointer;
        _tapDown = p;
      }
    } else if (e is PointerUpEvent && e.pointer == _tapPointer) {
      _tapPointer = null;
      final moved = (p - (_tapDown ?? p)).distance;
      if (hole != null && hole.contains(p) && moved < kTouchSlop * 1.5) {
        Timer.run(() => close(GuideResult.tappedTarget));
      }
    } else if (e is PointerCancelEvent && e.pointer == _tapPointer) {
      _tapPointer = null;
    }
  }

  Offset _toLocal(Offset global) {
    final me = _laidOut ? context.findRenderObject() : null;
    return me is RenderBox && me.hasSize && me.attached ? me.globalToLocal(global) : global;
  }

  // ------------------------------------------------------------- building

  double get _dim {
    final inT = Curves.easeOut.transform(const Interval(0, 0.55).transform(_enter.value));
    final outT = Curves.easeOut.transform(_exit.value);
    return inT * (1 - outT);
  }

  @override
  Widget build(BuildContext context) {
    _screen = MediaQuery.sizeOf(context);
    final step = _step;
    final everything = Listenable.merge([_enter, _exit, _move]);

    Widget body = _GuideHitArea(
      hole: () => _shown?.target,
      passThrough: step.tapTarget && !_ending,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: CustomPaint(
              painter: _DimPainter(hole: () => _shown, dim: () => _dim, pulse: () => Curves.easeInOut.transform(_pulse.value), repaint: Listenable.merge([everything, _pulse])),
            ),
          ),
          if (step.tapTarget)
            IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge([everything, _pulse]),
                builder: (context, _) => _hand(),
              ),
            ),
          AnimatedBuilder(animation: everything, builder: (context, _) => _layout(context)),
        ],
      ),
    );

    if (Router.maybeOf(context)?.backButtonDispatcher != null) {
      body = BackButtonListener(onBackButtonPressed: _onBack, child: body);
    }
    return Material(
      type: MaterialType.transparency,
      child: IgnorePointer(ignoring: _ending, child: body),
    );
  }

  /// The pointing hand on a "tap it" step: pulses like a finger tapping.
  Widget _hand() {
    final hole = _shown;
    if (hole == null) return const SizedBox.shrink();
    final p = _reduce ? 0.5 : Curves.easeInOut.transform(_pulse.value);
    final settled = _move.value >= 1 ? 1.0 : 0.0;
    final opacity = (_cardIn * settled).clamp(0.0, 1.0);
    const size = 40.0;
    final c = hole.rect.center;
    final down = 4 * p;
    return Stack(
      children: [
        Positioned(
          // The fingertip (top-centre of the glyph) rests just below the centre.
          left: c.dx - size * 0.45,
          // Kept on screen for targets at the very bottom (the tab bar).
          top: math.min(c.dy + hole.rect.height * 0.12, _screen.height - MediaQuery.paddingOf(context).bottom - size - 2) + down,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: 1.04 - 0.1 * p,
              child: const Icon(
                AppIcons.handPointing,
                size: size,
                color: Colors.white,
                shadows: [Shadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 2))],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Card fade-in (0..1) during arrival, times the exit.
  double get _cardIn {
    final inT = _reduce ? _enter.value : Curves.easeOutCubic.transform(const Interval(0.3, 1).transform(_enter.value));
    final outT = Curves.easeOut.transform(const Interval(0, 0.7).transform(_exit.value));
    return (inT * (1 - outT)).clamp(0.0, 1.0);
  }

  Widget _layout(BuildContext context) {
    final mq = MediaQuery.of(context);
    final groupW = math.min(GuideOverlay.maxCardWidth, _screen.width - 32);
    final t = _reduce ? 1.0 : Curves.easeInOutCubic.transform(_move.value);
    final fromHole = _from != null && _from!.isOpen ? _from : null;
    final toHole = _to != null && _to!.isOpen ? _to : null;
    final insets = EdgeInsets.only(
      top: mq.padding.top + 12,
      bottom: math.max(mq.padding.bottom, mq.viewInsets.bottom) + 12,
    );

    // TiTi's size: smaller when the free space is tight.
    final room = _room(toHole, insets);
    final titiH = room >= 400 ? 120.0 : 84.0;
    final titiW = titiH * 0.86;

    // TiTi stands under the card, as close to the spotlight's x as fits.
    final groupLeft = (_screen.width - groupW) / 2;
    double titiX(_Hole? h) {
      final cx = h == null ? _screen.width / 2 : h.rect.center.dx;
      return (cx - groupLeft).clamp(titiW / 2 + 6, groupW - titiW / 2 - 6);
    }

    final tx = lerpDouble(titiX(fromHole), titiX(toHole), t)!;

    // Arrival: TiTi rises from below with one overshoot, then stays put.
    final riseT = _reduce ? 1.0 : Curves.easeOutBack.transform(const Interval(0.1, 1).transform(_enter.value));
    final titiFadeIn = _reduce ? _enter.value : const Interval(0.1, 0.5).transform(_enter.value);
    final dropT = _reduce ? 0.0 : Curves.easeInCubic.transform(_exit.value);
    final titiDy = (1 - riseT) * 260 + dropT * 180;
    final titiOpacity = (titiFadeIn * (1 - _exit.value)).clamp(0.0, 1.0);

    final cardOpacity = _cardIn;
    final cardScale = _reduce ? 1.0 : 0.94 + 0.06 * Curves.easeOutCubic.transform(const Interval(0.3, 1).transform(_enter.value)) - 0.04 * _exit.value;

    final group = SizedBox(
      width: groupW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: cardOpacity,
            child: Transform.scale(
              scale: cardScale,
              alignment: Alignment((tx / groupW) * 2 - 1, 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Card(
                    step: _step,
                    index: _index,
                    count: _count,
                    last: _last,
                    reduce: _reduce,
                    onNext: _next,
                    onSkip: () => close(GuideResult.skipped),
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: tx - 9),
                    child: Transform.translate(offset: const Offset(0, -1), child: const CustomPaint(size: Size(18, 10), painter: _TailPainter())),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: EdgeInsets.only(left: tx - titiW / 2),
            child: Opacity(
              opacity: titiOpacity,
              child: Transform.translate(
                offset: Offset(0, titiDy),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: _reduce ? 0 : 250),
                  curve: Curves.easeOutCubic,
                  width: titiW,
                  height: titiH,
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: _reduce ? 120 : 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: _reduce ? child : ScaleTransition(scale: Tween(begin: 0.88, end: 1.0).animate(a), alignment: Alignment.bottomCenter, child: child),
                    ),
                    child: FittedBox(
                      key: ValueKey(_step.pose),
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      child: Titi(_step.pose, height: 130, alignment: Alignment.bottomCenter),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return CustomSingleChildLayout(
      delegate: _GroupLayout(from: fromHole, to: toHole, t: t, insets: insets, gap: 18),
      child: group,
    );
  }

  /// The bigger free band above or below [h] (or the whole height).
  double _room(_Hole? h, EdgeInsets insets) {
    final top = insets.top;
    final bottom = _screen.height - insets.bottom;
    if (h == null) return bottom - top;
    return math.max(h.rect.top - top, bottom - h.rect.bottom);
  }
}

/// Puts the card + TiTi group in the bigger free band beside the hole (or in
/// the middle), gliding between the old and new place while the hole moves.
class _GroupLayout extends SingleChildLayoutDelegate {
  _GroupLayout({required this.from, required this.to, required this.t, required this.insets, required this.gap});
  final _Hole? from;
  final _Hole? to;
  final double t;
  final EdgeInsets insets;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(constraints.maxWidth, math.max(0, constraints.maxHeight - insets.vertical)));

  double _y(_Hole? h, Size size, double childH) {
    final top = insets.top;
    final bottom = size.height - insets.bottom;
    final maxY = math.max(top, bottom - childH);
    if (h == null) return ((top + bottom - childH) / 2).clamp(top, maxY);
    final above = h.rect.top - top;
    final below = bottom - h.rect.bottom;
    final y = below >= above ? h.rect.bottom + gap : h.rect.top - gap - childH;
    return y.clamp(top, maxY);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final y = lerpDouble(_y(from, size, childSize.height), _y(to, size, childSize.height), t)!;
    return Offset((size.width - childSize.width) / 2, y);
  }

  @override
  bool shouldRelayout(_GroupLayout old) => old.from != from || old.to != to || old.t != t || old.insets != insets;
}

// ----------------------------------------------------------------- card

class _Card extends StatelessWidget {
  const _Card({required this.step, required this.index, required this.count, required this.last, required this.reduce, required this.onNext, required this.onSkip});
  final GuideStep step;
  final int index;
  final int count;
  final bool last;
  final bool reduce;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(milliseconds: reduce ? 120 : 220);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 20, offset: Offset(0, 6))],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
      child: AnimatedSize(
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: duration,
          layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
          child: KeyedSubtree(key: ValueKey(index), child: _content()),
        ),
      ),
    );
  }

  Widget _content() {
    final tapStep = step.tapTarget;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(step.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.25, color: _ink)),
        ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(step.body, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, height: 1.38, color: _body)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (tapStep) ...[
              const Icon(AppIcons.handTap, size: 18, color: AppColors.brand),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Tap it to continue', key: Key('guide-tap-hint'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink)),
              ),
            ] else
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: count > 1 ? FittedBox(fit: BoxFit.scaleDown, child: _Dots(index: index, count: count)) : const SizedBox.shrink(),
                ),
              ),
            // Skip: hidden on the last step (unless it's a "tap it" step,
            // which has no other button).
            if (!last || tapStep)
              TextButton(
                key: const Key('guide-skip'),
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: _body,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                child: const Text('Skip', maxLines: 1),
              ),
            if (!tapStep) ...[
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Material(
                  color: AppColors.brand,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    key: const Key('guide-next'),
                    customBorder: const StadiumBorder(),
                    onTap: onNext,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Text(
                        step.nextLabel ?? (last ? 'Got it' : 'Next'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.count});
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(right: 5),
              width: i == index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(color: i == index ? AppColors.brand : _dotOff, borderRadius: BorderRadius.circular(3)),
            ),
        ],
      );
}

class _TailPainter extends CustomPainter {
  const _TailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..quadraticBezierTo(w * 0.62, h * 0.55, w / 2 + 1, h - 1)
      ..quadraticBezierTo(w / 2, h, w / 2 - 1, h - 1)
      ..quadraticBezierTo(w * 0.38, h * 0.55, 0, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TailPainter old) => false;
}

// ------------------------------------------------------------ dim + ring

class _DimPainter extends CustomPainter {
  _DimPainter({required this.hole, required this.dim, required this.pulse, required Listenable repaint}) : super(repaint: repaint);
  final _Hole? Function() hole;
  final double Function() dim;
  final double Function() pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final d = dim();
    if (d <= 0) return;
    final full = Offset.zero & size;
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.7 * d);
    final h = hole();
    if (h == null) {
      canvas.drawRect(full, shade);
      return;
    }
    final rr = RRect.fromRectAndRadius(h.rect, Radius.circular(h.radius));
    canvas.drawPath(Path.combine(PathOperation.difference, Path()..addRect(full), Path()..addRRect(rr)), shade);

    // A soft white ring that breathes around the hole. Fades with a hole
    // that is closing.
    final sizeFade = (h.rect.shortestSide / 24).clamp(0.0, 1.0);
    final p = pulse();
    final ringAlpha = (0.55 - 0.4 * p) * d * sizeFade;
    canvas.drawRRect(
      rr.inflate(3 + 6 * p),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 - p
        ..color = Colors.white.withValues(alpha: ringAlpha),
    );
    canvas.drawRRect(
      rr.inflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.4 * d * sizeFade),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_DimPainter old) => true;
}

// ------------------------------------------------------------ hit testing

/// Swallows every touch on the overlay, except (on a "tap it" step) on the
/// target inside the hole: there the hit test fails, so the touch reaches the real widget
/// underneath. The card's buttons always win.
class _GuideHitArea extends SingleChildRenderObjectWidget {
  const _GuideHitArea({required this.hole, required this.passThrough, super.child});
  final Rect? Function() hole;
  final bool passThrough;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGuideHitArea(hole, passThrough);

  @override
  void updateRenderObject(BuildContext context, _RenderGuideHitArea renderObject) {
    renderObject
      ..hole = hole
      ..passThrough = passThrough;
  }
}

class _RenderGuideHitArea extends RenderProxyBox {
  _RenderGuideHitArea(this.hole, this.passThrough);
  Rect? Function() hole;
  bool passThrough;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    if (passThrough && (hole()?.contains(position) ?? false)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}
