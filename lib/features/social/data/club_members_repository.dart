import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/club_member.dart';

/// A club's full member list for its members page: one RPC
/// (`club_members_list`, migration 0111) with each member's role, club tag
/// and default car, officers first.
class ClubMembersRepository {
  ClubMembersRepository(this._client);
  final SupabaseClient _client;

  Future<List<ClubMemberEntry>> list(String clubId) async {
    final rows = await _client.rpc('club_members_list', params: {'p_club': clubId}) as List;
    return rows.whereType<Map>().map((r) => ClubMemberEntry.fromMap(r.cast<String, dynamic>())).toList();
  }
}

final clubMembersRepositoryProvider = Provider<ClubMembersRepository>((ref) => ClubMembersRepository(ref.watch(supabaseProvider)));
