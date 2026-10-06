import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/club_tag.dart';

/// Official club tags (migration 0109). Lists get the tag with the author
/// (`club_tag` in [authorCols]); this is for one person and for my choice.
class ClubTagRepository {
  ClubTagRepository(this._client);
  final SupabaseClient _client;

  /// The tag [userId] shows, or null.
  Future<ClubTag?> tagOf(String userId) async => ClubTag.fromJson(await _client.rpc('club_tag_of', params: {'p_user': userId}));

  /// Do I wear this club's tag?
  Future<bool> wearing(String clubId, String me) async {
    final row = await _client.from('club_members').select('show_tag').eq('club_id', clubId).eq('user_id', me).maybeSingle();
    return row?['show_tag'] as bool? ?? false;
  }

  /// Wear (or stop wearing) a club's tag. Turning one on turns the others off.
  Future<void> setWearing(String clubId, bool show) => _client.rpc('set_club_tag', params: {'p_club': clubId, 'p_show': show});
}

final clubTagRepositoryProvider = Provider<ClubTagRepository>((ref) => ClubTagRepository(ref.watch(supabaseProvider)));
