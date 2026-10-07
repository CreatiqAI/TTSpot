import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'guide.dart';
import 'guide_controller.dart';

/// Wraps a page: once [ready] is true (data loaded) and the page is on top,
/// waits a beat and shows the guide from [build] if it hasn't been seen.
/// [build] runs at show time, so it can read current state (e.g. skip a step).
///
/// "On top" means: its route is current, its tab is the visible one (hidden
/// shell tabs have tickers off), the app is in the foreground, nothing covers
/// the page's centre (a dialog, a sheet, a pushed page), the member is
/// onboarded and no other guide is up. Until then it keeps checking for
/// about 10 s, then gives up quietly. One try per widget lifetime.
class GuideOnFirstView extends ConsumerStatefulWidget {
  const GuideOnFirstView({super.key, required this.id, required this.build, required this.child, this.ready = true, this.delay = const Duration(milliseconds: 700), this.onDone});

  /// One of [GuideIds]; checked before [build] runs.
  final String id;
  final Guide Function() build;
  final Widget child;
  final bool ready;
  final Duration delay;

  /// After the guide ends (not when it wasn't shown). May run after this
  /// widget is gone (a "tap it" step that navigated away): check `mounted`
  /// before touching widget state.
  final void Function(GuideResult result)? onDone;

  /// How often it re-checks, and how long it keeps trying once [ready].
  static const tick = Duration(milliseconds: 150);
  static const giveUpAfter = Duration(seconds: 10);

  @override
  ConsumerState<GuideOnFirstView> createState() => _GuideOnFirstViewState();
}

class _GuideOnFirstViewState extends ConsumerState<GuideOnFirstView> {
  final _probe = GlobalKey();
  Timer? _timer;
  bool _done = false;

  /// Time spent trying (only counts while [GuideOnFirstView.ready]).
  Duration _waited = Duration.zero;

  /// How long the page has been showable without a break.
  Duration? _showableFor;

  bool _tickerOn = true;
  ModalRoute<Object?>? _route;
  int? _viewId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerOn = TickerMode.valuesOf(context).enabled;
    _route = ModalRoute.of(context);
    _viewId = View.maybeOf(context)?.viewId;
    // A tab coming into view (TickerMode) or the route on top changing.
    if (!_tickerOn || !(_route?.isCurrent ?? true)) _showableFor = null;
  }

  @override
  void didUpdateWidget(GuideOnFirstView old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_done || !mounted || !widget.ready || _timer != null) return;
    _timer = Timer.periodic(GuideOnFirstView.tick, (_) => _check());
    _check(first: true);
  }

  void _stop({bool done = false}) {
    _timer?.cancel();
    _timer = null;
    if (done) _done = true;
  }

  void _check({bool first = false}) {
    if (_done || !mounted) return _stop();
    if (!widget.ready) {
      // Data went back to loading: wait for ready again (didUpdateWidget).
      _showableFor = null;
      return _stop();
    }
    if (!first) _waited += GuideOnFirstView.tick;
    final c = ref.read(guideControllerProvider);
    if (c.ready && (c.seen(widget.id) || !c.enabled)) return _stop(done: true);

    if (!(c.ready && c.onboarded && !c.showing && _visible())) {
      _showableFor = null;
      if (_waited >= GuideOnFirstView.giveUpAfter) _stop(done: true);
      return;
    }
    if (_showableFor == null) {
      _showableFor = Duration.zero;
    } else if (!first) {
      _showableFor = _showableFor! + GuideOnFirstView.tick;
    }
    if (_showableFor! < widget.delay) return;
    _stop(done: true);
    _show();
  }

  Future<void> _show() async {
    final r = await ref.read(guideControllerProvider).showOnce(context, widget.build());
    if (r != GuideResult.notShown) widget.onDone?.call(r);
  }

  bool _visible() {
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return false;
    if (!_tickerOn) return false;
    if (!(_route?.isCurrent ?? true)) return false;
    final ro = _probe.currentContext?.findRenderObject();
    return ro is _RenderProbe && ro.hitsOwnCentre(_viewId);
  }

  @override
  Widget build(BuildContext context) => _Probe(key: _probe, child: widget.child);
}

/// Answers "would a tap on my centre reach me?": false when a dialog, sheet
/// barrier or another page sits on top, or the page is off screen.
class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderProbe();
}

class _RenderProbe extends RenderProxyBox {
  bool _probing = false;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // While probing, claim the whole box (children don't matter: only
    // whether anything above us took the hit first).
    if (_probing) {
      if (!size.contains(position)) return false;
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return super.hitTest(result, position: position);
  }

  bool hitsOwnCentre(int? viewId) {
    if (!attached || !hasSize || size.isEmpty || viewId == null) return false;
    final Offset centre;
    try {
      centre = localToGlobal(size.center(Offset.zero));
    } catch (_) {
      return false;
    }
    final result = HitTestResult();
    _probing = true;
    try {
      WidgetsBinding.instance.hitTestInView(result, centre, viewId);
    } finally {
      _probing = false;
    }
    for (final e in result.path) {
      if (identical(e.target, this)) return true;
    }
    return false;
  }
}
