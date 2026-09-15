import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

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

final friendIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(friendsProvider).value?.map((p) => p.id).toSet() ?? const {};
});

class FriendActions {
  FriendActions(this._ref);
  final Ref _ref;

  FriendsRepository get _repo => _ref.read(friendsRepositoryProvider);

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
class LocationPublisher extends Notifier<bool> with WidgetsBindingObserver {
  StreamSubscription<Position>? _sub;
  DateTime? _lastSent;
  String? _lastCheckedIn;
  String? _lastNearbyOffered;

  @override
  bool build() {
    ref.onDispose(stop);
    return false; // publishing?
  }

  Future<void> start() async {
    if (state) return;
    if (ref.read(currentUserIdProvider) == null) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      // Never prompt from here: the location gate screen asks with context.
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    } catch (_) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _listen();
    state = true;
  }

  void _listen() {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen(_onPosition, onError: (_) {});
    // First fix straight away; the stream only fires on movement.
    Geolocator.getLastKnownPosition().then((p) {
      if (p != null) _onPosition(p, force: true);
    });
  }

  Future<void> _onPosition(Position p, {bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastSent != null && now.difference(_lastSent!) < const Duration(seconds: 12)) return;
    _lastSent = now;
    try {
      final ping = await ref.read(friendsRepositoryProvider).updateMyLocation(
            lat: p.latitude,
            lng: p.longitude,
            heading: p.heading.isNaN ? null : p.heading,
            accuracy: p.accuracy.isNaN ? null : p.accuracy,
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_sub == null) _listen();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _sub?.cancel();
      _sub = null;
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    WidgetsBinding.instance.removeObserver(this);
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
