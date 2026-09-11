import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_art.dart';
import '../../auth/domain/profile.dart';

class Club {
  const Club({
    required this.id,
    required this.name,
    required this.handle,
    this.description,
    this.avatarUrl,
    this.homeState,
    required this.ownerId,
    required this.createdAt,
    required this.memberCount,
  });

  final String id;
  final String name;
  final String handle;
  final String? description;
  final String? avatarUrl;
  final String? homeState;
  final String ownerId;
  final DateTime createdAt;
  final int memberCount;

  factory Club.fromMap(Map<String, dynamic> m) {
    final members = m['members'];
    var count = 0;
    if (members is List && members.isNotEmpty && members.first is Map) {
      count = ((members.first as Map)['count'] as num?)?.toInt() ?? 0;
    }
    return Club(
      id: m['id'] as String,
      name: m['name'] as String,
      handle: m['handle'] as String,
      description: m['description'] as String?,
      avatarUrl: m['avatar_url'] as String?,
      homeState: m['home_state'] as String?,
      ownerId: m['owner_id'] as String,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      memberCount: count,
    );
  }
}

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.kind,
    required this.lat,
    required this.lng,
    required this.createdAt,
    this.pastMeets = 0,
    this.upcomingMeets = 0,
    this.checkinsTotal = 0,
    this.lastMeetAt,
    this.coverUrl,
    this.description,
    this.tags = const [],
    this.recommended = false,
    this.spotCheckins = 0,
    this.postCount = 0,
    this.momentCount = 0,
    this.score = 0,
  });
  final String id;
  final String name;
  final String kind;
  final double lat;
  final double lng;
  final DateTime createdAt;
  // From the `places_with_counts` view (zero when read from `places`).
  final int pastMeets;
  final int upcomingMeets;
  final int checkinsTotal;
  final DateTime? lastMeetAt;
  final String? coverUrl;
  final String? description;
  final List<String> tags;
  final bool recommended;
  /// Stand-alone check-ins (打卡) at the spot, without a meet.
  final int spotCheckins;
  final int postCount;
  final int momentCount;
  /// Ranking used for the Spots layer and the feed tab.
  final int score;

  LatLng get latLng => LatLng(lat, lng);
  int get totalCheckins => checkinsTotal + spotCheckins;

  String get kindLabel => switch (kind) {
        'mamak' => 'Mamak',
        'carpark' => 'Carpark',
        'circuit' => 'Circuit',
        'mall' => 'Mall',
        'route' => 'Route',
        _ => 'Place',
      };
  /// 3D illustration for the place kind, see [AppArt].
  String get kindArt => switch (kind) {
        'mamak' => AppArt.coffee,
        'carpark' => AppArt.parking,
        'circuit' => AppArt.racing,
        'mall' => AppArt.mall,
        'route' => AppArt.road,
        _ => AppArt.pin,
      };
  String get kindEmoji => switch (kind) {
        'mamak' => '☕',
        'carpark' => '🅿️',
        'circuit' => '🏁',
        'mall' => '🏬',
        'route' => '🛣️',
        _ => '📍',
      };

  factory Place.fromMap(Map<String, dynamic> m) => Place(
        id: m['id'] as String,
        name: m['name'] as String,
        kind: m['kind'] as String? ?? 'other',
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        pastMeets: (m['past_meets'] as num?)?.toInt() ?? 0,
        upcomingMeets: (m['upcoming_meets'] as num?)?.toInt() ?? 0,
        checkinsTotal: (m['checkins_total'] as num?)?.toInt() ?? 0,
        lastMeetAt: m['last_meet_at'] == null ? null : DateTime.parse(m['last_meet_at'] as String).toLocal(),
        coverUrl: m['cover_url'] as String?,
        description: m['description'] as String?,
        tags: ((m['tags'] as List?) ?? const []).cast<String>(),
        recommended: m['recommended'] as bool? ?? false,
        spotCheckins: (m['spot_checkins'] as num?)?.toInt() ?? 0,
        postCount: (m['post_count'] as num?)?.toInt() ?? 0,
        momentCount: (m['moment_count'] as num?)?.toInt() ?? 0,
        score: (m['score'] as num?)?.toInt() ?? 0,
      );
}

/// Someone who checked in at a spot, with when.
class PlaceVisit {
  const PlaceVisit({required this.profile, required this.at});
  final Profile profile;
  final DateTime at;
}

/// Someone who keeps coming back to a place.
class PlaceRegular {
  const PlaceRegular({required this.profile, required this.visits});
  final Profile profile;
  final int visits;
}

class CarMod {
  const CarMod({required this.id, required this.carId, required this.title, this.description, this.cost, required this.doneOn, required this.photoUrls, required this.createdAt});
  final String id;
  final String carId;
  final String title;
  final String? description;
  final double? cost;
  final DateTime doneOn;
  final List<String> photoUrls;
  final DateTime createdAt;

  factory CarMod.fromMap(Map<String, dynamic> m) => CarMod(
        id: m['id'] as String,
        carId: m['car_id'] as String,
        title: m['title'] as String,
        description: m['description'] as String?,
        cost: (m['cost'] as num?)?.toDouble(),
        doneOn: DateTime.parse(m['done_on'] as String),
        photoUrls: ((m['photo_urls'] as List?) ?? const []).cast<String>(),
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}
