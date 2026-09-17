import 'dart:async';

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
final friendTagsProvider = FutureProvider<Map<String, String>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const {};
  return ref.watch(friendsRepositoryProvider).friendTags(me);
});

final friendIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(friendsProvider).value?.map((p) => p.id).toSet() ?? const {};
});

class FriendActions {
  FriendActions(this._ref);
  final Ref _ref;

  FriendsRepository get _repo => _ref.read(friendsRepositoryProvider);

  Future<void> setTag(String userId, String? color) async {
    final me = _ref.read(currentUserIdProvider);
    if (me == null) return;
    await _repo.setFriendTag(me, userId, color);
    _ref.invalidate(friendTagsProvider);
  }

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

/// Friends on the map. Refetches on every realtime change (debounced).
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
  Future<void> load() async {
    try {
      final blocked = ref.read(blockedUserIdsProvider).value ?? const <String>{};
      final pins = await repo.friendPins(me);
      if (!controller.isClosed) controller.add(pins.where((p) => !blocked.contains(p.user.id)).toList());
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

/// A live meet the server noticed next to me that I haven't checked in to.
class NearbyMeetNotifier extends Notifier<({String id, String title})?> {
  @override
  ({String id, String title})? build() => null;
  void set(({String id, String title})? v) => state = v;
  void dismiss() => state = null;
}

final nearbyMeetProvider = NotifierProvider<NearbyMeetNotifier, ({String id, String title})?>(NearbyMeetNotifier.new);

/// Publishes my position while the app is in the foreground (Snapchat model:
/// no background tracking). Start it once from the shell.
class LocationPublisher extends Notifier<bool> {
  DateTime? _lastSent;
  String? _lastCheckedIn;
  String? _lastNearbyOffered;

  @override
  bool build() {
    // Every good fix from the one live stream (core/location/live_position.dart).
    ref.listen<LivePosition?>(livePositionProvider, (_, p) {
      if (p != null && state) _onPosition(p, force: _lastSent == null);
    });
    return false; // publishing?
  }

  Future<void> start() async {
    if (state) return;
    if (ref.read(currentUserIdProvider) == null) return;
    final live = ref.read(livePositionProvider.notifier);
    await live.start();
    if (!live.running) return; // no permission yet; the gate calls start() again
    state = true;
    final p = ref.read(livePositionProvider);
    if (p != null) _onPosition(p, force: true);
  }

  Future<void> _onPosition(LivePosition p, {bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastSent != null && now.difference(_lastSent!) < const Duration(seconds: 12)) return;
    // Don't tell friends I'm somewhere I'm probably not.
    if (!force && p.accuracyM > 250) return;
    _lastSent = now;
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
      } else {
        ref.read(nearbyMeetProvider.notifier).dismiss();
      }
    } catch (_) {
      // offline or signed out; try again on the next fix
    }
  }

  void stop() => state = false;

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
