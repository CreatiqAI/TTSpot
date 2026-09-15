import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_art.dart';

/// Mirrors the Postgres enum `event_type`.
enum EventType {
  meet('meet', 'Meet', '🚗', AppArt.car, Color(0xFFFF3D1F)),
  tt('tt', 'TT session', '☕', AppArt.coffee, Color(0xFFF5A524)),
  convoy('convoy', 'Convoy', '🛣️', AppArt.road, Color(0xFF3B82F6)),
  trackday('trackday', 'Track day', '🏁', AppArt.flag, Color(0xFF22C55E)),
  charity('charity', 'Charity', '💛', AppArt.heartYellow, Color(0xFFEC4899)),
  official('official', 'Official', '🏆', AppArt.trophy, Color(0xFFA855F7));

  const EventType(this.db, this.label, this.emoji, this.art, this.color);

  /// Value stored in the database.
  final String db;
  final String label;
  final String emoji;
  /// 3D illustration (asset path), see [AppArt].
  final String art;
  final Color color;

  /// What the New meet form offers. TT is the instant "TT now" kind.
  static const pickable = [EventType.meet, EventType.convoy, EventType.trackday];

  static EventType fromDb(String value) =>
      EventType.values.firstWhere((t) => t.db == value, orElse: () => EventType.meet);
}

enum EventStatus { active, cancelled }

/// A row from `events` (or the `events_with_counts` view).
class Event {
  const Event({
    required this.id,
    required this.organizerId,
    required this.title,
    this.description,
    required this.type,
    this.coverUrl,
    required this.startsAt,
    this.endsAt,
    required this.venueName,
    required this.lat,
    required this.lng,
    this.maxAttendees,
    required this.status,
    required this.attendeeCount,
    this.checkinCount = 0,
    required this.createdAt,
    this.placeId,
    this.clubId,
    this.isInstant = false,
    this.friendsOnly = false,
    this.address,
    this.vendorId,
    this.vendorName,
    this.vendorLogoUrl,
  });

  final String id;
  final String organizerId;
  final String title;
  final String? description;
  final EventType type;
  final String? coverUrl;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String venueName;
  final double lat;
  final double lng;
  final int? maxAttendees;
  final EventStatus status;
  final int attendeeCount;
  final int checkinCount;
  final DateTime createdAt;
  final String? placeId;
  final String? clubId;
  final bool isInstant;
  /// Set when a partner business hosts it.
  final String? vendorId;
  final String? vendorName;
  final String? vendorLogoUrl;
  /// `visibility = 'friends'`: only the organiser's friends, club members and attendees see it.
  final bool friendsOnly;
  /// Street address from Google, when the venue was picked by search.
  final String? address;

  LatLng get latLng => LatLng(lat, lng);
  bool get isCancelled => status == EventStatus.cancelled;
  bool get isFull => maxAttendees != null && attendeeCount >= maxAttendees!;

  /// When the meet is over (explicit end, else 6 h after start). Mirrors `event_live_window`.
  DateTime get closesAt => endsAt ?? startsAt.add(const Duration(hours: 6));
  DateTime get opensAt => startsAt.subtract(const Duration(hours: 1));

  bool get isPast => closesAt.isBefore(DateTime.now());

  /// Inside the check-in window (1 h before start until it closes).
  bool get isLive {
    if (isCancelled) return false;
    final now = DateTime.now();
    return now.isAfter(opensAt) && now.isBefore(closesAt);
  }

  factory Event.fromMap(Map<String, dynamic> m) => Event(
        id: m['id'] as String,
        organizerId: m['organizer_id'] as String,
        title: m['title'] as String,
        description: m['description'] as String?,
        type: EventType.fromDb(m['event_type'] as String),
        coverUrl: m['cover_url'] as String?,
        startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
        endsAt: m['ends_at'] == null ? null : DateTime.parse(m['ends_at'] as String).toLocal(),
        venueName: m['venue_name'] as String,
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        maxAttendees: m['max_attendees'] as int?,
        status: m['status'] == 'cancelled' ? EventStatus.cancelled : EventStatus.active,
        attendeeCount: (m['attendee_count'] as num?)?.toInt() ?? 0,
        checkinCount: (m['checkin_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        placeId: m['place_id'] as String?,
        clubId: m['club_id'] as String?,
        isInstant: m['is_instant'] as bool? ?? false,
        friendsOnly: m['visibility'] == 'friends',
        address: m['address'] as String?,
        vendorId: m['vendor_id'] as String?,
        vendorName: m['vendor_name'] as String?,
        vendorLogoUrl: m['vendor_logo_url'] as String?,
      );
}
