import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/geo/latlng.dart';
import '../../../core/location/live_position.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../auth/domain/profile.dart';
import '../../safety/data/safety_repository.dart';
import '../data/social_repository.dart';
import '../domain/album.dart';
import '../domain/post.dart';

// ------------------------------------------------------------------ feeds ---

List<FeedPost> _dropBlocked(List<FeedPost> list, Set<String> blocked) =>
    list.where((f) => !blocked.contains(f.post.authorId)).toList();

/// The "For you" grid so far: ranked pages appended as you scroll.
class ForYouState {
  const ForYouState({required this.items, this.loadingMore = false, this.done = false});
  final List<FeedPost> items;
  final bool loadingMore;

  /// Nothing more to rank (or the session cap is reached).
  final bool done;

  ForYouState copyWith({List<FeedPost>? items, bool? loadingMore, bool? done}) =>
      ForYouState(items: items ?? this.items, loadingMore: loadingMore ?? this.loadingMore, done: done ?? this.done);
}

/// "For you" (Home grid), ranked per member on the server like RedNote /
/// Instagram (migration 0094: quality, freshness, friends and interests,
/// seen posts sink). 20 posts per page as you scroll. Likes and saves patch
/// the post in place instead of reloading, so the grid never reshuffles
/// under your thumb; pull to refresh re-ranks with a new seed.
class ForYouFeed extends AsyncNotifier<ForYouState> {
  static const pageSize = 20;
  static const maxItems = 400;

  String _seed = '';
  int _generation = 0;

  @override
  Future<ForYouState> build() async {
    ref.watch(currentUserIdProvider);
    await ref.watch(blockedUserIdsProvider.future);
    _generation++;
    _seed = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final page = await _page(const []);
    return ForYouState(items: page.items, done: page.ranked < pageSize);
  }

  Future<({List<FeedPost> items, int ranked})> _page(List<String> exclude) async {
    final me = ref.read(currentUserIdProvider);
    final repo = ref.read(socialRepositoryProvider);
    final blocked = await ref.read(blockedUserIdsProvider.future);
    // Only a position the app already has: the feed never asks for location.
    final near = ref.read(livePositionProvider)?.latLng;
    final ranked = await repo.rankForYou(limit: pageSize, exclude: exclude, seed: _seed, near: near);
    final reasons = {for (final r in ranked) r.id: r.reason};
    final feed = await repo.attachViewerState(await repo.fetchByIds([for (final r in ranked) r.id]), me);
    return (
      items: [
        for (final f in feed)
          if (!blocked.contains(f.post.authorId))
            FeedPost(post: f.post, likedByMe: f.likedByMe, savedByMe: f.savedByMe, myVote: f.myVote, reason: reasons[f.post.id]),
      ],
      ranked: ranked.length,
    );
  }

  /// The next page, when the grid nears its end.
  Future<void> loadMore() async {
    final s = state.value;
    if (s == null || s.loadingMore || s.done || state.isLoading) return;
    final gen = _generation;
    state = AsyncData(s.copyWith(loadingMore: true));
    try {
      final page = await _page([for (final f in s.items) f.post.id]);
      if (!ref.mounted || gen != _generation) return;
      final cur = state.value ?? s;
      final have = {for (final f in cur.items) f.post.id};
      final items = [...cur.items, for (final f in page.items) if (!have.contains(f.post.id)) f];
      state = AsyncData(ForYouState(items: items, done: page.ranked < pageSize || items.length >= maxItems));
    } catch (_) {
      // The next scroll tries again.
      if (ref.mounted && gen == _generation) state = AsyncData((state.value ?? s).copyWith(loadingMore: false));
    }
  }

  /// Re-reads one post after a like, save, vote or delete (gone = removed).
  Future<void> reloadPost(String postId) async {
    final s = state.value;
    if (s == null || !s.items.any((f) => f.post.id == postId)) return;
    final repo = ref.read(socialRepositoryProvider);
    final post = await repo.fetchPost(postId);
    final fresh = post == null ? null : (await repo.attachViewerState([post], ref.read(currentUserIdProvider))).first;
    if (!ref.mounted) return;
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(cur.copyWith(items: [
      for (final f in cur.items)
        if (f.post.id != postId)
          f
        else if (fresh != null)
          FeedPost(post: fresh.post, likedByMe: fresh.likedByMe, savedByMe: fresh.savedByMe, myVote: fresh.myVote, reason: f.reason),
    ]));
  }

  /// "Not interested" (or, with [author], "Fewer from this person"): out of
  /// the grid at once, and the ranking learns it. Returns the undo.
  Future<Future<void> Function()> hide(FeedPost f, {bool author = false}) async {
    final repo = ref.read(socialRepositoryProvider);
    final me = ref.read(currentUserIdProvider);
    final before = state.value;
    bool gone(FeedPost x) => author ? x.post.authorId == f.post.authorId : x.post.id == f.post.id;
    if (before != null) state = AsyncData(before.copyWith(items: [for (final x in before.items) if (!gone(x)) x]));
    await repo.hidePost(f.post.id, author: author);
    return () async {
      if (me != null) await repo.unhidePost(f.post.id, me);
      if (!ref.mounted || before == null) return;
      final cur = state.value;
      if (cur == null) return;
      // Put them back where they were; keep the current copies of the rest.
      final now = {for (final x in cur.items) x.post.id: x};
      final restored = [for (final x in before.items) if (now.containsKey(x.post.id) || gone(x)) now[x.post.id] ?? x];
      final shown = {for (final x in restored) x.post.id};
      state = AsyncData(cur.copyWith(items: [...restored, for (final x in cur.items) if (!shown.contains(x.post.id)) x]));
    };
  }
}

final forYouFeedProvider = AsyncNotifierProvider<ForYouFeed, ForYouState>(ForYouFeed.new);

/// "Following": friends, people I follow and my clubs, newest first.
final followingFeedProvider = FutureProvider<List<FeedPost>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final repo = ref.watch(socialRepositoryProvider);
  final posts = await repo.fetchFollowing();
  return _dropBlocked(await repo.attachViewerState(posts, me), blocked);
});

/// "More like this" under a post.
final relatedPostsProvider = FutureProvider.autoDispose.family<List<FeedPost>, String>((ref, postId) async {
  final me = ref.watch(currentUserIdProvider);
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final repo = ref.watch(socialRepositoryProvider);
  return _dropBlocked(await repo.attachViewerState(await repo.fetchRelated(postId), me), blocked);
});

/// What came on screen and which posts were opened, for the ranking. Views
/// go up in batches; nothing here ever blocks the UI or shows an error.
class FeedSignals {
  FeedSignals(this._ref);
  final Ref _ref;
  final _pending = <String>{};
  Timer? _timer;

  void seen(Iterable<String> ids) {
    if (_ref.read(currentUserIdProvider) == null) return;
    _pending.addAll(ids);
    if (_pending.length >= 20) {
      flush();
    } else {
      _timer ??= Timer(const Duration(seconds: 3), flush);
    }
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final ids = _pending.toList();
    _pending.clear();
    _ref.read(socialRepositoryProvider).logViews(ids).ignore();
  }

  /// A post page was open for [stayed].
  void opened(String postId, Duration stayed) {
    if (_ref.read(currentUserIdProvider) == null) return;
    _ref.read(socialRepositoryProvider).logOpen(postId, stayed.inMilliseconds).ignore();
  }
}

final feedSignalsProvider = Provider<FeedSignals>((ref) {
  final signals = FeedSignals(ref);
  ref.onDispose(signals.flush);
  return signals;
});

final userPostsProvider = FutureProvider.family<List<FeedPost>, String>((ref, userId) async {
  final me = ref.watch(currentUserIdProvider);
  final repo = ref.watch(socialRepositoryProvider);
  return repo.attachViewerState(await repo.fetchByAuthor(userId), me);
});

/// Posts tagged to an event (the meet photo wall), place, car or club.
final postsWhereProvider = FutureProvider.family<List<FeedPost>, ({String column, String value})>((ref, key) async {
  final me = ref.watch(currentUserIdProvider);
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final repo = ref.watch(socialRepositoryProvider);
  return _dropBlocked(await repo.attachViewerState(await repo.fetchWhere(key.column, key.value), me), blocked);
});

final savedPostsProvider = FutureProvider<List<FeedPost>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  final repo = ref.watch(socialRepositoryProvider);
  return repo.attachViewerState(await repo.fetchSaved(me), me);
});

final likedPostsProvider = FutureProvider<List<FeedPost>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  final repo = ref.watch(socialRepositoryProvider);
  return repo.attachViewerState(await repo.fetchLiked(me), me);
});

final commentedPostsProvider = FutureProvider<List<FeedPost>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  final repo = ref.watch(socialRepositoryProvider);
  return repo.attachViewerState(await repo.fetchCommented(me), me);
});

/// Every moment I posted, live or not (author-only read).
final myMomentsArchiveProvider = FutureProvider<List<Story>>((ref) {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return Future.value(const []);
  return ref.watch(socialRepositoryProvider).fetchUserMoments(me, all: true, limit: 300);
});
final storyProvider = FutureProvider.family<Story?, String>((ref, id) => ref.watch(socialRepositoryProvider).fetchStory(id));
final storyViewersProvider = FutureProvider.family<List<StoryViewer>, String>((ref, id) => ref.watch(socialRepositoryProvider).storyViewers(id));
final albumsContainingProvider = FutureProvider.family<Set<String>, String>((ref, id) => ref.watch(socialRepositoryProvider).albumsContaining(id));

final userAlbumsProvider = FutureProvider.family<List<MomentAlbum>, String>((ref, userId) => ref.watch(socialRepositoryProvider).fetchAlbums(userId));
final albumProvider = FutureProvider.family<MomentAlbum?, String>((ref, id) => ref.watch(socialRepositoryProvider).fetchAlbum(id));
final albumMomentsProvider = FutureProvider.family<List<Story>, String>((ref, id) => ref.watch(socialRepositoryProvider).fetchAlbumMoments(id));

final postProvider = FutureProvider.family<FeedPost?, String>((ref, id) async {
  final me = ref.watch(currentUserIdProvider);
  final repo = ref.watch(socialRepositoryProvider);
  final post = await repo.fetchPost(id);
  if (post == null) return null;
  return (await repo.attachViewerState([post], me)).first;
});

final postCommentsProvider = FutureProvider.family<List<PostComment>, String>((ref, id) async {
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final list = await ref.watch(socialRepositoryProvider).fetchComments(id);
  return list.where((c) => !blocked.contains(c.userId)).toList();
});

final pollResultsProvider = FutureProvider.family<Map<int, int>, String>((ref, id) {
  return ref.watch(socialRepositoryProvider).pollResults(id);
});

final postLikersProvider = FutureProvider.family<List<Profile>, String>((ref, id) {
  return ref.watch(socialRepositoryProvider).likers(id);
});

/// Spotted posts in the current map viewport.
final spottedInBoundsProvider = FutureProvider.family<List<Post>, LatLngBounds>((ref, bounds) {
  return ref.watch(socialRepositoryProvider).fetchSpottedInBounds(bounds);
});

// ---------------------------------------------------------------- stories ---

final storiesProvider = FutureProvider<List<StoryGroup>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final groups = await ref.watch(socialRepositoryProvider).fetchStories(me);
  return groups.where((g) => !blocked.contains(g.author.id)).toList();
});

final profileSearchProvider = FutureProvider.family<List<Profile>, String>((ref, q) => ref.watch(socialRepositoryProvider).searchProfiles(q));

final eventMomentsProvider = FutureProvider.family<List<Story>, String>((ref, eventId) => ref.watch(socialRepositoryProvider).fetchEventMoments(eventId));
final placeMomentsProvider = FutureProvider.family<List<Story>, String>((ref, placeId) => ref.watch(socialRepositoryProvider).fetchPlaceMoments(placeId));
final userMomentsProvider = FutureProvider.family<List<Story>, String>((ref, userId) => ref.watch(socialRepositoryProvider).fetchUserMoments(userId));

// -------------------------------------------------------- car of the week ---

final weekLeaderProvider = FutureProvider<({Post post, int likes})?>((ref) => ref.watch(socialRepositoryProvider).currentWeekLeader());
final lastWinnerProvider = FutureProvider<WeeklyWinner?>((ref) => ref.watch(socialRepositoryProvider).lastWinner());

// ---------------------------------------------------------------- follows ---

final isFollowingProvider = FutureProvider.family<bool, String>((ref, other) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null || me == other) return false;
  return ref.watch(socialRepositoryProvider).isFollowing(me, other);
});

final followCountsProvider = FutureProvider.family<({int followers, int following}), String>((ref, userId) {
  return ref.watch(socialRepositoryProvider).followCounts(userId);
});

final followersProvider = FutureProvider.family<List<Profile>, String>((ref, userId) => ref.watch(socialRepositoryProvider).followers(userId));
final followingListProvider = FutureProvider.family<List<Profile>, String>((ref, userId) => ref.watch(socialRepositoryProvider).following(userId));

// ---------------------------------------------------------------- actions ---

/// Mutations. Each call refreshes the providers it affects.
class SocialActions {
  SocialActions(this._ref);
  final Ref _ref;

  String get _me {
    final id = _ref.read(currentUserIdProvider);
    if (id == null) throw const AppException('You\'re signed out. Sign in again.');
    return id;
  }

  SocialRepository get _repo => _ref.read(socialRepositoryProvider);

  void refreshPost(String postId, {String? authorId}) {
    _ref.invalidate(postProvider(postId));
    if (authorId != null) _ref.invalidate(userPostsProvider(authorId));
    // The ranked grid patches the one post; a reload would reshuffle it.
    if (_ref.exists(forYouFeedProvider)) _ref.read(forYouFeedProvider.notifier).reloadPost(postId).ignore();
    _ref.invalidate(followingFeedProvider);
    _ref.invalidate(savedPostsProvider);
    _ref.invalidate(weekLeaderProvider);
  }

  /// "Not interested" from a post's menu (the grid's long-press goes
  /// through [ForYouFeed.hide] so it can offer Undo in place).
  Future<void> notInterested(FeedPost f, {bool author = false}) async {
    if (_ref.exists(forYouFeedProvider)) {
      await _ref.read(forYouFeedProvider.notifier).hide(f, author: author);
    } else {
      await _repo.hidePost(f.post.id, author: author);
    }
    _ref.invalidate(followingFeedProvider);
  }

  Future<void> toggleLike(FeedPost f) async {
    if (f.likedByMe) {
      await _repo.unlike(f.post.id, _me);
    } else {
      await _repo.like(f.post.id, _me);
    }
    refreshPost(f.post.id, authorId: f.post.authorId);
    _ref.invalidate(postLikersProvider(f.post.id));
  }

  Future<void> toggleSave(FeedPost f) async {
    if (f.savedByMe) {
      await _repo.unsave(f.post.id, _me);
    } else {
      await _repo.save(f.post.id, _me);
    }
    refreshPost(f.post.id, authorId: f.post.authorId);
  }

  Future<void> vote(FeedPost f, int option) async {
    await _repo.vote(f.post.id, _me, option);
    _ref.invalidate(pollResultsProvider(f.post.id));
    refreshPost(f.post.id, authorId: f.post.authorId);
  }

  Future<void> claimSpotted(FeedPost f) async {
    await _repo.claimSpotted(f.post.id);
    refreshPost(f.post.id, authorId: f.post.authorId);
  }

  Future<void> deletePost(FeedPost f) async {
    await _repo.deletePost(f.post.id);
    refreshPost(f.post.id, authorId: f.post.authorId);
  }

  Future<void> addComment(String postId, String body) async {
    if (body.trim().isEmpty) return;
    await _repo.addComment(postId: postId, me: _me, body: body);
    _ref.invalidate(postCommentsProvider(postId));
    _ref.invalidate(postProvider(postId));
  }

  Future<void> deleteComment(String postId, String commentId) async {
    await _repo.deleteComment(commentId);
    _ref.invalidate(postCommentsProvider(postId));
    _ref.invalidate(postProvider(postId));
  }

  Future<void> toggleFollow(String other, {required bool currentlyFollowing}) async {
    if (currentlyFollowing) {
      await _repo.unfollow(_me, other);
    } else {
      await _repo.follow(_me, other);
    }
    _ref.invalidate(isFollowingProvider(other));
    _ref.invalidate(followCountsProvider(other));
    _ref.invalidate(followCountsProvider(_me));
    _ref.invalidate(followersProvider(other));
    _ref.invalidate(followingListProvider(_me));
    _ref.invalidate(followingFeedProvider);
  }

  Future<void> markStoryViewed(String storyId) async {
    await _repo.markStoryViewed(storyId, _me);
  }

  Future<void> deleteStory(String storyId) async {
    await _repo.deleteStory(storyId);
    _ref.invalidate(storiesProvider);
    _ref.invalidate(userMomentsProvider(_me));
    _ref.invalidate(myMomentsArchiveProvider);
    _ref.invalidate(userAlbumsProvider(_me));
  }

  Future<String> saveAlbum({String? id, required String name, String? coverUrl, required List<String> storyIds}) async {
    if (name.trim().isEmpty) throw const AppException('Give the album a name.');
    if (storyIds.isEmpty) throw const AppException('Pick at least one moment.');
    final albumId = await _repo.saveAlbum(id: id, me: _me, name: name, coverUrl: coverUrl, storyIds: storyIds);
    _ref.invalidate(userAlbumsProvider(_me));
    _ref.invalidate(albumProvider(albumId));
    _ref.invalidate(albumMomentsProvider(albumId));
    return albumId;
  }

  Future<void> toggleInAlbum(String albumId, String storyId, {required bool add}) async {
    if (add) {
      await _repo.addToAlbum(albumId, storyId);
    } else {
      await _repo.removeFromAlbum(albumId, storyId);
    }
    _ref.invalidate(albumsContainingProvider(storyId));
    _ref.invalidate(albumMomentsProvider(albumId));
    _ref.invalidate(userAlbumsProvider(_me));
  }

  Future<void> deleteAlbum(String id) async {
    await _repo.deleteAlbum(id);
    _ref.invalidate(userAlbumsProvider(_me));
  }
}

final socialActionsProvider = Provider<SocialActions>((ref) => SocialActions(ref));
