import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';

enum ReportTarget { event, comment, profile }

/// Reports + blocks. Blocking hides the other user's content locally
/// (every list filters against [blockedUserIdsProvider]).
class SafetyRepository {
  SafetyRepository(this._client);
  final SupabaseClient _client;

  Future<Set<String>> fetchBlockedIds(String userId) async {
    final rows = await _client.from('blocks').select('blocked_id').eq('blocker_id', userId);
    return rows.map((r) => r['blocked_id'] as String).toSet();
  }

  Future<void> block({required String blockerId, required String blockedId}) =>
      _client.from('blocks').upsert({'blocker_id': blockerId, 'blocked_id': blockedId});

  Future<void> unblock({required String blockerId, required String blockedId}) =>
      _client.from('blocks').delete().eq('blocker_id', blockerId).eq('blocked_id', blockedId);

  Future<void> report({
    required String reporterId,
    required ReportTarget target,
    required String targetId,
    required String reason,
  }) =>
      _client.from('reports').insert({
        'reporter_id': reporterId,
        'target_type': target.name,
        'target_id': targetId,
        'reason': reason.trim(),
      });
}

final safetyRepositoryProvider = Provider<SafetyRepository>(
  (ref) => SafetyRepository(ref.watch(supabaseProvider)),
);

/// Ids of users the current user has blocked. Empty when signed out.
/// Invalidate after block/unblock.
final blockedUserIdsProvider = FutureProvider<Set<String>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const {};
  return ref.watch(safetyRepositoryProvider).fetchBlockedIds(userId);
});
