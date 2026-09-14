import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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

/// "For you": everything, newest first (masonry grid).
final exploreFeedProvider = FutureProvider<List<FeedPost>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final repo = ref.watch(socialRepositoryProvider);
  final posts = await repo.fetchExplore();
  return _dropBlocked(await repo.attachViewerState(posts, me), blocked);
});

/// "Following": people I follow, newest first (feed cards).
final followingFeedProvider = FutureProvider<List<FeedPost>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final repo = ref.watch(socialRepositoryProvider);
  final posts = await repo.fetchFollowing(me);
  return _dropBlocked(await repo.attachViewerState(posts, me), blocked);
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

  void _refreshFeeds() {
    _ref.invalidate(exploreFeedProvider);
    _ref.invalidate(followingFeedProvider);
    _ref.invalidate(savedPostsProvider);
    _ref.invalidate(weekLeaderProvider);
  }

  void refreshPost(String postId, {String? authorId}) {
    _ref.invalidate(postProvider(postId));
    if (authorId != null) _ref.invalidate(userPostsProvider(authorId));
    _refreshFeeds();
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
