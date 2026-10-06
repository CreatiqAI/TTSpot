import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/domain/profile.dart';
import '../domain/comment_thread.dart';
import 'social_repository.dart' show authorCols, profileCols;

/// Post comments with replies and likes (migration 20261005000102). The
/// server threads a reply under its top-level parent and sends the reply,
/// like and @mention pings itself.
class CommentRepository {
  CommentRepository(this._client);
  final SupabaseClient _client;

  /// Every comment on [postId] (top-level and replies), oldest first, with
  /// like counts and which ones [me] liked.
  Future<List<CommentItem>> fetch(String postId, String? me) async {
    final rows = await _client
        .from('post_comments')
        .select('id, post_id, user_id, parent_id, reply_to_id, body, created_at, profiles($authorCols), post_comment_likes(count)')
        .eq('post_id', postId)
        .order('created_at')
        .limit(500);
    final ids = [for (final r in rows) r['id'] as String];
    var mine = const <String>{};
    if (me != null && ids.isNotEmpty) {
      final liked = await _client.from('post_comment_likes').select('comment_id').eq('user_id', me).inFilter('comment_id', ids);
      mine = {for (final r in liked) r['comment_id'] as String};
    }
    return [for (final r in rows) CommentItem.fromMap(r, likedByMe: mine.contains(r['id']))];
  }

  /// [parentId]: the comment tapped Reply on (a reply's reply is fine; the
  /// server files it under the top-level comment).
  Future<void> add({required String postId, required String me, required String body, String? parentId}) =>
      _client.from('post_comments').insert({'post_id': postId, 'user_id': me, 'body': body.trim(), 'parent_id': ?parentId});

  /// Its replies go with it.
  Future<void> delete(String id) => _client.from('post_comments').delete().eq('id', id);

  Future<void> like(String commentId, String me) => _client.from('post_comment_likes').upsert({'comment_id': commentId, 'user_id': me});
  Future<void> unlike(String commentId, String me) => _client.from('post_comment_likes').delete().eq('comment_id', commentId).eq('user_id', me);

  /// People whose @handle or name contains [query], for @ suggestions.
  Future<List<Profile>> searchPeople(String query, {int limit = 8}) async {
    final q = query.trim().replaceAll(RegExp(r'[%,()*]'), '');
    if (q.isEmpty) return const [];
    final rows = await _client
        .from('profiles')
        .select(profileCols)
        .not('username', 'is', null)
        .or('username.ilike.$q%,display_name.ilike.%$q%')
        .limit(limit);
    return rows.map(Profile.fromMap).toList();
  }
}

final commentRepositoryProvider = Provider<CommentRepository>((ref) => CommentRepository(ref.watch(supabaseProvider)));
