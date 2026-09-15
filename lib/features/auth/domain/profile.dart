/// A row from `public.profiles`.
class Profile {
  const Profile({
    required this.id,
    this.username,
    this.displayName,
    this.bio,
    this.avatarUrl,
    this.homeState,
    required this.createdAt,
    this.carCount,
    this.isAdmin = false,
    this.clubOwner = false,
    this.settings = const {},
  });

  final String id;
  final String? username;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final String? homeState;
  final DateTime createdAt;
  /// Only filled when fetched with the `cars(count)` embed (own profile).
  final int? carCount;
  final bool isAdmin;
  /// Approved to start and run car clubs (admin-reviewed application).
  final bool clubOwner;
  /// profiles.settings (see AppSettings).
  final Map<String, dynamic> settings;

  /// Admins can run clubs without applying.
  bool get canRunClubs => clubOwner || isAdmin;

  /// Step 1 of onboarding is complete once a username exists.
  bool get isOnboarded => username != null && username!.isNotEmpty;

  /// Step 2: every member needs at least one car in the garage.
  bool get needsCar => carCount == 0;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        username: m['username'] as String?,
        displayName: m['display_name'] as String?,
        bio: m['bio'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        homeState: m['home_state'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        carCount: _count(m['cars']),
        isAdmin: m['is_admin'] as bool? ?? false,
        clubOwner: m['club_owner'] as bool? ?? false,
        settings: (m['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  static int? _count(Object? embed) {
    if (embed is List && embed.isNotEmpty && embed.first is Map) {
      return ((embed.first as Map)['count'] as num?)?.toInt();
    }
    return null;
  }

  Profile copyWith({
    String? username,
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? homeState,
  }) =>
      Profile(
        id: id,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        bio: bio ?? this.bio,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        homeState: homeState ?? this.homeState,
        createdAt: createdAt,
        carCount: carCount,
        isAdmin: isAdmin,
        clubOwner: clubOwner,
        settings: settings,
      );
}
