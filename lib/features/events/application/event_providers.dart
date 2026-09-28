import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../map/application/map_providers.dart';
import '../../safety/data/safety_repository.dart';
import '../../auth/domain/profile.dart';
import '../data/events_repository.dart';
import '../domain/checkin_row.dart';
import '../domain/event.dart';
import '../domain/event_car.dart';
import '../domain/event_detail.dart';
import 'my_events_provider.dart';

/// Event + organizer + attendee preview + whether I'm going.
final eventDetailProvider = FutureProvider.family<EventDetail?, String>((ref, id) async {
  final viewerId = ref.watch(currentUserIdProvider);
  return ref.watch(eventsRepositoryProvider).fetchDetail(id, viewerId: viewerId);
});

/// Comments, oldest first, minus blocked authors.
final eventCommentsProvider = FutureProvider.family<List<EventComment>, String>((ref, id) async {
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final comments = await ref.watch(eventsRepositoryProvider).fetchComments(id);
  return comments.where((c) => !blocked.contains(c.userId)).toList();
});

/// Event ids I've checked in to (proven "went").
final myCheckinsProvider = FutureProvider<Set<String>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const {};
  return ref.watch(eventsRepositoryProvider).myCheckinEventIds(me);
});

final eventAttendeesProvider = FutureProvider.family<List<Profile>, String>((ref, id) => ref.watch(eventsRepositoryProvider).attendees(id));

final eventCheckedInProvider = FutureProvider.family<List<Profile>, String>((ref, id) {
  return ref.watch(eventsRepositoryProvider).fetchCheckedIn(id);
});

final eventRecapProvider = FutureProvider.family<EventRecap, String>((ref, id) {
  return ref.watch(eventsRepositoryProvider).fetchRecap(id);
});

/// The car each member is bringing to the meet, by user id (their pick, else
/// their default car). Empty when the lookup fails, so lists still render.
final eventCarsProvider = FutureProvider.family<Map<String, EventCar>, String>((ref, id) async {
  try {
    return await ref.watch(eventsRepositoryProvider).eventCars(id);
  } catch (_) {
    return const {};
  }
});

// ------------------------------------------------------- host confirmation ---

final meetModeProvider = FutureProvider.autoDispose.family<MeetMode, String>((ref, id) {
  return ref.watch(eventsRepositoryProvider).meetMode(id);
});

/// The host's "Who's here" list. On a big meet, opening it first settles
/// everyone who stayed 10+ min so the host only sees the exceptions.
final hostCheckinListProvider = FutureProvider.autoDispose.family<List<CheckinRow>, String>((ref, id) async {
  final repo = ref.watch(eventsRepositoryProvider);
  final mode = await ref.watch(meetModeProvider(id).future);
  if (mode == MeetMode.big) {
    try {
      await repo.autoConfirmStayed(id);
    } catch (_) {
      // not the host, or offline; the list still loads
    }
  }
  return repo.checkinList(id);
});

/// Upcoming meets my friends are going to.
final friendsGoingProvider = FutureProvider<List<({Event event, List<String> friendIds})>>((ref) {
  return ref.watch(eventsRepositoryProvider).fetchFriendsGoing();
});

/// Mutations for one event. Each call refreshes the providers it affects.
class EventActions {
  EventActions(this._ref);
  final Ref _ref;

  String get _me {
    final id = _ref.read(currentUserIdProvider);
    if (id == null) throw const AppException('You\'re signed out. Sign in again.');
    return id;
  }

  EventsRepository get _repo => _ref.read(eventsRepositoryProvider);

  /// [carId]: the car I'm bringing (null = my default car).
  Future<void> join(String eventId, {String? carId}) async {
    await _repo.join(eventId: eventId, userId: _me, carId: carId);
    _refresh(eventId);
  }

  /// Switch the car I'm bringing to a meet I joined / checked in at.
  Future<void> setCar(String eventId, String carId) async {
    await _repo.setEventCar(eventId: eventId, carId: carId);
    _ref.invalidate(eventCarsProvider(eventId));
    _ref.invalidate(eventRecapProvider(eventId));
    _ref.invalidate(hostCheckinListProvider(eventId));
  }

  Future<void> leave(String eventId) async {
    await _repo.leave(eventId: eventId, userId: _me);
    _refresh(eventId);
  }

  Future<bool> toggleBookmark(String eventId) async {
    final on = await _repo.toggleBookmark(eventId);
    _refresh(eventId);
    return on;
  }

  Future<void> cancel(String eventId) async {
    await _repo.cancel(eventId);
    _refresh(eventId);
  }

  Future<String> ttNow({required double lat, required double lng, String? venue, int minutes = 60, List<String>? invitees, String? address, String? carId}) async {
    final v = venue?.trim();
    final id = await _repo.ttNow(lat: lat, lng: lng, venue: v == null || v.isEmpty ? null : v, minutes: minutes, invitees: invitees, address: address, carId: carId);
    _ref.invalidate(myCheckinsProvider);
    _ref.invalidate(myEventsProvider);
    return id;
  }

  /// Check in with a fresh GPS fix. The database rejects it when too far / too early.
  /// [carId]: the car I brought (null = my RSVP car, else my default car).
  Future<void> checkIn(String eventId, {String? carId}) async {
    Position pos;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw const AppException('Turn on location to check in.');
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw const AppException('Allow location so we know you\'re really there.');
      }
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
      );
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException('Couldn\'t get your location. Try again outside.');
    }
    await _repo.checkIn(eventId: eventId, userId: _me, lat: pos.latitude, lng: pos.longitude, carId: carId);
    _ref.invalidate(myCheckinsProvider);
    _ref.invalidate(eventCarsProvider(eventId));
    _ref.invalidate(eventCheckedInProvider(eventId));
    _ref.invalidate(eventRecapProvider(eventId));
    _refresh(eventId);
  }

  /// Host: mark one arrival as here / not here.
  Future<void> hostConfirm(String eventId, String userId, {required bool confirmed}) async {
    await _repo.hostConfirm(eventId: eventId, userId: userId, confirmed: confirmed);
    _ref.invalidate(hostCheckinListProvider(eventId));
  }

  /// Host: confirm everyone still undecided. Returns how many.
  Future<int> hostConfirmAll(String eventId) async {
    final n = await _repo.hostConfirmAll(eventId);
    _ref.invalidate(hostCheckinListProvider(eventId));
    return n;
  }

  Future<void> addComment(String eventId, String body) async {
    if (body.trim().isEmpty) return;
    await _repo.addComment(eventId: eventId, userId: _me, body: body);
    _ref.invalidate(eventCommentsProvider(eventId));
  }

  Future<void> deleteComment(String eventId, String commentId) async {
    await _repo.deleteComment(commentId);
    _ref.invalidate(eventCommentsProvider(eventId));
  }

  void _refresh(String eventId) {
    _ref.invalidate(eventDetailProvider(eventId));
    _ref.invalidate(eventCarsProvider(eventId));
    _ref.invalidate(mapEventsProvider); // attendee counts on the map list
    _ref.invalidate(myEventsProvider);
  }
}

final eventActionsProvider = Provider<EventActions>((ref) => EventActions(ref));
