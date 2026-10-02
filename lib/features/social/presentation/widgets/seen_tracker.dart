import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Tells the feed ranking which posts really came on screen. Wrap a feed in
/// [SeenScope] and each post in [SeenMarker]: once scrolling settles, a post
/// counts when at least half of it is visible (or it fills a third of the
/// screen), once per scope until [SeenScopeState.reset]. Markers outside a
/// scope do nothing.
class SeenScope extends StatefulWidget {
  const SeenScope({super.key, required this.onSeen, required this.child});
  final ValueChanged<List<String>> onSeen;
  final Widget child;

  @override
  State<SeenScope> createState() => SeenScopeState();
}

class SeenScopeState extends State<SeenScope> {
  final _markers = <_SeenMarkerState>{};
  final _counted = <String>{};
  Timer? _settle;
  bool _onScreen = true;
  double _screen = 800;

  /// A fresh feed (pull to refresh): every post counts again.
  void reset() => _counted.clear();

  void _add(_SeenMarkerState m) {
    _markers.add(m);
    _schedule();
  }

  void _remove(_SeenMarkerState m) => _markers.remove(m);

  void _schedule() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 400), _check);
  }

  void _check() {
    // A tab in the background (Garage, another bottom tab) isn't on screen.
    if (!mounted || !_onScreen) return;
    final screen = _screen;
    final fresh = <String>[];
    for (final m in _markers) {
      final id = m.widget.postId;
      if (_counted.contains(id)) continue;
      final box = m.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize || box.size.height <= 0) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final h = box.size.height;
      final visible = math.min(top + h, screen) - math.max(top, 0.0);
      if (visible >= math.min(h * 0.5, screen / 3)) {
        _counted.add(id);
        fresh.add(id);
      }
    }
    if (fresh.isNotEmpty) widget.onSeen(fresh);
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _onScreen = TickerMode.valuesOf(context).enabled;
    _screen = MediaQuery.sizeOf(context).height;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _schedule();
        return false;
      },
      child: _SeenInherited(scope: this, child: widget.child),
    );
  }
}

class _SeenInherited extends InheritedWidget {
  const _SeenInherited({required this.scope, required super.child});
  final SeenScopeState scope;

  @override
  bool updateShouldNotify(_SeenInherited old) => old.scope != scope;
}

class SeenMarker extends StatefulWidget {
  const SeenMarker({super.key, required this.postId, required this.child});
  final String postId;
  final Widget child;

  @override
  State<SeenMarker> createState() => _SeenMarkerState();
}

class _SeenMarkerState extends State<SeenMarker> {
  SeenScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.dependOnInheritedWidgetOfExactType<_SeenInherited>()?.scope;
    if (scope == _scope) return;
    _scope?._remove(this);
    _scope = scope;
    scope?._add(this);
  }

  @override
  void dispose() {
    _scope?._remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
