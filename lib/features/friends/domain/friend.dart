import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../auth/domain/profile.dart';

/// Mirrors the strings returned by `friendship_status()`.
enum FriendshipStatus {
  none,
  pendingOut,
  pendingIn,
  friends;

  static FriendshipStatus fromDb(String? v) => switch (v) {
        'friends' => friends,
        'pending_out' => pendingOut,
        'pending_in' => pendingIn,
        _ => none,
      };
}

/// A pending request someone sent me.
/// Someone worth adding, and the one-line reason why.
class FriendSuggestion {
  const FriendSuggestion({required this.profile, required this.reason});
  final Profile profile;
  final String reason;
}

class FriendRequest {
  const FriendRequest({required this.from, required this.createdAt});
  final Profile from;
  final DateTime createdAt;
}

/// A friend's last known position (row from `user_locations` + embeds).
class FriendPin {
  const FriendPin({
    required this.user,
    required this.lat,
    required this.lng,
    required this.updatedAt,
    this.placeId,
    this.placeName,
    this.eventId,
    this.eventTitle,
    this.ghost = false,
    this.viaClub = false,
    this.clubName,
  });

  /// True when I only see this person because we share a car club.
  final bool viaClub;
  final String? clubName;

  final Profile user;
  final double lat;
  final double lng;
  final DateTime updatedAt;
  final String? placeId;
  final String? placeName;
  final String? eventId;
  final String? eventTitle;
  final bool ghost;

  LatLng get latLng => LatLng(lat, lng);

  /// Fresh enough to draw as "here now" (otherwise "last seen").
  bool get isFresh => DateTime.now().difference(updatedAt) < const Duration(minutes: 20);

  factory FriendPin.fromMap(Map<String, dynamic> m) => FriendPin(
        user: Profile.fromMap(m['profiles'] as Map<String, dynamic>),
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        updatedAt: DateTime.parse(m['updated_at'] as String).toLocal(),
        ghost: m['ghost'] as bool? ?? false,
        placeId: m['place_id'] as String?,
        placeName: (m['places'] as Map<String, dynamic>?)?['name'] as String?,
        eventId: m['event_id'] as String?,
        eventTitle: (m['events'] as Map<String, dynamic>?)?['title'] as String?,
        viaClub: m['via'] == 'club',
        clubName: m['club_name'] as String?,
      );
}

/// My own `user_locations` row (ghost flag + where the server thinks I am).
class MyLocation {
  const MyLocation({required this.ghost, this.placeId, this.placeName, this.eventId, this.updatedAt});
  final bool ghost;
  final String? placeId;
  final String? placeName;
  final String? eventId;
  final DateTime? updatedAt;

  static const unknown = MyLocation(ghost: false);

  factory MyLocation.fromMap(Map<String, dynamic> m) => MyLocation(
        ghost: m['ghost'] as bool? ?? false,
        placeId: m['place_id'] as String?,
        placeName: (m['places'] as Map<String, dynamic>?)?['name'] as String?,
        eventId: m['event_id'] as String?,
        updatedAt: m['updated_at'] == null ? null : DateTime.parse(m['updated_at'] as String).toLocal(),
      );
}

/// What `update_my_location` tells the app after each ping.
class LocationPing {
  const LocationPing({this.placeId, this.placeName, this.checkedInEventId, this.nearbyEventId, this.nearbyEventTitle});
  final String? placeId;
  final String? placeName;
  final String? checkedInEventId;
  final String? nearbyEventId;
  final String? nearbyEventTitle;

  factory LocationPing.fromMap(Map<String, dynamic> m) => LocationPing(
        placeId: m['place_id'] as String?,
        placeName: m['place_name'] as String?,
        checkedInEventId: m['checked_in_event_id'] as String?,
        nearbyEventId: m['nearby_event_id'] as String?,
        nearbyEventTitle: m['nearby_event_title'] as String?,
      );
}
