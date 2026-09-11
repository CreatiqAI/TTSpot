import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/domain/profile.dart';
import '../domain/post.dart';

const profileCols = 'id, username, display_name, bio, avatar_url, home_state, created_at';
const _storySelect = '*, profiles:profiles!stories_author_id_fkey($profileCols), events(title), places(name)';

const _postSelect = '*, '
    'author:profiles!posts_author_id_fkey($profileCols), '
    'claimer:profiles!posts_claimed_by_fkey($profileCols), '
    'car:cars(id, make, model), place:places(id, name), event:events(id, title), club:clubs(id, name, handle), '
    'likes:post_likes(count), comments:post_comments(count), votes:poll_votes(count)';

/// Posts, likes, saves, comments, polls, follows, stories, car of the week.
class SocialRepository {
  SocialRepository(this._client);
  final SupabaseClient _client;

  // ---------------------------------------------------------------- feeds ---

  Future<List<Post>> fetchExplore({int limit = 40, DateTime? before, PostKind? kind}) async {
    var q = _client.from('posts').select(_postSelect);
    if (kind != null) q = q.eq('kind', kind.db);
    if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return rows.map(Post.fromMap).toList();
  }

  Future<List<Post>> fetchFollowing(String me, {int limit = 40}) async {
    final ids = (await _client.from('follows').select('followee_id').eq('follower_id', me))
        .map((r) => r['followee_id'] as String)
        .toList();
    if (ids.isEmpty) return const [];
    final rows = await _client.from('posts').select(_postSelect).inFilter('author_id', ids).order('created_at', ascending: false).limit(limit);
    return rows.map(Post.fromMap).toList();
  }

  Future<List<Post>> fetchByAuthor(String userId, {int limit = 60}) async {
    final rows = await _client.from('posts').select(_postSelect).eq('author_id', userId).order('created_at', ascending: false).limit(limit);
    return rows.map(Post.fromMap).toList();
  }

  Future<List<Post>> fetchWhere(String column, String value, {int limit = 60}) async {
    final rows = await _client.from('posts').select(_postSelect).eq(column, value).order('created_at', ascending: false).limit(limit);
    return rows.map(Post.fromMap).toList();
  }

  Future<List<Post>> fetchSaved(String me) async {
    final ids = (await _client.from('post_saves').select('post_id').eq('user_id', me).order('created_at', ascending: false).limit(100))
        .map((r) => r['post_id'] as String)
        .toList();
    if (ids.isEmpty) return const [];
    final rows = await _client.from('posts').select(_postSelect).inFilter('id', ids);
    final byId = {for (final r in rows) r['id'] as String: Post.fromMap(r)};
    return ids.map((id) => byId[id]).whereType<Post>().toList();
  }

  /// Spotted posts inside a map box (for the map layer).
  Future<List<Post>> fetchSpottedInBounds(LatLngBounds b, {int limit = 100}) async {
    final rows = await _client
        .from('posts')
        .select(_postSelect)
        .eq('kind', 'spotted')
        .gte('lat', b.southwest.latitude)
        .lte('lat', b.northeast.latitude)
        .gte('lng', b.southwest.longitude)
        .lte('lng', b.northeast.longitude)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Post.fromMap).toList();
  }

  Future<Post?> fetchPost(String id) async {
    final row = await _client.from('posts').select(_postSelect).eq('id', id).maybeSingle();
    return row == null ? null : Post.fromMap(row);
  }

  /// Viewer state for a batch of posts, in one round trip per table.
  Future<List<FeedPost>> attachViewerState(List<Post> posts, String? me) async {
    if (posts.isEmpty) return const [];
    if (me == null) return posts.map((p) => FeedPost(post: p, likedByMe: false, savedByMe: false)).toList();
    final ids = posts.map((p) => p.id).toList();
    final results = await Future.wait<dynamic>([
      _client.from('post_likes').select('post_id').eq('user_id', me).inFilter('post_id', ids),
      _client.from('post_saves').select('post_id').eq('user_id', me).inFilter('post_id', ids),
      _client.from('poll_votes').select('post_id, option_index').eq('user_id', me).inFilter('post_id', ids),
    ]);
    final liked = (results[0] as List).map((r) => r['post_id'] as String).toSet();
    final saved = (results[1] as List).map((r) => r['post_id'] as String).toSet();
    final votes = {for (final r in results[2] as List) r['post_id'] as String: (r['option_index'] as num).toInt()};
    return posts
        .map((p) => FeedPost(post: p, likedByMe: liked.contains(p.id), savedByMe: saved.contains(p.id), myVote: votes[p.id]))
        .toList();
  }

  // --------------------------------------------------------------- create ---

  Future<String> uploadPhoto({required String userId, required Uint8List bytes, String folder = 'posts'}) async {
    final path = '$userId/$folder/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _client.storage.from('post-photos').uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    return _client.storage.from('post-photos').getPublicUrl(path);
  }

  Future<Post> createPost({
    required String authorId,
    required PostKind kind,
    String? title,
    String? caption,
    required List<String> photoUrls,
    double coverAspect = 1.0,
    String? carId,
    String? eventId,
    String? placeId,
    String? clubId,
    LatLng? location,
    List<PollOption>? pollOptions,
    DateTime? pollEndsAt,
    List<GuideStop>? guideStops,
  }) async {
    final row = await _client
        .from('posts')
        .insert({
          'author_id': authorId,
          'kind': kind.db,
          'title': ?title?.trim(),
          'caption': ?caption?.trim(),
          'photo_urls': photoUrls,
          'cover_aspect': coverAspect,
          'car_id': ?carId,
          'event_id': ?eventId,
          'place_id': ?placeId,
          'club_id': ?clubId,
          'lat': ?location?.latitude,
          'lng': ?location?.longitude,
          'poll_options': ?pollOptions?.map((o) => o.toJson()).toList(),
          'poll_ends_at': ?pollEndsAt?.toUtc().toIso8601String(),
          'guide_stops': ?guideStops?.map((s) => s.toJson()).toList(),
        })
        .select(_postSelect)
        .single();
    return Post.fromMap(row);
  }

  Future<void> deletePost(String id) => _client.from('posts').delete().eq('id', id);

  // ------------------------------------------------------------ reactions ---

  Future<void> like(String postId, String me) => _client.from('post_likes').upsert({'post_id': postId, 'user_id': me});
  Future<void> unlike(String postId, String me) => _client.from('post_likes').delete().eq('post_id', postId).eq('user_id', me);
  Future<void> save(String postId, String me) => _client.from('post_saves').upsert({'post_id': postId, 'user_id': me});
  Future<void> unsave(String postId, String me) => _client.from('post_saves').delete().eq('post_id', postId).eq('user_id', me);

  Future<void> vote(String postId, String me, int option) =>
      _client.from('poll_votes').upsert({'post_id': postId, 'user_id': me, 'option_index': option});

  /// Vote counts per option index.
  Future<Map<int, int>> pollResults(String postId) async {
    final rows = await _client.from('poll_votes').select('option_index').eq('post_id', postId);
    final counts = <int, int>{};
    for (final r in rows) {
      final i = (r['option_index'] as num).toInt();
      counts[i] = (counts[i] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> claimSpotted(String postId) => _client.rpc('claim_spotted', params: {'p_post': postId});

  Future<List<Profile>> likers(String postId, {int limit = 50}) async {
    final rows = await _client.from('post_likes').select('profiles($profileCols)').eq('post_id', postId).order('created_at', ascending: false).limit(limit);
    return rows.map((r) => r['profiles']).whereType<Map<String, dynamic>>().map(Profile.fromMap).toList();
  }

  // ------------------------------------------------------------- comments ---

  Future<List<PostComment>> fetchComments(String postId) async {
    final rows = await _client.from('post_comments').select('*, profiles($profileCols)').eq('post_id', postId).order('created_at').limit(300);
    return rows.map(PostComment.fromMap).toList();
  }

  Future<void> addComment({required String postId, required String me, required String body}) =>
      _client.from('post_comments').insert({'post_id': postId, 'user_id': me, 'body': body.trim()});

  Future<void> deleteComment(String id) => _client.from('post_comments').delete().eq('id', id);

  // -------------------------------------------------------------- follows ---

  Future<void> follow(String me, String other) => _client.from('follows').upsert({'follower_id': me, 'followee_id': other});
  Future<void> unfollow(String me, String other) => _client.from('follows').delete().eq('follower_id', me).eq('followee_id', other);

  Future<bool> isFollowing(String me, String other) async {
    final row = await _client.from('follows').select('follower_id').eq('follower_id', me).eq('followee_id', other).maybeSingle();
    return row != null;
  }

  Future<({int followers, int following})> followCounts(String userId) async {
    final results = await Future.wait<dynamic>([
      _client.from('follows').select('follower_id').eq('followee_id', userId),
      _client.from('follows').select('followee_id').eq('follower_id', userId),
    ]);
    return (followers: (results[0] as List).length, following: (results[1] as List).length);
  }

  Future<List<Profile>> followers(String userId) async {
    final rows = await _client.from('follows').select('profiles!follows_follower_id_fkey($profileCols)').eq('followee_id', userId).order('created_at', ascending: false).limit(200);
    return rows.map((r) => r['profiles']).whereType<Map<String, dynamic>>().map(Profile.fromMap).toList();
  }

  Future<List<Profile>> following(String userId) async {
    final rows = await _client.from('follows').select('profiles!follows_followee_id_fkey($profileCols)').eq('follower_id', userId).order('created_at', ascending: false).limit(200);
    return rows.map((r) => r['profiles']).whereType<Map<String, dynamic>>().map(Profile.fromMap).toList();
  }

  Future<List<Profile>> searchProfiles(String query, {int limit = 20}) async {
    final q = query.trim().replaceAll('%', '');
    if (q.isEmpty) return const [];
    final rows = await _client.from('profiles').select(profileCols).or('username.ilike.%$q%,display_name.ilike.%$q%').limit(limit);
    return rows.map(Profile.fromMap).toList();
  }

  // -------------------------------------------------------------- stories ---

  Future<List<StoryGroup>> fetchStories(String me) async {
    final results = await Future.wait<dynamic>([
      _client.from('stories').select(_storySelect).gt('expires_at', DateTime.now().toUtc().toIso8601String()).order('created_at'),
      _client.from('story_views').select('story_id').eq('viewer_id', me),
    ]);
    final stories = (results[0] as List).map((r) => Story.fromMap(r as Map<String, dynamic>)).toList();
    final seen = (results[1] as List).map((r) => r['story_id'] as String).toSet();
    final byAuthor = <String, List<Story>>{};
    for (final s in stories) {
      byAuthor.putIfAbsent(s.authorId, () => []).add(s);
    }
    final groups = byAuthor.values
        .where((list) => list.first.author != null)
        .map((list) => StoryGroup(author: list.first.author!, stories: list, allSeen: list.every((s) => seen.contains(s.id))))
        .toList();
    // Mine first, then unseen, then by newest.
    groups.sort((a, b) {
      if (a.author.id == me) return -1;
      if (b.author.id == me) return 1;
      if (a.allSeen != b.allSeen) return a.allSeen ? 1 : -1;
      return b.stories.last.createdAt.compareTo(a.stories.last.createdAt);
    });
    return groups;
  }

  Future<void> createStory({
    required String me,
    required String photoUrl,
    String? caption,
    double? lat,
    double? lng,
    String? eventId,
    String? placeId,
  }) =>
      _client.from('stories').insert({
        'author_id': me,
        'photo_url': photoUrl,
        'caption': ?caption?.trim(),
        'lat': ?lat,
        'lng': ?lng,
        'event_id': ?eventId,
        'place_id': ?placeId,
      });

  /// Live moments with a location, for the map (last 24 h).
  Future<List<Story>> fetchLiveMomentsInBounds({required double south, required double north, required double west, required double east, int limit = 60}) async {
    final rows = await _client
        .from('stories')
        .select(_storySelect)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .not('lat', 'is', null)
        .gte('lat', south)
        .lte('lat', north)
        .gte('lng', west)
        .lte('lng', east)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Story.fromMap).toList();
  }

  /// Album of a meet (all time, newest first).
  Future<List<Story>> fetchEventMoments(String eventId, {int limit = 60}) async {
    final rows = await _client.from('stories').select(_storySelect).eq('event_id', eventId).order('created_at', ascending: false).limit(limit);
    return rows.map(Story.fromMap).toList();
  }

  /// Album of a place: moments tagged to the place or to any meet held there.
  Future<List<Story>> fetchPlaceMoments(String placeId, {int limit = 60}) async {
    final rows = await _client.from('stories').select(_storySelect).eq('place_id', placeId).order('created_at', ascending: false).limit(limit);
    return rows.map(Story.fromMap).toList();
  }

  /// Someone's moments that were kept (tagged to a meet or place) plus live ones.
  Future<List<Story>> fetchUserMoments(String userId, {int limit = 90}) async {
    final rows = await _client
        .from('stories')
        .select(_storySelect)
        .eq('author_id', userId)
        .or('event_id.not.is.null,place_id.not.is.null,expires_at.gt.${DateTime.now().toUtc().toIso8601String()}')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Story.fromMap).toList();
  }

  Future<void> markStoryViewed(String storyId, String me) =>
      _client.from('story_views').upsert({'story_id': storyId, 'viewer_id': me});

  Future<void> deleteStory(String id) => _client.from('stories').delete().eq('id', id);

  // ------------------------------------------------------ car of the week ---

  Future<({Post post, int likes})?> currentWeekLeader() async {
    final rows = await _client.rpc('current_week_leader') as List;
    if (rows.isEmpty) return null;
    final r = rows.first as Map<String, dynamic>;
    final post = await fetchPost(r['post_id'] as String);
    if (post == null) return null;
    return (post: post, likes: (r['like_count'] as num).toInt());
  }

  Future<WeeklyWinner?> lastWinner() async {
    final row = await _client.from('weekly_winners').select().order('week_start', ascending: false).limit(1).maybeSingle();
    if (row == null) return null;
    final post = row['post_id'] == null ? null : await fetchPost(row['post_id'] as String);
    return WeeklyWinner(
      weekStart: DateTime.parse(row['week_start'] as String),
      post: post,
      likeCount: (row['like_count'] as num).toInt(),
    );
  }
}

final socialRepositoryProvider = Provider<SocialRepository>((ref) => SocialRepository(ref.watch(supabaseProvider)));
