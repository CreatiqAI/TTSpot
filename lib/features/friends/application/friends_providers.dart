import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../../core/location/live_position.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../auth/domain/profile.dart';
import '../../events/application/event_providers.dart';
import '../../safety/data/safety_repository.dart';
import '../../social/application/notification_providers.dart';
import '../data/friends_repository.dart';
import '../domain/friend.dart';
import '../domain/pin_refresh.dart';
import '../domain/presence.dart';

// ----------------------------------------------------------------- friends ---

final friendsProvider = FutureProvider<List<Profile>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final list = await ref.watch(friendsRepositoryProvider).friends(me);
  return list.where((p) => !blocked.contains(p.id)).toList();
});

final friendRequestsProvider = FutureProvider<List<FriendRequest>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  return ref.watch(friendsRepositoryProvider).incomingRequests(me);
});

final outgoingRequestIdsProvider = FutureProvider<Set<String>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const {};
  return ref.watch(friendsRepositoryProvider).outgoingRequestIds(me);
});

final friendshipStatusProvider = FutureProvider.family<FriendshipStatus, String>((ref, userId) {
  return ref.watch(friendsRepositoryProvider).status(userId);
});

final friendCountProvider = FutureProvider.family<int, String>((ref, userId) {
  return ref.watch(friendsRepositoryProvider).friendCount(userId);
});

/// Set of my friends' ids, for quick "is this a friend" checks.
final friendSuggestionsProvider = FutureProvider<List<FriendSuggestion>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  return ref.watch(friendsRepositoryProvider).suggestions();
});

/// Colours I assigned to friends on the map (friend id -> key).
class FriendTagsNotifier extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() async {
    final me = ref.watch(currentUserIdProvider);
    if (me == null) return const {};
    return ref.watch(friendsRepositoryProvider).friendTags(me);
  }

  /// Give [userId] the colour [color] (null = back to the default). The map
  /// and the lists change at once; the save follows, and only a failed save
  /// puts that friend's old colour back (and rethrows).
  Future<void> set(String userId, String? color) async {
    final me = ref.read(currentUserIdProvider);
    if (me == null) return;
    final before = state.value ?? const <String, String>{};
    final old = before[userId];
    if (old == color) return;
    state = AsyncData(_with(before, userId, color));
    try {
      await ref.read(friendsRepositoryProvider).setFriendTag(me, userId, color);
    } catch (_) {
      // Another friend's colour may have changed meanwhile: undo only this one.
      state = AsyncData(_with(state.value ?? before, userId, old));
      rethrow;
    }
  }

  static Map<String, String> _with(Map<String, String> m, String userId, String? color) {
    final next = {...m};
    if (color == null) {
      next.remove(userId);
    } else {
      next[userId] = color;
    }
    return next;
  }
}

final friendTagsProvider = AsyncNotifierProvider<FriendTagsNotifier, Map<String, String>>(FriendTagsNotifier.new);

final friendIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(friendsProvider).value?.map((p) => p.id).toSet() ?? const {};
});

class FriendActions {
  FriendActions(this._ref);
  final Ref _ref;

  FriendsRepository get _repo => _ref.read(friendsRepositoryProvider);

  /// Optimistic: see [FriendTagsNotifier.set].
  Future<void> setTag(String userId, String? color) => _ref.read(friendTagsProvider.notifier).set(userId, color);

  Future<FriendshipStatus> add(String userId) async {
    final s = await _repo.sendRequest(userId);
    _refresh(userId);
    return s;
  }

  Future<void> accept(String userId) async {
    await _repo.respond(userId, accept: true);
    _refresh(userId);
  }

  Future<void> decline(String userId) async {
    await _repo.respond(userId, accept: false);
    _refresh(userId);
  }

  Future<void> remove(String userId) async {
    await _repo.remove(userId);
    _refresh(userId);
  }

  void _refresh(String userId) {
    _ref.invalidate(friendsProvider);
    _ref.invalidate(friendRequestsProvider);
    _ref.invalidate(outgoingRequestIdsProvider);
    _ref.invalidate(friendSuggestionsProvider);
    _ref.invalidate(friendshipStatusProvider(userId));
    _ref.invalidate(friendCountProvider(userId));
    _ref.invalidate(friendPinsProvider);
    _ref.invalidate(notificationsProvider);
    final me = _ref.read(currentUserIdProvider);
    if (me != null) _ref.invalidate(friendCountProvider(me));
  }
}

final friendActionsProvider = Provider<FriendActions>((ref) => FriendActions(ref));

// --------------------------------------------------------------- live pins ---

/// Friends on the map: everyone whose position is under a day old
/// ([kShowWindow]). Only those under a minute old are live ([FriendPin.isLive]).
/// Realtime changes move pins straight from the payload; the list is fetched
/// only when names may have changed, at most once per [kPinFetchGap]
/// (pin_refresh.dart). Also fetched every minute while the app is open, so
/// "5 min ago" labels stay honest and strangers (no realtime) update; not in
/// the background, and once on coming back.
final friendPinsProvider = StreamProvider<List<FriendPin>>((ref) {
  final me = ref.watch(currentUserIdProvider);
  final repo = ref.watch(friendsRepositoryProvider);
  if (me == null) {
    final controller = StreamController<List<FriendPin>>();
    controller.add(const []);
    ref.onDispose(controller.close);
    return controller.stream;
  }
  final feed = _PinsFeed(ref, repo, me);
  ref.onDispose(feed.dispose);
  return feed.start();
});

/// The state behind [friendPinsProvider], in fields rather than captured
/// locals (the release compiler lesson from 0.3.49).
class _PinsFeed {
  _PinsFeed(this._ref, this._repo, this._me);

  final Ref _ref;
  final FriendsRepository _repo;
  final String _me;
  final _controller = StreamController<List<FriendPin>>();
  late final PinRefresher _refresher = PinRefresher(fetch: _load);

  /// The list last sent, newest first.
  List<FriendPin> _pins = const [];
  Timer? _liveEnds;
  Timer? _tick;
  RealtimeChannel? _channel;
  AppLifecycleListener? _life;
  bool _closed = false;

  Stream<List<FriendPin>> start() {
    _refresher.now();
    _channel = _repo.subscribePins(_me, _onChange);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_foreground) _refresher.request();
    });
    // Realtime is off while the app is away: catch up on coming back.
    _life = AppLifecycleListener(onResume: _refresher.request);
    return _controller.stream;
  }

  static bool get _foreground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s != AppLifecycleState.paused && s != AppLifecycleState.hidden && s != AppLifecycleState.detached;
  }

  // Sends [next] on, then sends the list again the moment the next live pin
  // turns "last seen", so "On the map now" never outlives the minute while
  // we wait for the next change.
  void _emit(List<FriendPin> next) {
    if (_closed) return;
    _pins = next;
    _controller.add(next);
    _liveEnds?.cancel();
    final left = untilLiveEnds([for (final p in next) p.updatedAt], DateTime.now());
    if (left != null) _liveEnds = Timer(left, _resend);
  }

  void _resend() => _emit([..._pins]);

  Future<void> _load() async {
    if (_closed) return;
    try {
      final blocked = _ref.read(blockedUserIdsProvider).value ?? const <String>{};
      final pins = await _repo.friendPins(_me);
      _emit([for (final p in pins) if (!blocked.contains(p.user.id) && isShownAt(p.updatedAt)) p]);
    } catch (e, st) {
      if (!_closed) _controller.addError(e, st);
    }
  }

  void _onChange(PinChange? c) {
    if (_closed) return;
    if (c == null) {
      _refresher.request();
      return;
    }
    final blocked = _ref.read(blockedUserIdsProvider).value ?? const <String>{};
    switch (pinStep(c, me: _me, held: _held(c.userId), blocked: blocked, now: DateTime.now())) {
      case PinStep.ignore:
        break;
      case PinStep.patch:
        _emit(patchPins(_pins, c));
      case PinStep.patchThenFetch:
        _emit(patchPins(_pins, c));
        _refresher.request();
      case PinStep.fetch:
        _refresher.request();
    }
  }

  FriendPin? _held(String userId) {
    for (final p in _pins) {
      if (p.user.id == userId) return p;
    }
    return null;
  }

  void dispose() {
    _closed = true;
    _refresher.dispose();
    _liveEnds?.cancel();
    _tick?.cancel();
    _life?.dispose();
    _channel?.unsubscribe();
    _controller.close();
  }
}

final myLocationProvider = FutureProvider<MyLocation>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return MyLocation.unknown;
  return ref.watch(friendsRepositoryProvider).myLocation(me);
});

/// A live meet the server noticed within 300 m that I haven't checked in to.
/// `done` is true for a moment after the one-tap check-in ("Checked in").
typedef NearbyMeet = ({String id, String title, bool done});

class NearbyMeetNotifier extends Notifier<NearbyMeet?> {
  Timer? _clear;

  @override
  NearbyMeet? build() {
    ref.onDispose(() => _clear?.cancel());
    return null;
  }

  void set(({String id, String title}) v) {
    _clear?.cancel();
    state = (id: v.id, title: v.title, done: false);
  }

  /// Flip the card to "Checked in" and take it down a few seconds later.
  void markCheckedIn() {
    final cur = state;
    if (cur == null) return;
    state = (id: cur.id, title: cur.title, done: true);
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 3), () {
      if (state?.done == true) state = null;
    });
  }

  void dismiss() {
    _clear?.cancel();
    state = null;
  }
}

final nearbyMeetProvider = NotifierProvider<NearbyMeetNotifier, NearbyMeet?>(NearbyMeetNotifier.new);

/// Publishes my position while the app is in the foreground (Snapchat model:
/// no background tracking). Start it once from the shell.
class LocationPublisher extends Notifier<bool> {
  /// When the last ping went out, and when the last one that worked did.
  DateTime? _lastTry;
  DateTime? _lastOk;
  /// The fix last sent, re-sent by the heartbeat when no better one is held.
  LivePosition? _lastSentFix;
  Timer? _heartbeat;
  String? _lastCheckedIn;
  String? _lastNearbyOffered;

  @override
  bool build() {
    // Every good fix from the one live stream (core/location/live_position.dart).
    ref.listen<LivePosition?>(livePositionProvider, (_, p) {
      if (p != null && state) _onPosition(p, force: _lastTry == null);
    });
    ref.onDispose(() => _heartbeat?.cancel());
    return false; // publishing?
  }

  Future<void> start() async {
    if (state) return;
    if (ref.read(currentUserIdProvider) == null) return;
    final live = ref.read(livePositionProvider.notifier);
    await live.start();
    if (!live.running) return; // no permission yet; the gate calls start() again
    state = true;
    _heartbeat?.cancel();
    // A cheap clock check every 5 s: a ping goes out 40 to 45 s after the
    // last one that worked ([heartbeatDue]).
    _heartbeat = Timer.periodic(kHeartbeatCheck, (_) => _beat());
    final p = ref.read(livePositionProvider);
    if (p != null) _onPosition(p, force: true);
  }

  /// Friends see me as live for a minute after each ping ([kLiveWindow]),
  /// and the GPS stream only fires when I move. Standing still with the app
  /// open, re-send where I am once the last good ping is [kPresenceHeartbeat]
  /// old, so I stay live. Driving, the moves already do it and this stays
  /// quiet. Only in the foreground: a closed app must turn "last seen".
  void _beat() {
    if (!state) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    if (!heartbeatDue(now: DateTime.now(), lastOk: _lastOk, lastTry: _lastTry)) return;
    final held = ref.read(livePositionProvider);
    // The newest fix when it is good enough to share, else the one friends already see.
    final p = held != null && held.accuracyM <= 250 ? held : _lastSentFix;
    if (p != null) _onPosition(p, force: true);
  }

  Future<void> _onPosition(LivePosition p, {bool force = false}) async {
    final now = DateTime.now();
    final lastTry = _lastTry;
    if (!force && lastTry != null && now.difference(lastTry) < const Duration(seconds: 12)) return;
    // Don't tell friends I'm somewhere I'm probably not.
    if (!force && p.accuracyM > 250) return;
    _lastTry = now;
    _lastSentFix = p;
    try {
      final ping = await ref.read(friendsRepositoryProvider).updateMyLocation(
            lat: p.latLng.latitude,
            lng: p.latLng.longitude,
            heading: p.heading,
            accuracy: p.accuracyM,
          );
      // The server stamped it a moment after [now]; counting from [now]
      // keeps the next heartbeat on the early side.
      final ok = _lastOk;
      if (ok == null || now.isAfter(ok)) _lastOk = now;
      ref.invalidate(myLocationProvider);
      if (ping.checkedInEventId != null && ping.checkedInEventId != _lastCheckedIn) {
        _lastCheckedIn = ping.checkedInEventId;
        ref.invalidate(myCheckinsProvider);
        ref.invalidate(eventDetailProvider(ping.checkedInEventId!));
      }
      if (ping.nearbyEventId != null) {
        if (ping.nearbyEventId != _lastNearbyOffered) {
          _lastNearbyOffered = ping.nearbyEventId;
          ref.read(nearbyMeetProvider.notifier).set((id: ping.nearbyEventId!, title: ping.nearbyEventTitle ?? 'a meet'));
        }
      } else if (ref.read(nearbyMeetProvider)?.done != true) {
        // Not near a meet any more (or checked in). Leave a "Checked in" card
        // to clear itself.
        ref.read(nearbyMeetProvider.notifier).dismiss();
      }
    } catch (_) {
      // offline or signed out; try again on the next fix
    }
  }

  void stop() {
    _heartbeat?.cancel();
    _heartbeat = null;
    state = false;
  }

  Future<void> setShare(String mode, {int? radiusM}) async {
    try {
      await ref.read(friendsRepositoryProvider).setShare(mode, radiusM: radiusM);
      ref.invalidate(myLocationProvider);
      ref.invalidate(friendPinsProvider);
    } catch (e) {
      throw AppException(friendlyError(e));
    }
  }

  Future<void> setGhost(bool ghost) async {
    try {
      await ref.read(friendsRepositoryProvider).setGhost(ghost);
      ref.invalidate(myLocationProvider);
    } catch (e) {
      throw AppException(friendlyError(e));
    }
  }
}

final locationPublisherProvider = NotifierProvider<LocationPublisher, bool>(LocationPublisher.new);
