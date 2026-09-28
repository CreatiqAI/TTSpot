/// One row of the host's "Who's here" list (RPC `event_checkin_list`).
class CheckinRow {
  const CheckinRow({
    required this.userId,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.car,
    required this.checkedInAt,
    required this.source,
    required this.stayedMin,
    required this.stayed,
    required this.confirmed,
    required this.rejected,
    this.carId,
    this.carCover,
  });

  final String userId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  /// The car they brought, "Make Model" (their default car when they didn't pick).
  final String? car;
  final String? carId;
  /// That car's portrait / first photo.
  final String? carCover;
  final DateTime checkedInAt;
  /// 'manual' | 'auto' | 'organizer' | 'qr'
  final String source;
  /// Minutes between the first and last location ping near the meet.
  final int stayedMin;
  /// 10+ minutes and 3+ pings near the meet.
  final bool stayed;
  /// Host said "Here" (or the big-meet auto-confirm did).
  final bool confirmed;
  /// Host said "Not here".
  final bool rejected;

  String get name => displayName ?? (username == null ? 'Member' : '@$username');

  factory CheckinRow.fromMap(Map<String, dynamic> m) => CheckinRow(
        userId: m['user_id'] as String,
        username: m['username'] as String?,
        displayName: m['display_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        car: m['car'] as String?,
        checkedInAt: DateTime.parse(m['checked_in_at'] as String).toLocal(),
        source: m['source'] as String? ?? 'manual',
        stayedMin: (m['stayed_min'] as num?)?.toInt() ?? 0,
        stayed: m['stayed'] == true,
        confirmed: m['confirmed'] == true,
        rejected: m['rejected'] == true,
        carId: m['car_id'] as String?,
        carCover: m['car_cover'] as String?,
      );
}

/// How a meet's arrivals get confirmed (RPC `meet_mode`).
enum MeetMode {
  /// Under 30 RSVPs, not official-club or partner: the host confirms by hand.
  small,
  /// Everyone who stayed 10+ min is confirmed on their own; the host sees exceptions.
  big;

  static MeetMode fromDb(String? v) => v == 'big' ? big : small;

  String get label => this == big ? 'Big meet · auto after 10 min, exceptions below' : 'Small meet · confirm arrivals';
}
