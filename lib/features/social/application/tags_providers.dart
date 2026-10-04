import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../safety/data/safety_repository.dart';
import '../data/social_repository.dart';
import '../data/tags_repository.dart';
import '../domain/post.dart';
import '../domain/tags.dart';

// --------------------------------------------------- tag page and search ---

enum PostQueryKind { tag, search }

/// A tag page (`text` = the tag) or a search box (`text` = what was typed).
typedef PostQuery = ({PostQueryKind kind, String text});

class PagedPostsState {
  const PagedPostsState({required this.items, this.total, this.loadingMore = false, this.done = false});
  final List<FeedPost> items;

  /// Tag pages: how many posts carry the tag.
  final int? total;
  final bool loadingMore;
  final bool done;

  PagedPostsState copyWith({List<FeedPost>? items, int? total, bool? loadingMore, bool? done}) => PagedPostsState(
        items: items ?? this.items,
        total: total ?? this.total,
        loadingMore: loadingMore ?? this.loadingMore,
        done: done ?? this.done,
      );
}

/// A ranked grid that grows as you scroll: a tag's posts (tag_posts) or
/// search results (search_posts), 30 at a time.
class PagedPosts extends AsyncNotifier<PagedPostsState> {
  PagedPosts(this.query);
  final PostQuery query;

  static const pageSize = 30;
  static const maxItems = 600;

  int _offset = 0;
  int _generation = 0;

  @override
  Future<PagedPostsState> build() async {
    ref.watch(currentUserIdProvider);
    await ref.watch(blockedUserIdsProvider.future);
    _generation++;
    _offset = 0;
    if (query.text.trim().isEmpty) return const PagedPostsState(items: [], total: 0, done: true);
    final page = await _page(0);
    return PagedPostsState(items: page.items, total: page.total, done: page.ranked < pageSize);
  }

  Future<({List<FeedPost> items, int ranked, int? total})> _page(int offset) async {
    final tags = ref.read(tagsRepositoryProvider);
    final social = ref.read(socialRepositoryProvider);
    final me = ref.read(currentUserIdProvider);
    final blocked = await ref.read(blockedUserIdsProvider.future);
    List<String> ids;
    int? total;
    switch (query.kind) {
      case PostQueryKind.tag:
        final r = await tags.tagPosts(query.text, limit: pageSize, offset: offset);
        ids = r.ids;
        total = r.total;
      case PostQueryKind.search:
        ids = await tags.searchPosts(query.text, limit: pageSize, offset: offset);
    }
    _offset = offset + ids.length;
    final feed = await social.attachViewerState(await social.fetchByIds(ids), me);
    return (items: [for (final f in feed) if (!blocked.contains(f.post.authorId)) f], ranked: ids.length, total: total);
  }

  /// The next page, when the grid nears its end.
  Future<void> loadMore() async {
    final s = state.value;
    if (s == null || s.loadingMore || s.done || state.isLoading) return;
    final gen = _generation;
    state = AsyncData(s.copyWith(loadingMore: true));
    try {
      final page = await _page(_offset);
      if (!ref.mounted || gen != _generation) return;
      final cur = state.value ?? s;
      final have = {for (final f in cur.items) f.post.id};
      final items = [...cur.items, for (final f in page.items) if (!have.contains(f.post.id)) f];
      state = AsyncData(PagedPostsState(
        items: items,
        total: page.total ?? cur.total,
        done: page.ranked < pageSize || items.length >= maxItems,
      ));
    } catch (_) {
      // The next scroll tries again.
      if (ref.mounted && gen == _generation) state = AsyncData((state.value ?? s).copyWith(loadingMore: false));
    }
  }
}

final pagedPostsProvider = AsyncNotifierProvider.autoDispose.family<PagedPosts, PagedPostsState, PostQuery>(PagedPosts.new);

/// Tags starting with what was typed (popular tags for '').
final tagSearchProvider = FutureProvider.autoDispose.family<List<TagCount>, String>((ref, q) {
  ref.watch(currentUserIdProvider);
  return ref.watch(tagsRepositoryProvider).searchTags(q, limit: 12);
});

// ------------------------------------------------------- my post numbers ---

/// Collects the posts the screen asks about in one frame and fetches their
/// numbers in one round trip (a profile grid is many tiles).
class MyPostStatsBatcher {
  MyPostStatsBatcher(this._repo);
  final TagsRepository _repo;
  final _waiting = <String, Completer<MyPostStats?>>{};
  bool _scheduled = false;

  Future<MyPostStats?> load(String postId) {
    final c = _waiting.putIfAbsent(postId, Completer<MyPostStats?>.new);
    if (!_scheduled) {
      _scheduled = true;
      scheduleMicrotask(_flush);
    }
    return c.future;
  }

  Future<void> _flush() async {
    _scheduled = false;
    final batch = Map.of(_waiting);
    _waiting.clear();
    final ids = batch.keys.toList();
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
      try {
        final stats = await _repo.myPostStats(chunk);
        for (final id in chunk) {
          batch[id]!.complete(stats[id]);
        }
      } catch (e, st) {
        for (final id in chunk) {
          batch[id]!.completeError(e, st);
        }
      }
    }
  }
}

final myPostStatsBatcherProvider = Provider<MyPostStatsBatcher>((ref) => MyPostStatsBatcher(ref.watch(tagsRepositoryProvider)));

/// Views, saves and shares of one of my posts (null for anyone else's: the
/// server only answers the author).
final myPostStatsProvider = FutureProvider.autoDispose.family<MyPostStats?, String>((ref, postId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(myPostStatsBatcherProvider).load(postId);
});
