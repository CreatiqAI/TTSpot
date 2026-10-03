import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../auth/domain/profile.dart';
import '../../events/domain/event.dart';
import '../data/community_repository.dart';
import '../domain/club.dart';

// ------------------------------------------------------------------ clubs ---

/// Why a club must have a logo, shown wherever one is asked for.
const kClubLogoHint = "Your logo shows on the map and on your club's events.";

final clubsProvider = FutureProvider.family<List<Club>, String>((ref, query) => ref.watch(communityRepositoryProvider).clubs(query: query));
final clubProvider = FutureProvider.family<Club?, String>((ref, id) => ref.watch(communityRepositoryProvider).club(id));
final clubMembersProvider = FutureProvider.family<List<Profile>, String>((ref, id) => ref.watch(communityRepositoryProvider).clubMembers(id));
final clubEventsProvider = FutureProvider.family<List<Event>, String>((ref, id) => ref.watch(communityRepositoryProvider).clubEvents(id));

final myClubsProvider = FutureProvider<List<Club>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  return ref.watch(communityRepositoryProvider).myClubs(me);
});

/// Pending invite for me on this club (id), or null.
final clubsOfUserProvider = FutureProvider.family<List<Club>, String>((ref, userId) => ref.watch(communityRepositoryProvider).myClubs(userId));

final myClubInviteProvider = FutureProvider.family<String?, String>((ref, clubId) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(null);
  return ref.watch(communityRepositoryProvider).myClubInvite(clubId);
});

/// Whether I share my live location with this club's members.
/// club id -> my role. Clubs I own or admin are accounts I can switch into.
final myClubRolesProvider = FutureProvider<Map<String, String>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const {});
  return ref.watch(communityRepositoryProvider).myClubRoles();
});

final clubMemberRolesProvider = FutureProvider.family<Map<String, String>, String>((ref, clubId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(communityRepositoryProvider).clubMemberRoles(clubId);
});

final myClubInviteRoleProvider = FutureProvider.family<String?, String>((ref, clubId) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(null);
  return ref.watch(communityRepositoryProvider).myClubInviteRole(clubId);
});

final myClubShareProvider = FutureProvider.family<bool, String>((ref, clubId) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(true);
  return ref.watch(communityRepositoryProvider).myClubShare(clubId);
});

final clubLeaderboardProvider = FutureProvider.family<List<ClubLeader>, String>((ref, clubId) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(communityRepositoryProvider).clubLeaderboard(clubId);
});

/// My join request on a club: 'pending' | 'declined' | null.
final myClubRequestProvider = FutureProvider.family<String?, String>((ref, clubId) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(null);
  return ref.watch(communityRepositoryProvider).myClubRequest(clubId);
});

/// Pending requests on a club (empty unless I am owner / admin).
final clubJoinRequestsProvider = FutureProvider.family<List<ClubJoinRequest>, String>((ref, clubId) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(communityRepositoryProvider).clubJoinRequests(clubId);
});

final isClubMemberProvider = FutureProvider.family<bool, String>((ref, clubId) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return false;
  return ref.watch(communityRepositoryProvider).isMember(clubId, me);
});

// ----------------------------------------------------------------- places ---

final placeProvider = FutureProvider.family<Place?, String>((ref, id) => ref.watch(communityRepositoryProvider).place(id));
final placeEventsProvider = FutureProvider.family<List<Event>, String>((ref, id) => ref.watch(communityRepositoryProvider).placeEvents(id));
final placeSearchProvider = FutureProvider.family<List<Place>, String>((ref, q) => ref.watch(communityRepositoryProvider).searchPlaces(q));
final placeRegularsProvider = FutureProvider.family<List<PlaceRegular>, String>((ref, id) => ref.watch(communityRepositoryProvider).placeRegulars(id));
final placeRecentVisitorsProvider = FutureProvider.family<List<PlaceVisit>, String>((ref, id) => ref.watch(communityRepositoryProvider).placeRecentVisitors(id));
final myPlaceCheckinTodayProvider = FutureProvider.family<bool, String>((ref, id) => ref.watch(communityRepositoryProvider).myPlaceCheckinToday(id));
final topSpotsProvider = FutureProvider<List<Place>>((ref) => ref.watch(communityRepositoryProvider).topSpots());
final placeBusyDaysProvider = FutureProvider.family<Map<int, int>, String>((ref, id) => ref.watch(communityRepositoryProvider).placeBusyDays(id));

/// My saved spots, newest first, wherever they are. Empty when signed out,
/// and (quietly) before the saved-spots migration has landed.
final savedPlacesProvider = FutureProvider<List<Place>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  try {
    return await ref.watch(communityRepositoryProvider).mySavedPlaces();
  } on PostgrestException catch (e) {
    if (e.code == 'PGRST202' || e.code == '42883') return const []; // function not deployed yet
    rethrow;
  }
});

/// Ids of my saved spots, for bookmark toggles and the map's saved mark.
final savedPlaceIdsProvider = Provider<Set<String>>((ref) => {for (final p in ref.watch(savedPlacesProvider).value ?? const <Place>[]) p.id});

class CommunityActions {
  CommunityActions(this._ref);
  final Ref _ref;

  String get _me {
    final id = _ref.read(currentUserIdProvider);
    if (id == null) throw const AppException('You\'re signed out. Sign in again.');
    return id;
  }

  CommunityRepository get _repo => _ref.read(communityRepositoryProvider);

  /// A club needs a logo (owner's rule; the database refuses one without):
  /// a new photo in [avatar], or [avatarUrl] when the logo is already
  /// uploaded (the one sent with the club application).
  /// [isPublic]: anyone can join right away (the default); off = people ask
  /// to join and the officers approve.
  Future<Club> createClub({required String name, required String handle, String? description, String? homeState, XFile? avatar, String? avatarUrl, bool isPublic = true}) async {
    if (avatar == null && (avatarUrl ?? '').trim().isEmpty) throw const AppException(kClubLogoHint);
    if (name.trim().length < 2) throw const AppException('Give the club a name.');
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(handle.trim().toLowerCase())) {
      throw const AppException('Handle: 3–24 characters, letters, numbers or _ only.');
    }
    if (avatar != null) {
      avatarUrl = await _repo.uploadPhoto(userId: _me, bytes: await avatar.readAsBytes(), folder: 'clubs', thumb: false);
    }
    final club = await _repo.createClub(ownerId: _me, name: name, handle: handle, description: description, homeState: homeState, avatarUrl: avatarUrl, joinPolicy: isPublic ? 'public' : 'private');
    _ref.invalidate(clubsProvider(''));
    _ref.invalidate(myClubsProvider);
    return club;
  }

  Future<void> inviteToClub(String clubId, String userId, {String role = 'member'}) => _repo.inviteToClub(clubId, userId, role: role);

  /// New logo for a club I help run (owner, VP or secretary). Logos can be
  /// changed, never removed.
  Future<void> setClubLogo(String clubId, XFile logo) async {
    final url = await _repo.uploadPhoto(userId: _me, bytes: await logo.readAsBytes(), folder: 'clubs', thumb: false);
    await _repo.setClubLogo(clubId, url);
    _ref.invalidate(clubProvider(clubId));
    _ref.invalidate(myClubsProvider);
    _ref.invalidate(clubsProvider(''));
  }

  Future<void> requestOfficialClub(String clubId) async {
    await _repo.requestOfficialClub(clubId);
    _ref.invalidate(clubProvider(clubId));
  }

  Future<void> setClubGarage(String clubId, String name, double lat, double lng) async {
    await _repo.setClubGarage(clubId, name, lat, lng);
    _ref.invalidate(clubProvider(clubId));
  }

  /// Public club or private (ask to join). President, VP or secretary.
  Future<void> setClubJoinPolicy(String clubId, {required bool isPublic}) async {
    await _repo.setClubJoinPolicy(clubId, isPublic ? 'public' : 'private');
    _ref.invalidate(clubProvider(clubId));
    _ref.invalidate(clubJoinRequestsProvider(clubId));
    _ref.invalidate(clubsProvider(''));
    _ref.invalidate(myClubsProvider);
  }

  /// Join a public club right away. False when I was already in.
  Future<bool> joinClub(String clubId) async {
    try {
      return await _repo.joinClub(clubId);
    } finally {
      // Refresh either way: on a refusal the club may have just gone private.
      _membershipChanged(clubId);
    }
  }

  void _membershipChanged(String clubId) {
    _ref.invalidate(isClubMemberProvider(clubId));
    _ref.invalidate(clubProvider(clubId));
    _ref.invalidate(clubMembersProvider(clubId));
    _ref.invalidate(clubMemberRolesProvider(clubId));
    _ref.invalidate(myClubRequestProvider(clubId));
    _ref.invalidate(myClubInviteProvider(clubId));
    _ref.invalidate(myClubInviteRoleProvider(clubId));
    _ref.invalidate(myClubShareProvider(clubId));
    _ref.invalidate(clubLeaderboardProvider(clubId));
    _ref.invalidate(myClubsProvider);
    _ref.invalidate(myClubRolesProvider);
    _ref.invalidate(clubsProvider(''));
    final me = _ref.read(currentUserIdProvider);
    if (me != null) _ref.invalidate(clubsOfUserProvider(me));
  }

  Future<void> requestClubJoin(String clubId, String? message) async {
    await _repo.requestClubJoin(clubId, message);
    _ref.invalidate(myClubRequestProvider(clubId));
  }

  Future<void> cancelClubRequest(String clubId) async {
    await _repo.cancelClubRequest(clubId);
    _ref.invalidate(myClubRequestProvider(clubId));
  }

  Future<void> reviewClubRequest(String id, {required String clubId, required bool approve}) async {
    await _repo.reviewClubRequest(id, approve: approve);
    _ref.invalidate(clubJoinRequestsProvider(clubId));
    _ref.invalidate(clubMembersProvider(clubId));
    _ref.invalidate(clubMemberRolesProvider(clubId));
  }

  Future<void> respondClubInvite(String clubId, {required bool accept}) async {
    await _repo.respondClubInvite(clubId, accept: accept);
    _ref.invalidate(myClubInviteProvider(clubId));
    _ref.invalidate(myClubInviteRoleProvider(clubId));
    _ref.invalidate(isClubMemberProvider(clubId));
    _ref.invalidate(clubMembersProvider(clubId));
    _ref.invalidate(clubMemberRolesProvider(clubId));
    _ref.invalidate(clubProvider(clubId));
    _ref.invalidate(myClubsProvider);
    _ref.invalidate(myClubRolesProvider);
  }

  Future<void> setClubRole(String clubId, String userId, String role) async {
    await _repo.setClubRole(clubId, userId, role);
    _ref.invalidate(clubMemberRolesProvider(clubId));
  }

  Future<void> removeClubMember(String clubId, String userId) async {
    await _repo.removeClubMember(clubId, userId);
    _ref.invalidate(clubMembersProvider(clubId));
    _ref.invalidate(clubMemberRolesProvider(clubId));
    _ref.invalidate(clubProvider(clubId));
  }

  Future<void> setClubShare(String clubId, bool share) async {
    await _repo.setClubShare(clubId, share);
    _ref.invalidate(myClubShareProvider(clubId));
  }

  Future<void> toggleClubMembership(String clubId, {required bool isMember}) async {
    if (!isMember) {
      await joinClub(clubId);
      return;
    }
    await _repo.leaveClub(clubId, _me);
    _membershipChanged(clubId);
  }

  /// Check in at a spot with a fresh GPS fix (must be within 300 m).
  Future<({bool isNew, int total})> checkInAtPlace(String placeId) async {
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
    final r = await _repo.checkInPlace(placeId: placeId, lat: pos.latitude, lng: pos.longitude);
    _ref.invalidate(placeProvider(placeId));
    _ref.invalidate(placeRegularsProvider(placeId));
    _ref.invalidate(placeRecentVisitorsProvider(placeId));
    _ref.invalidate(myPlaceCheckinTodayProvider(placeId));
    _ref.invalidate(topSpotsProvider);
    return r;
  }

  /// Save or unsave a spot. True = saved now.
  Future<bool> toggleSavePlace(String placeId) async {
    final saved = await _repo.toggleSavePlace(placeId);
    _ref.invalidate(savedPlacesProvider);
    return saved;
  }

  Future<Place> createPlace({required String name, required String kind, required double lat, required double lng}) async {
    if (name.trim().length < 2) throw const AppException('Give the place a name.');
    return _repo.createPlace(me: _me, name: name, kind: kind, lat: lat, lng: lng);
  }
}

final communityActionsProvider = Provider<CommunityActions>((ref) => CommunityActions(ref));
