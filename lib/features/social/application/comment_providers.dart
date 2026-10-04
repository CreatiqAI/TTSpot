import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/domain/profile.dart';
import '../../friends/application/friends_providers.dart';
import '../../safety/data/safety_repository.dart';
import '../data/comment_repository.dart';
import '../domain/comment_thread.dart';
import 'social_providers.dart';

/// Every comment on a post (replies too), minus people I blocked. The
/// screen groups them with [buildThreads], which also drops replies under a
/// blocked person's comment.
final postCommentItemsProvider = FutureProvider.family<List<CommentItem>, String>((ref, postId) async {
  final me = ref.watch(currentUserIdProvider);
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final list = await ref.watch(commentRepositoryProvider).fetch(postId, me);
  return list.where((c) => !blocked.contains(c.userId)).toList();
});

/// Whether [p] can be suggested after an "@": someone else, not blocked,
/// with a handle.
bool _suggestable(Profile p, String me, Set<String> blocked) {
  final handle = p.username;
  if (handle == null || handle.isEmpty) return false;
  return p.id != me && !blocked.contains(p.id);
}

bool _matches(Profile p, String q) {
  if (q.isEmpty) return true;
  final handle = p.username;
  if (handle != null && handle.toLowerCase().startsWith(q)) return true;
  final name = p.displayName;
  return name != null && name.toLowerCase().contains(q);
}

/// @ suggestions for [query] (what follows the "@"): friends first, then
/// anyone else whose handle or name matches. Never me, never someone I
/// blocked, never an account that hasn't picked a handle yet. Six at most.
final mentionSuggestionsProvider = FutureProvider.autoDispose.family<List<Profile>, String>((ref, query) async {
  final me = ref.watch(currentUserIdProvider) ?? '';
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final friends = await ref.watch(friendsProvider.future);
  final q = query.toLowerCase();

  final out = <Profile>[];
  final seen = <String>{};
  for (final f in friends) {
    if (_suggestable(f, me, blocked) && _matches(f, q) && seen.add(f.id)) out.add(f);
  }
  if (q.isNotEmpty && out.length < 6) {
    final others = await ref.watch(commentRepositoryProvider).searchPeople(q);
    for (final p in others) {
      if (_suggestable(p, me, blocked) && seen.add(p.id)) out.add(p);
    }
  }
  return out.take(6).toList();
});

class CommentActions {
  CommentActions(this._ref);
  final Ref _ref;

  CommentRepository get _repo => _ref.read(commentRepositoryProvider);
  String get _me => _ref.read(currentUserIdProvider)!;

  void _refresh(String postId) {
    _ref.invalidate(postCommentItemsProvider(postId));
    _ref.invalidate(postCommentsProvider(postId));
    _ref.invalidate(postProvider(postId)); // the comment count
  }

  /// [replyTo]: the comment tapped Reply on.
  Future<void> add(String postId, String body, {String? replyTo}) async {
    if (body.trim().isEmpty) return;
    await _repo.add(postId: postId, me: _me, body: body, parentId: replyTo);
    _refresh(postId);
  }

  Future<void> delete(String postId, String commentId) async {
    await _repo.delete(commentId);
    _refresh(postId);
  }

  /// The screen shows the new state at once; this only tells the server.
  Future<void> setLiked(String commentId, bool liked) => liked ? _repo.like(commentId, _me) : _repo.unlike(commentId, _me);
}

final commentActionsProvider = Provider<CommentActions>((ref) => CommentActions(ref));
