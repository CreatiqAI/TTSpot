import '../../auth/domain/profile.dart';

enum NotificationType {
  follow, postLike, postComment, eventJoin, eventComment, eventReminder, eventCancelled, spottedClaim, badge, carOfWeek, clubJoin,
  friendRequest, friendAccepted, ttNow, checkin, referral, points, partner, voucher, clubInvite, clubRequest, clubEvent, partnerEvent, garage, clubOfficial, cards, portrait, meetStart, announcement, luckyDraw, carDoc,
  friendPost, friendTt, clubMember,
  mention, commentReply, commentLike, clubPost, clubMeet,
  // TiTi's own daily line (titi-nudge); the body is the whole message.
  titiNudge, unknown;

  static NotificationType fromDb(String v) => switch (v) {
        'follow' => follow,
        'post_like' => postLike,
        'post_comment' => postComment,
        'event_join' => eventJoin,
        'event_comment' => eventComment,
        'event_reminder' => eventReminder,
        'event_cancelled' => eventCancelled,
        'spotted_claim' => spottedClaim,
        'badge' => badge,
        'car_of_week' => carOfWeek,
        'club_join' => clubJoin,
        'friend_request' => friendRequest,
        'friend_accepted' => friendAccepted,
        'tt_now' => ttNow,
        'checkin' => checkin,
        'referral' => referral,
        'points' => points,
        'partner' => partner,
        'voucher' => voucher,
        'club_invite' => clubInvite,
        'club_request' => clubRequest,
        'club_event' => clubEvent,
        'partner_event' => partnerEvent,
        'garage' => garage,
        'club_official' => clubOfficial,
        'cards' => cards,
        'portrait' => portrait,
        'meet_start' => meetStart,
        'announcement' => announcement,
        'lucky_draw' => luckyDraw,
        'car_doc' => carDoc,
        'friend_post' => friendPost,
        'friend_tt' => friendTt,
        'club_member' => clubMember,
        'mention' => mention,
        'comment_reply' => commentReply,
        'comment_like' => commentLike,
        'club_post' => clubPost,
        'club_meet' => clubMeet,
        'titi_nudge' => titiNudge,
        _ => unknown,
      };
}

/// A friend_post row's body is `what:first 60 characters` (what = photo,
/// video, poll, guide or spotted); the same wording as the push.
String friendPostText(String? body) {
  final s = body ?? '';
  final i = s.indexOf(':');
  final what = i < 0 ? 'photo' : s.substring(0, i);
  final text = (i < 0 ? s : s.substring(i + 1)).trim();
  if (text.isNotEmpty) return what == 'spotted' ? 'spotted a car: $text' : 'posted: $text';
  return switch (what) {
    'video' => 'posted a new video.',
    'poll' => 'posted a new poll.',
    'guide' => 'shared a new guide.',
    'spotted' => 'spotted a car.',
    _ => 'posted a new photo.',
  };
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    this.actor,
    this.postId,
    this.postCover,
    this.eventId,
    this.eventTitle,
    this.eventVenue,
    this.eventStartsAt,
    this.eventInstant = false,
    this.clubId,
    this.clubName,
    this.clubAvatarUrl,
    this.commentId,
    this.badgeId,
    this.body,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final NotificationType type;
  final Profile? actor;
  final String? postId;
  final String? postCover;
  final String? eventId;
  final String? eventTitle;
  final String? eventVenue;
  final DateTime? eventStartsAt;

  /// TT now (else a session planned for later).
  final bool eventInstant;
  final String? clubId;
  final String? clubName;
  final String? clubAvatarUrl;

  /// The comment it is about (post_comment, comment_reply, comment_like,
  /// and a mention in a comment); null for a mention in the post itself.
  final String? commentId;
  final String? badgeId;
  final String? body;
  final bool read;
  final DateTime createdAt;

  factory AppNotification.fromMap(Map<String, dynamic> m) {
    final post = m['posts'] as Map<String, dynamic>?;
    final event = m['events'] as Map<String, dynamic>?;
    final club = m['clubs'] as Map<String, dynamic>?;
    final photos = (post?['photo_urls'] as List?)?.cast<String>();
    final poster = post?['video_poster_url'] as String?;
    final starts = event?['starts_at'] as String?;
    return AppNotification(
      id: m['id'] as String,
      type: NotificationType.fromDb(m['type'] as String),
      actor: m['actor'] == null ? null : Profile.fromMap(m['actor'] as Map<String, dynamic>),
      postId: m['post_id'] as String?,
      postCover: photos == null || photos.isEmpty ? poster : photos.first,
      eventId: m['event_id'] as String?,
      eventTitle: event?['title'] as String?,
      eventVenue: event?['venue_name'] as String?,
      eventStartsAt: starts == null ? null : DateTime.parse(starts).toLocal(),
      eventInstant: event?['is_instant'] == true,
      clubId: m['club_id'] as String?,
      clubName: club?['name'] as String?,
      clubAvatarUrl: club?['avatar_url'] as String?,
      commentId: m['comment_id'] as String?,
      badgeId: m['badge_id'] as String?,
      body: m['body'] as String?,
      read: m['read_at'] != null,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    );
  }
}

class AppBadge {
  const AppBadge({required this.id, required this.name, required this.description, required this.emoji, required this.sort});
  final String id;
  final String name;
  final String description;
  final String emoji;
  final int sort;

  factory AppBadge.fromMap(Map<String, dynamic> m) => AppBadge(
        id: m['id'] as String,
        name: m['name'] as String,
        description: m['description'] as String,
        emoji: m['emoji'] as String,
        sort: (m['sort'] as num?)?.toInt() ?? 100,
      );
}

class EarnedBadge {
  const EarnedBadge({required this.badge, required this.awardedAt});
  final AppBadge badge;
  final DateTime awardedAt;
}
