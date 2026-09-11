import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/domain/profile.dart';
import '../../events/domain/event.dart';
import '../domain/club.dart';
import 'social_repository.dart';

const _clubSelect = '*, members:club_members(count)';

/// Clubs, places, car mods (build timeline).
class CommunityRepository {
  CommunityRepository(this._client);
  final SupabaseClient _client;

  // ---------------------------------------------------------------- clubs ---

  Future<List<Club>> clubs({String? query, int limit = 50}) async {
    var q = _client.from('clubs').select(_clubSelect);
    final s = query?.trim().replaceAll('%', '') ?? '';
    if (s.isNotEmpty) q = q.or('name.ilike.%$s%,handle.ilike.%$s%');
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return rows.map(Club.fromMap).toList();
  }

  Future<Club?> club(String id) async {
    final row = await _client.from('clubs').select(_clubSelect).eq('id', id).maybeSingle();
    return row == null ? null : Club.fromMap(row);
  }

  Future<List<Club>> myClubs(String me) async {
    final rows = await _client.from('club_members').select('clubs($_clubSelect)').eq('user_id', me);
    return rows.map((r) => r['clubs']).whereType<Map<String, dynamic>>().map(Club.fromMap).toList();
  }

  Future<bool> isMember(String clubId, String me) async {
    final row = await _client.from('club_members').select('user_id').eq('club_id', clubId).eq('user_id', me).maybeSingle();
    return row != null;
  }

  Future<List<Profile>> clubMembers(String clubId) async {
    final rows = await _client.from('club_members').select('role, profiles($profileCols)').eq('club_id', clubId).order('created_at').limit(200);
    return rows.map((r) => r['profiles']).whereType<Map<String, dynamic>>().map(Profile.fromMap).toList();
  }

  Future<Club> createClub({required String ownerId, required String name, required String handle, String? description, String? homeState, String? avatarUrl}) async {
    final row = await _client
        .from('clubs')
        .insert({
          'owner_id': ownerId,
          'name': name.trim(),
          'handle': handle.trim().toLowerCase(),
          'description': ?description?.trim(),
          'home_state': ?homeState,
          'avatar_url': ?avatarUrl,
        })
        .select(_clubSelect)
        .single();
    await _client.from('club_members').upsert({'club_id': row['id'], 'user_id': ownerId, 'role': 'owner'});
    return Club.fromMap(row);
  }

  Future<void> joinClub(String clubId, String me) => _client.from('club_members').upsert({'club_id': clubId, 'user_id': me});
  Future<void> leaveClub(String clubId, String me) => _client.from('club_members').delete().eq('club_id', clubId).eq('user_id', me);

  Future<List<Event>> clubEvents(String clubId) async {
    final rows = await _client.from('events_with_counts').select().eq('club_id', clubId).order('starts_at', ascending: false).limit(50);
    return rows.map(Event.fromMap).toList();
  }

  // --------------------------------------------------------------- places ---

  Future<Place?> place(String id) async {
    final row = await _client.from('places_with_counts').select().eq('id', id).maybeSingle();
    return row == null ? null : Place.fromMap(row);
  }

  /// Spots worth a check-in inside a box: recommended ones and anything with
  /// activity, best first.
  Future<List<Place>> spotsInBounds({required double south, required double north, required double west, required double east, int limit = 80}) async {
    final rows = await _client
        .from('places_with_counts')
        .select()
        .gt('score', 0)
        .gte('lat', south)
        .lte('lat', north)
        .gte('lng', west)
        .lte('lng', east)
        .order('score', ascending: false)
        .limit(limit);
    return rows.map(Place.fromMap).toList();
  }

  /// Top spots everywhere, for the feed tab.
  Future<List<Place>> topSpots({int limit = 40}) async {
    final rows = await _client.from('places_with_counts').select().gt('score', 0).order('score', ascending: false).limit(limit);
    return rows.map(Place.fromMap).toList();
  }

  /// Stand-alone check-in; the database enforces the 300 m rule.
  Future<({bool isNew, int total})> checkInPlace({required String placeId, required double lat, required double lng}) async {
    final v = await _client.rpc('checkin_place', params: {'p_place': placeId, 'p_lat': lat, 'p_lng': lng});
    final m = (v as Map).cast<String, dynamic>();
    return (isNew: m['new'] as bool? ?? false, total: (m['total'] as num?)?.toInt() ?? 0);
  }

  Future<bool> myPlaceCheckinToday(String placeId) async {
    final v = await _client.rpc('my_place_checkin_today', params: {'p_place': placeId});
    return v as bool? ?? false;
  }

  Future<List<PlaceVisit>> placeRecentVisitors(String placeId) async {
    final rows = await _client.rpc('place_recent_visitors', params: {'p_place': placeId, 'p_limit': 12}) as List;
    final list = rows.map((r) {
      final m = (r as Map).cast<String, dynamic>();
      return PlaceVisit(
        profile: Profile(
          id: m['user_id'] as String,
          username: m['username'] as String?,
          displayName: m['display_name'] as String?,
          avatarUrl: m['avatar_url'] as String?,
          createdAt: DateTime.now(),
        ),
        at: DateTime.parse(m['at'] as String).toLocal(),
      );
    }).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  Future<void> updatePlaceDetails(String placeId, {String? coverUrl, String? description}) =>
      _client.from('places').update({'cover_url': ?coverUrl, 'description': ?description}).eq('id', placeId);

  Future<List<PlaceRegular>> placeRegulars(String placeId) async {
    final rows = await _client.rpc('place_regulars', params: {'p_place': placeId, 'p_limit': 8}) as List;
    return rows.map((r) {
      final m = (r as Map).cast<String, dynamic>();
      return PlaceRegular(
        profile: Profile(
          id: m['user_id'] as String,
          username: m['username'] as String?,
          displayName: m['display_name'] as String?,
          avatarUrl: m['avatar_url'] as String?,
          createdAt: DateTime.now(),
        ),
        visits: (m['visits'] as num).toInt(),
      );
    }).toList();
  }

  /// Weekday (0 = Sunday) -> number of meets held here.
  Future<Map<int, int>> placeBusyDays(String placeId) async {
    final rows = await _client.rpc('place_busy_days', params: {'p_place': placeId}) as List;
    return {for (final r in rows) (r['dow'] as num).toInt(): (r['meets'] as num).toInt()};
  }

  Future<List<Place>> searchPlaces(String query, {int limit = 20}) async {
    final s = query.trim().replaceAll('%', '');
    var q = _client.from('places').select();
    if (s.isNotEmpty) q = q.ilike('name', '%$s%');
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return rows.map(Place.fromMap).toList();
  }

  Future<Place> createPlace({required String me, required String name, required String kind, required double lat, required double lng}) async {
    final row = await _client.from('places').insert({'name': name.trim(), 'kind': kind, 'lat': lat, 'lng': lng, 'created_by': me}).select().single();
    return Place.fromMap(row);
  }

  Future<List<Event>> placeEvents(String placeId) async {
    final rows = await _client.from('events_with_counts').select().eq('place_id', placeId).order('starts_at', ascending: false).limit(50);
    return rows.map(Event.fromMap).toList();
  }

  // ------------------------------------------------------------- car mods ---

  Future<List<CarMod>> carMods(String carId) async {
    final rows = await _client.from('car_mods').select().eq('car_id', carId).order('done_on', ascending: false);
    return rows.map(CarMod.fromMap).toList();
  }

  Future<CarMod> addMod({required String carId, required String title, String? description, double? cost, required DateTime doneOn, required List<String> photoUrls}) async {
    final row = await _client
        .from('car_mods')
        .insert({
          'car_id': carId,
          'title': title.trim(),
          'description': ?description?.trim(),
          'cost': ?cost,
          'done_on': doneOn.toIso8601String().substring(0, 10),
          'photo_urls': photoUrls,
        })
        .select()
        .single();
    return CarMod.fromMap(row);
  }

  Future<void> deleteMod(String id) => _client.from('car_mods').delete().eq('id', id);

  Future<void> setShowSpend(String carId, bool show) => _client.from('cars').update({'show_spend': show}).eq('id', carId);

  Future<String> uploadPhoto({required String userId, required Uint8List bytes, String folder = 'mods'}) async {
    final path = '$userId/$folder/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _client.storage.from('post-photos').uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    return _client.storage.from('post-photos').getPublicUrl(path);
  }
}

final communityRepositoryProvider = Provider<CommunityRepository>((ref) => CommunityRepository(ref.watch(supabaseProvider)));
