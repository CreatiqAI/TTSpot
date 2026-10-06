/// The official club tag someone shows beside their name (migration 0109).
///
/// The president of an official club always has one; members of an official
/// club wear it when they opt in (one club at a time). Underground clubs
/// never get one. The server decides: `club_tag` on a profiles row (a
/// computed field) or `club_tag_of(uuid)` returns it, or null.
class ClubTag {
  const ClubTag({required this.clubId, required this.name, this.handle, this.avatarUrl, this.role = 'member'});

  final String clubId;
  final String name;
  final String? handle;
  final String? avatarUrl;

  /// 'owner' (the president), 'vp', 'secretary' or 'member'.
  final String role;

  bool get isPresident => role == 'owner';

  /// Null when [v] is not a tag (no tag, or an older server).
  static ClubTag? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = v['club_id'];
    final name = v['name'];
    if (id is! String || name is! String || name.trim().isEmpty) return null;
    return ClubTag(clubId: id, name: name.trim(), handle: v['handle'] as String?, avatarUrl: v['avatar_url'] as String?, role: v['role'] as String? ?? 'member');
  }

  @override
  bool operator ==(Object other) => other is ClubTag && other.clubId == clubId && other.name == name && other.avatarUrl == avatarUrl && other.role == role;

  @override
  int get hashCode => Object.hash(clubId, name, avatarUrl, role);
}
