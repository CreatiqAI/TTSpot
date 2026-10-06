import '../../profile/domain/car.dart';
import 'club_tag.dart';

/// One row of a club's members page (`club_members_list`, migration 0111):
/// the person, their role in the club, the club tag they show and their
/// default car (the one marked default, else their newest).
class ClubMemberEntry {
  const ClubMemberEntry({
    required this.userId,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.role = 'member',
    this.joinedAt,
    this.clubTag,
    this.car,
  });

  final String userId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  /// 'owner' (the president), 'vp', 'secretary' or 'member'.
  final String role;
  final DateTime? joinedAt;
  final ClubTag? clubTag;

  /// Only what a thumbnail needs (make, model, cover, toy, body style).
  final Car? car;

  String get name => (displayName ?? '').trim().isNotEmpty ? displayName!.trim() : '@${username ?? ''}';

  bool get isOfficer => role == 'owner' || role == 'vp' || role == 'secretary';

  /// "2019 Perodua Myvi 1.5 AV", or null without a car.
  String? get carLine {
    final c = car;
    if (c == null) return null;
    final title = '${c.make} ${c.model}'.trim();
    if (title.isEmpty) return null;
    return c.year == null ? title : '${c.year} $title';
  }

  /// Does [query] (lower case, trimmed) match their name, handle or car?
  bool matches(String query) {
    if (query.isEmpty) return true;
    return [displayName ?? '', username ?? '', carLine ?? ''].any((s) => s.toLowerCase().contains(query));
  }

  factory ClubMemberEntry.fromMap(Map<String, dynamic> m) {
    Car? car;
    final raw = m['car'];
    if (raw is Map) {
      try {
        car = Car.fromMap(raw.cast<String, dynamic>());
      } catch (_) {
        car = null; // a car row we can't read: no thumbnail, the person still shows
      }
    }
    return ClubMemberEntry(
      userId: m['user_id'] as String,
      username: m['username'] as String?,
      displayName: m['display_name'] as String?,
      avatarUrl: m['avatar_url'] as String?,
      role: m['role'] as String? ?? 'member',
      joinedAt: m['joined_at'] == null ? null : DateTime.tryParse(m['joined_at'] as String)?.toLocal(),
      clubTag: ClubTag.fromJson(m['club_tag']),
      car: car,
    );
  }
}

/// Show the members search box above this many.
const kClubMembersSearchFrom = 12;
