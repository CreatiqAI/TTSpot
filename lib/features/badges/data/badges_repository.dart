import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/badges.dart';

/// Tiered badges and the profile's honour row (badge_progress,
/// honour_badges, set_honour_badges in 20261006000108).
class BadgesRepository {
  BadgesRepository(this._client);
  final SupabaseClient _client;

  /// Every badge with [userId]'s tier and count. On my own page the
  /// database catches my tiers up first.
  Future<List<BadgeProgress>> progress(String userId) async {
    final rows = await _client.rpc('badge_progress', params: {'p_user': userId}) as List;
    return rows.map((r) => BadgeProgress.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  /// Up to three medallions for [userId]'s profile.
  Future<List<HonourBadge>> honour(String userId) async {
    final rows = await _client.rpc('honour_badges', params: {'p_user': userId}) as List;
    return rows.map((r) => HonourBadge.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  /// My pick, in order (up to three). Empty = my latest three again.
  Future<void> setHonour(List<String> ids) => _client.rpc('set_honour_badges', params: {'p_ids': ids});
}

final badgesRepositoryProvider = Provider<BadgesRepository>((ref) => BadgesRepository(ref.watch(supabaseProvider)));
