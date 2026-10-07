import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'guide.dart';
import 'guide_overlay.dart';
import 'guide_store.dart';

/// Shows guides and remembers which ones were seen
/// (profiles.settings.guides_seen; switch: profiles.settings.tips).
class GuideController {
  GuideController(this._ref);
  final Ref _ref;

  GuideStore get _store => _ref.read(guideStoreProvider);

  /// Marked this session; covers the gap before the server list comes back
  /// (and a failed save).
  final _seenNow = <String>{};

  _Active? _active;

  /// Tips are on (Settings → Tips from TiTi). Default on.
  bool get enabled => _store.tipsOn;

  /// This guide was shown before (on any phone).
  bool seen(String id) => _seenNow.contains(id) || _store.seen.contains(id);

  /// A guide is on screen right now. Turns false as soon as a guide starts
  /// leaving, so the next screen's guide can start during the exit fade.
  bool get showing => _active != null;

  /// The member's settings are loaded, so [enabled] and [seen] are real.
  bool get ready => _store.loaded;

  /// Done with onboarding. Guides never show before that (unless forced).
  bool get onboarded => _store.onboarded;

  /// Shows [guide] once: only if tips are on, it wasn't seen, nothing else is
  /// showing and [context] is still mounted. Marks it seen as it starts.
  /// [force] skips the seen / tips checks (Settings → Replay, journeys).
  Future<GuideResult> showOnce(BuildContext context, Guide guide, {bool force = false}) {
    if (showing || !context.mounted || guide.steps.isEmpty) return Future.value(GuideResult.notShown);
    if (!force && (!ready || !onboarded || !enabled || seen(guide.id))) return Future.value(GuideResult.notShown);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return Future.value(GuideResult.notShown);

    unawaited(markSeen(guide.id));
    final done = Completer<GuideResult>();
    final key = GlobalKey<GuideOverlayState>();
    final active = _Active(guide.id, key);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => GuideOverlay(
        key: key,
        guide: guide,
        onEnd: (result) {
          if (identical(_active, active)) _active = null;
          if (!done.isCompleted) done.complete(result);
        },
        // Called once, after the exit animation, while the entry is still in.
        onRemove: () {
          entry.remove();
          entry.dispose();
        },
      ),
    );
    _active = active;
    overlay.insert(entry);
    return done.future;
  }

  /// The id of the guide on screen, or null.
  String? get showingId => _active?.id;

  /// Closes the guide on screen (as [GuideResult.skipped]), if any.
  void dismiss() => _active?.key.currentState?.close(GuideResult.skipped);

  Future<void> markSeen(String id) async {
    _seenNow.add(id);
    if (_store.seen.contains(id)) return;
    try {
      await _store.saveSeen({..._store.seen, ..._seenNow}.toList());
    } catch (e) {
      // Remembered for this session anyway; the next guide's save carries it.
      debugPrint('guide: could not save seen $id: $e');
    }
  }

  /// Settings → Replay tips: forget every seen guide.
  Future<void> resetAll() async {
    _seenNow.clear();
    await _store.saveSeen(const []);
  }
}

class _Active {
  _Active(this.id, this.key);
  final String id;
  final GlobalKey<GuideOverlayState> key;
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
