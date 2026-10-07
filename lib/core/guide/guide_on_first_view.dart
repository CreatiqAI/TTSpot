import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'guide.dart';

/// Wraps a page: once [ready] is true (data loaded) and the page is on top,
/// waits a beat and shows the guide from [build] if it hasn't been seen.
/// [build] runs at show time, so it can read current state (e.g. skip a step).
/// Scaffold stub: the engine track implements it, keeping this API.
class GuideOnFirstView extends ConsumerStatefulWidget {
  const GuideOnFirstView({super.key, required this.id, required this.build, required this.child, this.ready = true, this.delay = const Duration(milliseconds: 700), this.onDone});

  /// One of [GuideIds]; checked before [build] runs.
  final String id;
  final Guide Function() build;
  final Widget child;
  final bool ready;
  final Duration delay;

  /// After the guide ends (not when it wasn't shown).
  final void Function(GuideResult result)? onDone;

  @override
  ConsumerState<GuideOnFirstView> createState() => _GuideOnFirstViewState();
}

class _GuideOnFirstViewState extends ConsumerState<GuideOnFirstView> {
  @override
  Widget build(BuildContext context) => widget.child;
}
