import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/club_tag.dart';

/// Official club tags (migrations 0109 and 0111). Lists get the tag with the
/// author (`club_tag` in [authorCols]); this is for one person and for my
/// choice.
class ClubTagRepository {
  ClubTagRepository(this._client);
  final SupabaseClient _client;

  /// The tag [userId] shows, or null.
  Future<ClubTag?> tagOf(String userId) async => ClubTag.fromJson(await _client.rpc('club_tag_of', params: {'p_user': userId}));

  /// Wear (or take off) one club's tag: the club page's switch. Taking off
  /// the tag that shows means no tag at all (presidents included).
  Future<void> setWearing(String clubId, bool show) => _client.rpc('set_club_tag', params: {'p_club': clubId, 'p_show': show});

  /// My pick: the tag of [clubId] (an official club I'm in), or none (null).
  /// Returns the tag I show now.
  Future<ClubTag?> choose(String? clubId) async => ClubTag.fromJson(await _client.rpc('set_my_club_tag', params: {'p_club': clubId}));
}

final clubTagRepositoryProvider = Provider<ClubTagRepository>((ref) => ClubTagRepository(ref.watch(supabaseProvider)));
