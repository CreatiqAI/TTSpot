import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../auth/domain/profile.dart';

enum PostKind {
  post('post', 'Post'),
  spotted('spotted', 'Spotted'),
  poll('poll', 'Poll'),
  guide('guide', 'Guide');

  const PostKind(this.db, this.label);
  final String db;
  final String label;
  static PostKind fromDb(String v) => PostKind.values.firstWhere((k) => k.db == v, orElse: () => PostKind.post);
}

class PollOption {
  const PollOption({required this.text, this.photoUrl});
  final String text;
  final String? photoUrl;
  Map<String, dynamic> toJson() => {'text': text, 'photo_url': photoUrl};
  factory PollOption.fromJson(Map<String, dynamic> j) =>
      PollOption(text: j['text'] as String? ?? '', photoUrl: j['photo_url'] as String?);
}

class GuideStop {
  const GuideStop({required this.name, required this.lat, required this.lng});
  final String name;
  final double lat;
  final double lng;
  LatLng get latLng => LatLng(lat, lng);
  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lng': lng};
  factory GuideStop.fromJson(Map<String, dynamic> j) => GuideStop(
        name: j['name'] as String? ?? '',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );
}

/// Lightweight references embedded on a post.
class CarRef {
  const CarRef({required this.id, required this.make, required this.model});
  final String id;
  final String make;
  final String model;
  String get title => '$make $model';
}

class NamedRef {
  const NamedRef({required this.id, required this.name, this.handle, this.avatarUrl});
  final String id;
  final String name;
  final String? handle;
  final String? avatarUrl;
}

/// A row from `posts` with embeds and counts.
class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.kind,
    this.title,
    this.caption,
    required this.photoUrls,
    required this.coverAspect,
    this.car,
    this.place,
    this.event,
    this.club,
    this.asClub = false,
    this.lat,
    this.lng,
    this.claimedBy,
    this.claimer,
    this.pollOptions,
    this.pollEndsAt,
    this.guideStops,
    required this.createdAt,
    this.author,
    required this.likeCount,
    required this.commentCount,
    required this.voteCount,
  });

  final String id;
  final String authorId;
  final PostKind kind;
  final String? title;
  final String? caption;
  final List<String> photoUrls;
  final double coverAspect;
  final CarRef? car;
  final NamedRef? place;
  final NamedRef? event;
  final NamedRef? club;
  /// Published under the club's name (by its owner or an admin).
  final bool asClub;
  final double? lat;
  final double? lng;
  final String? claimedBy;
  final Profile? claimer;
  final List<PollOption>? pollOptions;
  final DateTime? pollEndsAt;
  final List<GuideStop>? guideStops;
  final DateTime createdAt;
  final Profile? author;
  final int likeCount;
  final int commentCount;
  final int voteCount;

  String? get cover => photoUrls.isEmpty ? null : photoUrls.first;
  LatLng? get latLng => lat == null || lng == null ? null : LatLng(lat!, lng!);
  bool get pollClosed => pollEndsAt != null && pollEndsAt!.isBefore(DateTime.now());

  static int _count(dynamic v) {
    if (v is List && v.isNotEmpty && v.first is Map) return ((v.first as Map)['count'] as num?)?.toInt() ?? 0;
    if (v is Map) return (v['count'] as num?)?.toInt() ?? 0;
    return 0;
  }

  factory Post.fromMap(Map<String, dynamic> m) {
    final carM = m['car'] as Map<String, dynamic>?;
    final placeM = m['place'] as Map<String, dynamic>?;
    final eventM = m['event'] as Map<String, dynamic>?;
    final clubM = m['club'] as Map<String, dynamic>?;
    final authorM = m['author'] as Map<String, dynamic>?;
    final claimerM = m['claimer'] as Map<String, dynamic>?;
    return Post(
      id: m['id'] as String,
      authorId: m['author_id'] as String,
      kind: PostKind.fromDb(m['kind'] as String),
      title: m['title'] as String?,
      caption: m['caption'] as String?,
      photoUrls: ((m['photo_urls'] as List?) ?? const []).cast<String>(),
      coverAspect: (m['cover_aspect'] as num?)?.toDouble() ?? 1.0,
      car: carM == null ? null : CarRef(id: carM['id'] as String, make: carM['make'] as String, model: carM['model'] as String),
      place: placeM == null ? null : NamedRef(id: placeM['id'] as String, name: placeM['name'] as String),
      event: eventM == null ? null : NamedRef(id: eventM['id'] as String, name: eventM['title'] as String),
      club: clubM == null ? null : NamedRef(id: clubM['id'] as String, name: clubM['name'] as String, handle: clubM['handle'] as String?, avatarUrl: clubM['avatar_url'] as String?),
      asClub: m['as_club'] as bool? ?? false,
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      claimedBy: m['claimed_by'] as String?,
      claimer: claimerM == null ? null : Profile.fromMap(claimerM),
      pollOptions: (m['poll_options'] as List?)?.map((o) => PollOption.fromJson(o as Map<String, dynamic>)).toList(),
      pollEndsAt: m['poll_ends_at'] == null ? null : DateTime.parse(m['poll_ends_at'] as String).toLocal(),
      guideStops: (m['guide_stops'] as List?)?.map((s) => GuideStop.fromJson(s as Map<String, dynamic>)).toList(),
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      author: authorM == null ? null : Profile.fromMap(authorM),
      likeCount: _count(m['likes']),
      commentCount: _count(m['comments']),
      voteCount: _count(m['votes']),
    );
  }
}

/// A post plus what the viewer has done with it.
class FeedPost {
  const FeedPost({required this.post, required this.likedByMe, required this.savedByMe, this.myVote});
  final Post post;
  final bool likedByMe;
  final bool savedByMe;
  final int? myVote;

  FeedPost copyWith({Post? post, bool? likedByMe, bool? savedByMe, int? myVote, bool clearVote = false}) => FeedPost(
        post: post ?? this.post,
        likedByMe: likedByMe ?? this.likedByMe,
        savedByMe: savedByMe ?? this.savedByMe,
        myVote: clearVote ? null : (myVote ?? this.myVote),
      );
}

class PostComment {
  const PostComment({required this.id, required this.postId, required this.userId, required this.body, required this.createdAt, this.author});
  final String id;
  final String postId;
  final String userId;
  final String body;
  final DateTime createdAt;
  final Profile? author;

  factory PostComment.fromMap(Map<String, dynamic> m) => PostComment(
        id: m['id'] as String,
        postId: m['post_id'] as String,
        userId: m['user_id'] as String,
        body: m['body'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        author: m['profiles'] == null ? null : Profile.fromMap(m['profiles'] as Map<String, dynamic>),
      );
}

/// A "moment": one photo, 24 h on the map, kept in the album of the meet or
/// place it was taken at.
class Story {
  const Story({
    required this.id,
    required this.authorId,
    required this.photoUrl,
    this.caption,
    required this.createdAt,
    required this.expiresAt,
    this.author,
    this.lat,
    this.lng,
    this.eventId,
    this.eventTitle,
    this.placeId,
    this.placeName,
  });
  final String id;
  final String authorId;
  final String photoUrl;
  final String? caption;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Profile? author;
  final double? lat;
  final double? lng;
  final String? eventId;
  final String? eventTitle;
  final String? placeId;
  final String? placeName;

  bool get isLive => expiresAt.isAfter(DateTime.now());
  LatLng? get latLng => lat == null || lng == null ? null : LatLng(lat!, lng!);

  /// "TTDI Thursday TT" / "Mamak Sri Melur"
  String? get whereLabel => eventTitle ?? placeName;

  factory Story.fromMap(Map<String, dynamic> m) => Story(
        id: m['id'] as String,
        authorId: m['author_id'] as String,
        photoUrl: m['photo_url'] as String,
        caption: m['caption'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        expiresAt: DateTime.parse(m['expires_at'] as String).toLocal(),
        author: m['profiles'] == null ? null : Profile.fromMap(m['profiles'] as Map<String, dynamic>),
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        eventId: m['event_id'] as String?,
        eventTitle: (m['events'] as Map<String, dynamic>?)?['title'] as String?,
        placeId: m['place_id'] as String?,
        placeName: (m['places'] as Map<String, dynamic>?)?['name'] as String?,
      );
}

/// One author's stories, in order, with whether the viewer has seen them all.
class StoryGroup {
  const StoryGroup({required this.author, required this.stories, required this.allSeen, this.label, this.albumId});
  final Profile author;
  final List<Story> stories;
  final bool allSeen;
  /// Shown instead of the time (an album name).
  final String? label;
  /// Set when these moments come from an album (owner gets Edit / Delete).
  final String? albumId;
}

class WeeklyWinner {
  const WeeklyWinner({required this.weekStart, required this.post, required this.likeCount});
  final DateTime weekStart;
  final Post? post;
  final int likeCount;
}
