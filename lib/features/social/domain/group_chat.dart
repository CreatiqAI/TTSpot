import '../../auth/domain/profile.dart';

/// Group chats: a friends' group (conversations.kind 'group') or a club's
/// members chat ('club'). Rules live in 20261005000100_group_chats.sql.
const kGroupMaxMembers = 100;
const kGroupNameMax = 60;
/// Friends you pick to start a group (you make the third).
const kGroupMinFriends = 2;

/// One person in a group chat.
class GroupMember {
  const GroupMember({required this.profile, this.isAdmin = false, this.joinedAt});
  final Profile profile;
  /// A friends' group admin (the creator is the first). Club chats use the club's officers instead.
  final bool isAdmin;
  final DateTime? joinedAt;

  String get id => profile.id;

  factory GroupMember.fromMap(Map<String, dynamic> m) => GroupMember(
        profile: Profile.fromMap(m['profiles'] as Map<String, dynamic>),
        isAdmin: m['is_admin'] as bool? ?? false,
        joinedAt: m['created_at'] == null ? null : DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

/// A short name for someone in a list of names: their first word, else the @handle.
String shortNameOf(Profile p) {
  final d = (p.displayName ?? '').trim();
  if (d.isNotEmpty) return d.split(RegExp(r'\s+')).first;
  final u = (p.username ?? '').trim();
  return u.isEmpty ? 'Member' : '@$u';
}

/// The title of a group nobody named yet: the people in it, like WhatsApp.
/// "Aiman", "Aiman and Bala", "Aiman, Bala and Chong", "Aiman, Bala, Chong and 4 more".
String groupAutoName(List<String> names) {
  final n = [for (final s in names) if (s.trim().isNotEmpty) s.trim()];
  if (n.isEmpty) return 'Group chat';
  if (n.length == 1) return n.first;
  if (n.length <= 3) return '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
  return '${n.take(3).join(', ')} and ${n.length - 3} more';
}
