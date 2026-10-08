import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/data/auth_repository.dart';
import '../../settings/application/settings_providers.dart';
import '../domain/event.dart';
import 'my_events_provider.dart';

// iPhone Live Activities: a meet I'm going to on the lock screen and in the
// Dynamic Island. "Starts in 1:12:05" from 2 h before the start, then
// "Live" with the time since the start until the meet ends. The timers run
// on the phone (SwiftUI timer text), so there are no pushes and no server
// cost. Native side: ios/Runner/LiveActivityBridge.swift (channel) and
// ios/TTSpotWidgets (the views). A no-op on Android and iOS < 16.1.

/// Starts by itself from this long before the start.
const kLiveActivityLead = Duration(hours: 2);

/// How long it shows after the start when the meet has no end time.
const kLiveActivityDefaultLength = Duration(hours: 3);

/// When the activity goes: the meet's end, else [kLiveActivityDefaultLength]
/// after the start.
DateTime liveActivityEndsAt(Event e) {
  final end = e.endsAt;
  return end != null && end.isAfter(e.startsAt) ? end : e.startsAt.add(kLiveActivityDefaultLength);
}

/// Still worth showing: not cancelled and not over.
bool liveActivityAlive(Event e, DateTime now) => !e.isCancelled && now.isBefore(liveActivityEndsAt(e));

/// May start by itself: from [kLiveActivityLead] before the start until it ends.
bool liveActivityWindowOpen(Event e, DateTime now) =>
    liveActivityAlive(e, now) && !now.isBefore(e.startsAt.subtract(kLiveActivityLead));

/// The type the widget draws: TT for instant meets, Official for official clubs.
String liveActivityType(Event e) {
  if (e.isInstant) return EventType.tt.db;
  if (e.isOfficialClubEvent) return EventType.official.db;
  return e.type.db;
}

/// What [planLiveActivities] decided.
class LiveActivityPlan {
  const LiveActivityPlan({this.start = const [], this.end = const {}});

  /// Start these, or refresh them when already running (title / time edits).
  final List<Event> start;

  /// End these event ids.
  final Set<String> end;

  bool get isEmpty => start.isEmpty && end.isEmpty;
}

/// On app open / resume: keep running activities whose meet is still mine
/// and not over; end the rest (meet over, cancelled, left, or the switch is
/// off). With none left, start the soonest meet of mine inside its window
/// that was never shown before ([shown]): once swiped away on the lock
/// screen, a meet's activity stays gone. One at a time, so the lock screen
/// stays clean.
LiveActivityPlan planLiveActivities({
  required bool enabled,
  required List<Event> mine,
  required Set<String> running,
  required DateTime now,
  Set<String> shown = const {},
}) {
  if (!enabled) return LiveActivityPlan(end: running);
  final byId = {for (final e in mine) e.id: e};
  final keep = [
    for (final id in running)
      if (byId[id] case final e? when liveActivityAlive(e, now)) e,
  ];
  final end = running.difference({for (final e in keep) e.id});
  if (keep.isNotEmpty) return LiveActivityPlan(start: keep, end: end);
  final open = mine.where((e) => !shown.contains(e.id) && liveActivityWindowOpen(e, now)).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return LiveActivityPlan(start: open.take(1).toList(), end: end);
}

/// The native side. Swapped for a fake in tests.
class LiveActivityChannel {
  const LiveActivityChannel();
  static const _ch = MethodChannel('my.ttspot.app/live_activity');

  Future<bool> supported() async => await _ch.invokeMethod<bool>('supported') ?? false;

  Future<Set<String>> active() async => {...?(await _ch.invokeListMethod<String>('active'))};

  /// [badge]: a small pill next to the title, e.g. my entry number "#0427".
  Future<bool> start(Event e, {String? badge}) async =>
      await _ch.invokeMethod<bool>('start', {
        'eventId': e.id,
        'title': e.title,
        'venue': e.venueName,
        'startsAt': e.startsAt.millisecondsSinceEpoch,
        'endsAt': liveActivityEndsAt(e).millisecondsSinceEpoch,
        'type': liveActivityType(e),
        'badge': ?badge,
      }) ??
      false;

  Future<void> end(String eventId) => _ch.invokeMethod<int>('end', {'eventId': eventId});

  Future<void> endAll() => _ch.invokeMethod<int>('endAll');
}

/// How many shown event ids `profiles.settings.la_started` keeps.
const kLiveActivityShownMax = 30;

/// The `la_started` list to save: [current] plus [id] last, at most
/// [kLiveActivityShownMax] (the oldest go first).
List<String> withLiveActivityShown(List<String> current, String id) {
  final next = [...current.where((x) => x != id), id];
  return next.length > kLiveActivityShownMax ? next.sublist(next.length - kLiveActivityShownMax) : next;
}

/// Starts and ends the meet Live Activity. Every call is best effort: a
/// failure never reaches the member (the activity is a nice-to-have).
class LiveActivityService {
  LiveActivityService({
    required this.enabled,
    required this.loadMine,
    this.loadEntryNo,
    this.loadShown,
    this.markShown,
    this.channel = const LiveActivityChannel(),
    bool? platformSupported,
    DateTime Function()? clock,
  })  : _platform = platformSupported ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS),
        _now = clock ?? DateTime.now;

  /// The "Live Activities" switch in Settings.
  final bool Function() enabled;

  /// Meets I host or joined. [fresh]: refetch instead of the cached list.
  final Future<List<Event>> Function({bool fresh}) loadMine;

  /// My entry number at an event (Expo mode), null when not checked in.
  final Future<int?> Function(String eventId)? loadEntryNo;

  /// Meets whose activity was already shown on this account
  /// (`settings.la_started`). Those never start again by themselves.
  final Future<Set<String>> Function()? loadShown;

  /// Remember that [eventId]'s activity was shown.
  final Future<void> Function(String eventId)? markShown;
  final LiveActivityChannel channel;
  final bool _platform;
  final DateTime Function() _now;

  Future<void> _queue = Future.value();

  /// One call at a time (resume + join can land together).
  Future<void> _serial(Future<void> Function() job) {
    final next = _queue.then((_) => job()).catchError((Object e) {
      debugPrint('live activity: $e');
    });
    _queue = next;
    return next;
  }

  Future<bool> _ready() async => _platform && await channel.supported();

  /// App open / resume: end stale ones, refresh or start the right one.
  /// [explicit]: the member asked for it (switched Live Activities on), so a
  /// meet shown before may start again.
  Future<void> sync({bool fresh = false, bool explicit = false}) => _serial(() async {
        if (!await _ready()) return;
        final running = await channel.active();
        final on = enabled();
        // Nothing to end and the switch is off: skip the fetch.
        if (!on && running.isEmpty) return;
        final mine = on ? await loadMine(fresh: fresh) : const <Event>[];
        final shown = on && !explicit ? await _loadShown() : const <String>{};
        final plan = planLiveActivities(enabled: on, mine: mine, running: running, now: _now(), shown: shown);
        for (final id in plan.end) {
          await channel.end(id);
        }
        for (final e in plan.start) {
          await _start(e, shown: shown);
        }
      });

  /// Just joined [eventId]: show it when it starts within [kLiveActivityLead].
  Future<void> joined(String eventId) => _serial(() async {
        if (!await _ready() || !enabled()) return;
        final mine = await loadMine(fresh: true);
        final e = mine.where((e) => e.id == eventId).firstOrNull;
        if (e == null || !liveActivityWindowOpen(e, _now())) return;
        await _only(e);
      });

  /// "I'm on my way" to [e]: show it now, however early (until the meet ends).
  Future<void> onMyWay(Event e) => _serial(() async {
        if (!await _ready() || !enabled() || !liveActivityAlive(e, _now())) return;
        await _only(e);
      });

  /// Left or cancelled [eventId].
  Future<void> end(String eventId) => _serial(() async {
        if (!_platform) return;
        await channel.end(eventId);
      });

  /// Switch off, sign out, account deleted.
  Future<void> endAll() => _serial(() async {
        if (!_platform) return;
        await channel.endAll();
      });

  /// [e] on its own: others end first.
  Future<void> _only(Event e) async {
    for (final id in await channel.active()) {
      if (id != e.id) await channel.end(id);
    }
    await _start(e);
  }

  Future<Set<String>> _loadShown() async => await loadShown?.call() ?? const <String>{};

  /// Starts (or refreshes) [e] and remembers it, so a swipe-away sticks.
  Future<void> _start(Event e, {Set<String>? shown}) async {
    final ok = await channel.start(e, badge: await _badge(e));
    final mark = markShown;
    if (!ok || mark == null || (shown ?? await _loadShown()).contains(e.id)) return;
    try {
      await mark(e.id);
    } catch (err) {
      debugPrint('live activity mark: $err');
    }
  }

  /// "#0427" once I'm checked in. Only asked from the check-in window on
  /// (an hour before the start), and never fails the start.
  Future<String?> _badge(Event e) async {
    final load = loadEntryNo;
    if (load == null || _now().isBefore(e.startsAt.subtract(const Duration(hours: 1)))) return null;
    try {
      final n = await load(e.id);
      return n == null ? null : liveActivityEntryBadge(n);
    } catch (_) {
      return null;
    }
  }
}

/// The entry number pill: "#0427".
String liveActivityEntryBadge(int n) => '#${n.toString().padLeft(4, '0')}';

/// My meets, refetched at most every 15 min on resume (joins refetch at once).
const _kMineMaxAge = Duration(minutes: 15);

final liveActivityServiceProvider = Provider<LiveActivityService>((ref) {
  DateTime? fetchedAt;
  return LiveActivityService(
    enabled: () => ref.read(settingsProvider).liveActivities,
    loadMine: ({bool fresh = false}) async {
      final now = DateTime.now();
      if (fresh || fetchedAt == null || now.difference(fetchedAt!) > _kMineMaxAge) {
        ref.invalidate(myEventsProvider);
        fetchedAt = now;
      }
      final m = await ref.read(myEventsProvider.future);
      return [...m.upcoming, ...m.past];
    },
    loadShown: () async {
      // The profile first: right after launch or resume it may still be loading.
      await ref.read(currentProfileProvider.future);
      return ref.read(settingsProvider).liveActivitiesShown.toSet();
    },
    markShown: (eventId) async {
      final list = withLiveActivityShown(ref.read(settingsProvider).liveActivitiesShown, eventId);
      await ref.read(settingsActionsProvider).patch({'la_started': list});
    },
    loadEntryNo: (eventId) async {
      final me = ref.read(currentUserIdProvider);
      if (me == null) return null;
      final row = await ref.read(supabaseProvider).from('checkins').select('entry_no').eq('event_id', eventId).eq('user_id', me).maybeSingle();
      return (row?['entry_no'] as num?)?.toInt();
    },
  );
});
