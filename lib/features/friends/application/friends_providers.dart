import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/live_position.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../auth/domain/profile.dart';
import '../../events/application/event_providers.dart';
import '../../safety/data/safety_repository.dart';
import '../../social/application/notification_providers.dart';
import '../data/friends_repository.dart';
import '../domain/friend.dart';
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
/// Refetches on every realtime change (debounced) and every minute.
final friendPinsProvider = StreamProvider<List<FriendPin>>((ref) {
  final me = ref.watch(currentUserIdProvider);
  final repo = ref.watch(friendsRepositoryProvider);
  final controller = StreamController<List<FriendPin>>();
  if (me == null) {
    controller.add(const []);
    ref.onDispose(controller.close);
    return controller.stream;
  }

  Timer? debounce;
  Timer? liveEnds;
  // Sends [pins] on, then sends them again the moment the next live pin
  // turns "last seen", so "On the map now" never outlives the minute while
  // we wait for the next fetch.
  void emit(List<FriendPin> pins) {
    if (controller.isClosed) return;
    controller.add(pins);
    liveEnds?.cancel();
    final left = untilLiveEnds([for (final p in pins) p.updatedAt], DateTime.now());
    if (left != null) liveEnds = Timer(left, () => emit([...pins]));
  }

  Future<void> load() async {
    try {
      final blocked = ref.read(blockedUserIdsProvider).value ?? const <String>{};
      final pins = await repo.friendPins(me);
      emit([for (final p in pins) if (!blocked.contains(p.user.id) && isShownAt(p.updatedAt)) p]);
    } catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    }
  }

  load();
  final channel = repo.subscribePins(me, () {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 600), load);
  });
  // Also refresh every minute so "5 min ago" labels stay honest.
  final tick = Timer.periodic(const Duration(minutes: 1), (_) => load());

  ref.onDispose(() {
    debounce?.cancel();
    liveEnds?.cancel();
    tick.cancel();
    channel.unsubscribe();
    controller.close();
  });
  return controller.stream;
});

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
  DateTime? _lastSent;
  /// The fix last sent, re-sent by the heartbeat when no better one is held.
  LivePosition? _lastSentFix;
  Timer? _heartbeat;
  String? _lastCheckedIn;
  String? _lastNearbyOffered;

  @override
  bool build() {
    // Every good fix from the one live stream (core/location/live_position.dart).
    ref.listen<LivePosition?>(livePositionProvider, (_, p) {
      if (p != null && state) _onPosition(p, force: _lastSent == null);
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
    // A cheap clock check every 5 s: a ping goes out 30 to 35 s after the last.
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) => _beat());
    final p = ref.read(livePositionProvider);
    if (p != null) _onPosition(p, force: true);
  }

  /// Friends see me as live for a minute after each ping ([kLiveWindow]),
  /// and the GPS stream only fires when I move. Standing still with the app
  /// open, re-send where I am every [kPresenceHeartbeat] so I stay live.
  /// Only in the foreground: a closed app must turn "last seen".
  void _beat() {
    final last = _lastSent;
    if (!state || last == null) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    if (DateTime.now().difference(last) < kPresenceHeartbeat) return;
    final held = ref.read(livePositionProvider);
    // The newest fix when it is good enough to share, else the one friends already see.
    final p = held != null && held.accuracyM <= 250 ? held : _lastSentFix;
    if (p != null) _onPosition(p, force: true);
  }

  Future<void> _onPosition(LivePosition p, {bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastSent != null && now.difference(_lastSent!) < const Duration(seconds: 12)) return;
    // Don't tell friends I'm somewhere I'm probably not.
    if (!force && p.accuracyM > 250) return;
    _lastSent = now;
    _lastSentFix = p;
    try {
      final ping = await ref.read(friendsRepositoryProvider).updateMyLocation(
            lat: p.latLng.latitude,
            lng: p.latLng.longitude,
            heading: p.heading,
            accuracy: p.accuracyM,
          );
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
