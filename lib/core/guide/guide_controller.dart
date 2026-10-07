import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'guide.dart';

/// Shows guides and remembers which ones were seen
/// (profiles.settings.guides_seen; switch: profiles.settings.tips).
/// Scaffold stub: the engine track replaces the body, keeping this API.
class GuideController {
  GuideController(this._ref);
  // ignore: unused_field
  final Ref _ref;

  /// Tips are on (Settings → Tips from TiTi). Default on.
  bool get enabled => true;

  /// This guide was shown before (on any phone).
  bool seen(String id) => true;

  /// A guide is on screen right now.
  bool get showing => false;

  /// Shows [guide] once: only if tips are on, it wasn't seen, nothing else is
  /// showing and [context] is still mounted. Marks it seen as it starts.
  /// [force] skips the seen / tips checks (Settings → Replay, journeys).
  Future<GuideResult> showOnce(BuildContext context, Guide guide, {bool force = false}) async => GuideResult.notShown;

  Future<void> markSeen(String id) async {}

  /// Settings → Replay tips: forget every seen guide.
  Future<void> resetAll() async {}
}

final guideControllerProvider = Provider<GuideController>((ref) => GuideController(ref));

/// A guide that spans screens (the first-box journey): which stage the member
/// is at, or null. In memory only; a journey abandoned mid-way just stops.
class GuideJourney extends Notifier<String?> {
  @override
  String? build() => null;

  void go(String? stage) => state = stage;
}

final guideJourneyProvider = NotifierProvider<GuideJourney, String?>(GuideJourney.new);
