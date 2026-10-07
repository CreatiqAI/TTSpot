import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/domain/profile.dart';
import '../domain/organizer_models.dart';

/// Every organizer-tools read and write (migrations 0066 and 0067).
class OrganizerRepository {
  OrganizerRepository(this._client);
  final SupabaseClient _client;

  List<Map<String, dynamic>> _rows(Object? v) => ((v as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

  // ------------------------------------------------------------ role ---

  Future<bool> isOrganizer(String userId) async {
    final row = await _client.from('profiles').select('is_organizer').eq('id', userId).maybeSingle();
    return row?['is_organizer'] as bool? ?? false;
  }

  Future<EventRole> myEventRole(String eventId) async {
    final v = await _client.rpc('my_event_role', params: {'p_event': eventId});
    return EventRole.fromMap(v == null ? null : (v as Map).cast<String, dynamic>());
  }

  Future<String> applyOrganizer({required String name, String? links, String? size, String? description}) async =>
      await _client.rpc('apply_organizer', params: {'p_name': name, 'p_links': links, 'p_size': size, 'p_description': description}) as String;

  // ------------------------------------------------------------ crew ---

  Future<List<CrewMember>> crew(String eventId) async =>
      _rows(await _client.rpc('event_crew_list', params: {'p_event': eventId})).map(CrewMember.fromMap).toList();

  Future<void> setCrew(String eventId, String userId, String role) =>
      _client.rpc('event_crew_set', params: {'p_event': eventId, 'p_user': userId, 'p_role': role});

  Future<void> removeCrew(String eventId, String userId) =>
      _client.rpc('event_crew_remove', params: {'p_event': eventId, 'p_user': userId});

  /// Members whose @handle starts with [q].
  Future<List<Profile>> searchUsers(String q) async {
    final t = q.trim().replaceAll('@', '').replaceAll('%', '').replaceAll('_', r'\_');
    if (t.length < 2) return const [];
    final rows = await _client
        .from('profiles')
        .select('id, username, display_name, avatar_url, created_at')
        .ilike('username', '$t%')
        .not('username', 'is', null)
        .limit(20);
    return rows.map(Profile.fromMap).toList();
  }

  // --------------------------------------------------- announcements ---

  Future<List<EventAnnouncement>> announcements(String eventId) async =>
      _rows(await _client.rpc('event_announcement_list', params: {'p_event': eventId})).map(EventAnnouncement.fromMap).toList();

  Future<int> audienceCount(String eventId, Audience audience) async =>
      ((await _client.rpc('announcement_audience_count', params: {'p_event': eventId, 'p_audience': audience.db})) as num?)?.toInt() ?? 0;

  Future<String> createAnnouncement({required String eventId, required String title, required String body, required Audience audience, DateTime? sendAt}) async =>
      await _client.rpc('create_event_announcement', params: {
        'p_event': eventId,
        'p_title': title,
        'p_body': body,
        'p_audience': audience.db,
        'p_send_at': sendAt?.toUtc().toIso8601String(),
      }) as String;

  Future<void> cancelAnnouncement(String id) => _client.rpc('cancel_event_announcement', params: {'p_id': id});

  // ------------------------------------------------------ lucky draw ---

  Future<List<LuckyDraw>> draws(String eventId) async {
    final rows = await _client.from('lucky_draws').select('*, lucky_draw_prizes(*)').eq('event_id', eventId).order('draw_at');
    return rows.map(LuckyDraw.fromMap).toList();
  }

  Future<LuckyDraw?> draw(String drawId) async {
    final row = await _client.from('lucky_draws').select('*, lucky_draw_prizes(*)').eq('id', drawId).maybeSingle();
    return row == null ? null : LuckyDraw.fromMap(row);
  }

  Future<String> saveDraw({
    required String eventId,
    String? drawId,
    required String title,
    required DateTime drawAt,
    DateTime? cutoffAt,
    required bool mustBePresent,
    required int claimMinutes,
    required List<DrawPrize> prizes,
    int? presenceMinutes,
  }) async =>
      await _client.rpc('save_lucky_draw', params: {
        'p_event': eventId,
        'p_draw': drawId,
        'p_title': title,
        'p_draw_at': drawAt.toUtc().toIso8601String(),
        'p_cutoff_at': cutoffAt?.toUtc().toIso8601String(),
        'p_must_be_present': mustBePresent,
        'p_claim_minutes': claimMinutes,
        'p_prizes': prizes.map((p) => p.toJson()).toList(),
        'p_presence_minutes': presenceMinutes,
      }) as String;

  Future<void> cancelDraw(String drawId) => _client.rpc('cancel_draw', params: {'p_draw': drawId});

  Future<void> runDraw(String drawId) => _client.rpc('run_lucky_draw', params: {'p_draw': drawId});

  Future<void> forfeitWinner(String winnerId) => _client.rpc('forfeit_draw_winner', params: {'p_winner': winnerId});

  Future<List<MyDraw>> myDrawStatus(String eventId) async =>
      _rows(await _client.rpc('my_draw_status', params: {'p_event': eventId})).map(MyDraw.fromMap).toList();

  Future<List<DrawResult>> results(String drawId) async =>
      _rows(await _client.rpc('draw_results', params: {'p_draw': drawId})).map(DrawResult.fromMap).toList();

  Future<DrawStage> stage(String drawId) async =>
      DrawStage.fromMap(((await _client.rpc('draw_stage', params: {'p_draw': drawId})) as Map).cast<String, dynamic>());

  /// Roll call: "I'm here". Returns how far from the event pin I am (metres).
  Future<int?> confirmPresence({required String drawId, required double lat, required double lng}) async {
    final r = await _client.rpc('confirm_draw_presence', params: {'p_draw': drawId, 'p_lat': lat, 'p_lng': lng});
    return ((r as Map?)?['distance_m'] as num?)?.toInt();
  }

  /// Crew: how many confirmed so far in a draw's roll call.
  Future<int> presenceCount(String drawId) async => ((await _client.rpc('draw_presence_count', params: {'p_draw': drawId})) as num?)?.toInt() ?? 0;

  Future<PrizeClaimResult> claimPrize(String code) async =>
      PrizeClaimResult.fromMap(((await _client.rpc('claim_prize', params: {'p_claim_code': code})) as Map).cast<String, dynamic>());
}

final organizerRepositoryProvider = Provider<OrganizerRepository>((ref) => OrganizerRepository(ref.watch(supabaseProvider)));
