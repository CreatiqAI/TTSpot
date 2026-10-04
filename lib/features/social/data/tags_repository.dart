import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/tags.dart';

/// #tags, post search, @mention lookups and my own post numbers (migration
/// 0101). Ranking happens on the server; these return post ids best first.
class TagsRepository {
  TagsRepository(this._client);
  final SupabaseClient _client;

  /// One page of a tag's posts, plus how many posts carry the tag (null on
  /// an empty page past the first, where the server has no row to say it).
  Future<({List<String> ids, int? total})> tagPosts(String tag, {int limit = 30, int offset = 0}) async {
    final rows = await _client.rpc('tag_posts', params: {'p_tag': tag, 'p_limit': limit, 'p_offset': offset}) as List;
    final ids = [for (final r in rows) r['post_id'] as String];
    if (rows.isEmpty) return (ids: ids, total: offset == 0 ? 0 : null);
    return (ids: ids, total: (rows.first['total'] as num?)?.toInt());
  }

  /// One page of posts matching a search box.
  Future<List<String>> searchPosts(String q, {int limit = 30, int offset = 0}) async {
    final rows = await _client.rpc('search_posts', params: {'p_q': q, 'p_limit': limit, 'p_offset': offset}) as List;
    return [for (final r in rows) r['post_id'] as String];
  }

  /// Tags starting with [q]; the most used lately when [q] is empty.
  Future<List<TagCount>> searchTags(String q, {int limit = 8}) async {
    final rows = await _client.rpc('search_tags', params: {'p_q': q, 'p_limit': limit}) as List;
    return [for (final r in rows) TagCount.fromMap(r as Map<String, dynamic>)];
  }

  /// Views, saves, likes, comments and shares for those of [ids] I wrote.
  Future<Map<String, MyPostStats>> myPostStats(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await _client.rpc('my_post_stats', params: {'p_ids': ids}) as List;
    return {for (final r in rows) r['post_id'] as String: MyPostStats.fromMap(r as Map<String, dynamic>)};
  }

  /// Who @[username] is, or null when nobody is.
  Future<String?> profileIdByUsername(String username) async {
    final row = await _client.from('profiles').select('id').eq('username', username.toLowerCase()).maybeSingle();
    return row?['id'] as String?;
  }
}

final tagsRepositoryProvider = Provider<TagsRepository>((ref) => TagsRepository(ref.watch(supabaseProvider)));
