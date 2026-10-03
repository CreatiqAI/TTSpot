/// What a member can follow without being friends or joining: a driver, a
/// club or a partner (migration 0095). What I follow lands in Home's
/// Following and ranks higher in For you.
enum FollowKind { person, club, partner }

/// One account to follow. A record, so it works as a provider key.
typedef FollowTarget = ({FollowKind kind, String id});

/// "1 follower", "128 followers", "1,204 followers".
String followersLabel(int n) {
  final grouped = n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return n == 1 ? '1 follower' : '$grouped followers';
}
