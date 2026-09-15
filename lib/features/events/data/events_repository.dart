import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/domain/profile.dart';
import '../domain/event.dart';
import '../domain/event_detail.dart';

const _profileCols = 'id, username, display_name, bio, avatar_url, home_state, created_at';

/// All `events`, `event_attendees` and `event_comments` reads and writes.
class EventsRepository {
  EventsRepository(this._client);
  final SupabaseClient _client;

  // ------------------------------------------------------------------ map ---

  /// Active events inside [bounds] starting between [from] and [to]
  /// (no upper limit when [to] is null). Uses the `events_with_counts` view.
  Future<List<Event>> fetchUpcomingInBounds({
    required LatLngBounds bounds,
    required DateTime from,
    DateTime? to,
    Set<EventType> types = const {},
    int limit = 100,
  }) async {
    var q = _client
        .from('events_with_counts')
        .select()
        .eq('status', 'active')
        .gte('starts_at', from.toUtc().toIso8601String())
        .gte('lat', bounds.southwest.latitude)
        .lte('lat', bounds.northeast.latitude)
        .gte('lng', bounds.southwest.longitude)
        .lte('lng', bounds.northeast.longitude);
    if (to != null) q = q.lte('starts_at', to.toUtc().toIso8601String());
    if (types.isNotEmpty) q = q.inFilter('event_type', types.map((t) => t.db).toList());

    final rows = await q.order('starts_at', ascending: true).limit(limit);
    return rows.map(Event.fromMap).toList();
  }

  /// Meets inside their live window right now (1 h before start until close).
  Future<List<Event>> fetchLiveInBounds({required LatLngBounds bounds, int limit = 50}) async {
    final now = DateTime.now().toUtc();
    final rows = await _client
        .from('events_with_counts')
        .select()
        .eq('status', 'active')
        .lte('starts_at', now.add(const Duration(hours: 1)).toIso8601String())
        .gte('starts_at', now.subtract(const Duration(hours: 8)).toIso8601String())
        .gte('lat', bounds.southwest.latitude)
        .lte('lat', bounds.northeast.latitude)
        .gte('lng', bounds.southwest.longitude)
        .lte('lng', bounds.northeast.longitude)
        .order('starts_at', ascending: false)
        .limit(limit);
    return rows.map(Event.fromMap).where((e) => e.isLive).toList();
  }

  // ------------------------------------------------------------ check-ins ---

  Future<Set<String>> myCheckinEventIds(String userId) async {
    final rows = await _client.from('checkins').select('event_id').eq('user_id', userId);
    return rows.map((r) => r['event_id'] as String).toSet();
  }

  Future<void> checkIn({required String eventId, required String userId, required double lat, required double lng}) =>
      _client.from('checkins').insert({'event_id': eventId, 'user_id': userId, 'lat': lat, 'lng': lng, 'source': 'manual'});

  /// People who checked in (newest first) with profiles.
  Future<List<Profile>> fetchCheckedIn(String eventId, {int limit = 30}) async {
    final rows = await _client
        .from('checkins')
        .select('user_id, checked_in_at, profiles($_profileCols)')
        .eq('event_id', eventId)
        .order('checked_in_at', ascending: false)
        .limit(limit);
    return rows.map((r) => r['profiles']).whereType<Map<String, dynamic>>().map(Profile.fromMap).toList();
  }

  Future<EventRecap> fetchRecap(String eventId) async {
    final v = await _client.rpc('event_recap', params: {'p_event': eventId});
    return EventRecap.fromMap((v as Map).cast<String, dynamic>());
  }

  /// Upcoming meets my friends RSVP'd to, with which friends.
  Future<List<({Event event, List<String> friendIds})>> fetchFriendsGoing() async {
    final rows = await _client.rpc('friends_upcoming_events') as List;
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r['event_id'] as String).toList();
    final events = await _client.from('events_with_counts').select().inFilter('id', ids).order('starts_at');
    final byId = {for (final r in rows) r['event_id'] as String: (r['friend_ids'] as List).cast<String>()};
    return events.map(Event.fromMap).map((e) => (event: e, friendIds: byId[e.id] ?? const <String>[])).toList();
  }

  // ------------------------------------------------------------ my events ---

  /// Events I organise or joined (any status, any date), newest first.
  Future<List<Event>> fetchMine(String userId) async {
    final organised = await _client.from('events_with_counts').select().eq('organizer_id', userId);
    final joinedIds = (await _client.from('event_attendees').select('event_id').eq('user_id', userId))
        .map((r) => r['event_id'] as String)
        .toList();
    final joined = joinedIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _client.from('events_with_counts').select().inFilter('id', joinedIds);

    final byId = <String, Event>{};
    for (final row in [...organised, ...joined]) {
      final e = Event.fromMap(row);
      byId[e.id] = e;
    }
    return byId.values.toList()..sort((a, b) => b.startsAt.compareTo(a.startsAt));
  }

  // -------------------------------------------------------------- details ---

  Future<Event?> fetchById(String id) async {
    final row = await _client.from('events_with_counts').select().eq('id', id).maybeSingle();
    return row == null ? null : Event.fromMap(row);
  }

  Future<EventDetail?> fetchDetail(String id, {required String? viewerId}) async {
    final event = await fetchById(id);
    if (event == null) return null;

    final results = await Future.wait<dynamic>([
      _client.from('profiles').select(_profileCols).eq('id', event.organizerId).maybeSingle(),
      _client
          .from('event_attendees')
          .select('user_id, profiles($_profileCols)')
          .eq('event_id', id)
          .order('created_at', ascending: true)
          .limit(8),
      if (viewerId != null)
        _client.from('event_attendees').select('user_id').eq('event_id', id).eq('user_id', viewerId).maybeSingle()
      else
        Future.value(null),
    ]);

    final organizerRow = results[0] as Map<String, dynamic>?;
    final attendeeRows = results[1] as List<dynamic>;
    final myRow = results[2] as Map<String, dynamic>?;

    return EventDetail(
      event: event,
      organizer: organizerRow == null ? null : Profile.fromMap(organizerRow),
      attendeesPreview: attendeeRows
          .map((r) => (r as Map<String, dynamic>)['profiles'])
          .whereType<Map<String, dynamic>>()
          .map(Profile.fromMap)
          .toList(),
      isAttending: myRow != null,
    );
  }

  /// Everyone who RSVP'd, host first.
  Future<List<Profile>> attendees(String eventId) async {
    final rows = await _client.from('event_attendees').select('created_at, profiles($_profileCols)').eq('event_id', eventId).order('created_at', ascending: true).limit(500);
    return rows.map((r) => r['profiles']).whereType<Map<String, dynamic>>().map(Profile.fromMap).toList();
  }

  // ----------------------------------------------------------------- rsvp ---

  Future<void> join({required String eventId, required String userId}) =>
      _client.from('event_attendees').insert({'event_id': eventId, 'user_id': userId});

  Future<void> leave({required String eventId, required String userId}) =>
      _client.from('event_attendees').delete().eq('event_id', eventId).eq('user_id', userId);

  Future<void> cancel(String eventId) => _client.from('events').update({'status': 'cancelled'}).eq('id', eventId);

  // --------------------------------------------------------------- create ---

  Future<Event> create({
    required String organizerId,
    required String title,
    String? description,
    required EventType type,
    String? coverUrl,
    required DateTime startsAt,
    required String venueName,
    required LatLng location,
    int? maxAttendees,
    String? clubId,
    bool friendsOnly = false,
    String? address,
  }) async {
    final row = await _client
        .from('events')
        .insert({
          'visibility': friendsOnly ? 'friends' : 'public',
          'address': ?address,
          'organizer_id': organizerId,
          'title': title.trim(),
          'description': ?description?.trim(),
          'event_type': type.db,
          'cover_url': ?coverUrl,
          'starts_at': startsAt.toUtc().toIso8601String(),
          'venue_name': venueName.trim(),
          'lat': location.latitude,
          'lng': location.longitude,
          'max_attendees': ?maxAttendees,
          'club_id': ?clubId,
        })
        .select()
        .single();
    return Event.fromMap(row);
  }

  /// Instant meet at my spot; the database pings my friends. Returns the event id.
  Future<String> ttNow({required double lat, required double lng, String? venue, String? title, int minutes = 60, List<String>? invitees, String? address}) async {
    final v = await _client.rpc('tt_now', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_venue': ?venue,
      'p_title': ?title,
      'p_minutes': minutes,
      'p_invitees': ?invitees,
      'p_address': ?address,
    });
    return v as String;
  }

  /// Uploads to `event-covers/<userId>/<millis>.jpg` and returns the public URL.
  Future<String> uploadCover({required String userId, required Uint8List bytes}) async {
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('event-covers').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return _client.storage.from('event-covers').getPublicUrl(path);
  }

  // ------------------------------------------------------------- comments ---

  Future<List<EventComment>> fetchComments(String eventId) async {
    final rows = await _client
        .from('event_comments')
        .select('*, profiles($_profileCols)')
        .eq('event_id', eventId)
        .order('created_at', ascending: true)
        .limit(200);
    return rows.map(EventComment.fromMap).toList();
  }

  Future<void> addComment({required String eventId, required String userId, required String body}) =>
      _client.from('event_comments').insert({'event_id': eventId, 'user_id': userId, 'body': body.trim()});

  Future<void> deleteComment(String commentId) => _client.from('event_comments').delete().eq('id', commentId);
}

final eventsRepositoryProvider = Provider<EventsRepository>(
  (ref) => EventsRepository(ref.watch(supabaseProvider)),
);
