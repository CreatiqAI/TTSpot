import '../../auth/domain/profile.dart';

enum NotificationType {
  follow, postLike, postComment, eventJoin, eventComment, eventReminder, eventCancelled, spottedClaim, badge, carOfWeek, clubJoin,
  friendRequest, friendAccepted, ttNow, checkin, referral, points, partner, voucher, clubInvite, clubRequest, clubEvent, partnerEvent, garage, clubOfficial, unknown;

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
        _ => unknown,
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
    this.clubId,
    this.clubName,
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
  final String? clubId;
  final String? clubName;
  final String? badgeId;
  final String? body;
  final bool read;
  final DateTime createdAt;

  factory AppNotification.fromMap(Map<String, dynamic> m) {
    final post = m['posts'] as Map<String, dynamic>?;
    final event = m['events'] as Map<String, dynamic>?;
    final club = m['clubs'] as Map<String, dynamic>?;
    final photos = (post?['photo_urls'] as List?)?.cast<String>();
    return AppNotification(
      id: m['id'] as String,
      type: NotificationType.fromDb(m['type'] as String),
      actor: m['actor'] == null ? null : Profile.fromMap(m['actor'] as Map<String, dynamic>),
      postId: m['post_id'] as String?,
      postCover: photos == null || photos.isEmpty ? null : photos.first,
      eventId: m['event_id'] as String?,
      eventTitle: event?['title'] as String?,
      clubId: m['club_id'] as String?,
      clubName: club?['name'] as String?,
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
