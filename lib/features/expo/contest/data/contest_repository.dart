import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../domain/contest.dart';

/// The show car vote (migration 0123).
class ContestRepository {
  ContestRepository(this._client);
  final SupabaseClient _client;

  Map<String, dynamic> _map(Object? v) => (v as Map).cast<String, dynamic>();

  /// The vote to show for an event: the newest open one, else the newest
  /// closed one. Null when there is none (or all were cancelled).
  Future<String?> currentContestId(String eventId) async {
    final rows = await _client
        .from('event_contests')
        .select('id, status, created_at')
        .eq('event_id', eventId)
        .neq('status', 'cancelled')
        .order('created_at', ascending: false)
        .limit(20);
    if (rows.isEmpty) return null;
    final open = rows.where((r) => r['status'] == 'open').firstOrNull;
    return (open ?? rows.first)['id'] as String;
  }

  Future<ContestBoard> board(String contestId) async =>
      ContestBoard.fromMap(_map(await _client.rpc('contest_board', params: {'p_contest': contestId})));

  Future<ContestEntryInfo> entryInfo(String entryId) async =>
      ContestEntryInfo.fromMap(_map(await _client.rpc('contest_entry_info', params: {'p_entry': entryId})));

  Future<String> create({required String eventId, required String title, String? about, DateTime? opensAt, DateTime? closesAt, required bool membersEnter}) async =>
      await _client.rpc('create_contest', params: {
        'p_event': eventId,
        'p_title': title,
        'p_about': about,
        'p_opens_at': opensAt?.toUtc().toIso8601String(),
        'p_closes_at': closesAt?.toUtc().toIso8601String(),
        'p_members_enter': membersEnter,
      }) as String;

  Future<void> update({required String contestId, required String title, String? about, DateTime? opensAt, DateTime? closesAt, required bool membersEnter}) =>
      _client.rpc('update_contest', params: {
        'p_contest': contestId,
        'p_title': title,
        'p_about': about,
        'p_opens_at': opensAt?.toUtc().toIso8601String(),
        'p_closes_at': closesAt?.toUtc().toIso8601String(),
        'p_members_enter': membersEnter,
      });

  Future<void> close(String contestId) => _client.rpc('close_contest', params: {'p_contest': contestId});
  Future<void> cancel(String contestId) => _client.rpc('cancel_contest', params: {'p_contest': contestId});

  Future<void> enter(String contestId, String carId) => _client.rpc('enter_contest', params: {'p_contest': contestId, 'p_car': carId});

  Future<void> withdraw(String entryId) => _client.rpc('withdraw_contest_entry', params: {'p_entry': entryId});

  /// Returns the number given, or null on a reject.
  Future<int?> review(String entryId, {required bool approve}) async {
    final v = _map(await _client.rpc('review_contest_entry', params: {'p_entry': entryId, 'p_approve': approve}));
    return (v['number'] as num?)?.toInt();
  }

  Future<int?> hostAdd(String contestId, String username, {String? carId}) async {
    final v = _map(await _client.rpc('host_add_contest_entry', params: {'p_contest': contestId, 'p_username': username, 'p_car': carId}));
    return (v['number'] as num?)?.toInt();
  }

  Future<void> vote(String entryId) => _client.rpc('cast_contest_vote', params: {'p_entry': entryId});
}

final contestRepositoryProvider = Provider<ContestRepository>((ref) => ContestRepository(ref.watch(supabaseProvider)));
