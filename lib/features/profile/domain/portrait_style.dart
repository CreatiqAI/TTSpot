import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';

/// One look the member can ask for. The prompt itself lives server-side in
/// supabase/functions/car-portrait (STYLES); the ids here must match its keys.
class PortraitStyle {
  const PortraitStyle({required this.id, required this.name, required this.description, required this.tint, required this.icon, this.referenceUrl});

  /// Sent to the edge function and stored in car_portraits.style.
  final String id;
  final String name;
  /// One line for the picker.
  final String description;
  /// Placeholder tile colour until we have curated reference art.
  final Color tint;
  final IconData icon;
  /// Curated example image for the picker tile (none yet; placeholders for now).
  final String? referenceUrl;

  static PortraitStyle? byId(String id) => kPortraitStyles.where((s) => s.id == id).firstOrNull;
}

/// Mirror of STYLES in supabase/functions/car-portrait/index.ts.
const kPortraitStyles = <PortraitStyle>[
  PortraitStyle(id: 'showroom', name: 'Showroom', description: 'Studio lights, glossy floor, nothing else in frame.', tint: Color(0xFF2E3440), icon: AppIcons.star),
  PortraitStyle(id: 'night_city', name: 'Night city', description: 'Neon reflections on wet Kuala Lumpur streets.', tint: Color(0xFF3B2A7A), icon: AppIcons.moon),
  PortraitStyle(id: 'golden_hour', name: 'Golden hour', description: 'Warm sunset light on an empty coastal road.', tint: Color(0xFFD9822B), icon: AppIcons.roadHorizon),
  PortraitStyle(id: 'race_poster', name: 'Race poster', description: 'Bold motorsport poster with motion streaks.', tint: Color(0xFFE00008), icon: AppIcons.flagCheckered),
  PortraitStyle(id: 'pastel_dream', name: 'Pastel dream', description: 'Soft pastel colours, dreamy and minimal.', tint: Color(0xFFE8A0BF), icon: AppIcons.heart),
  PortraitStyle(id: 'film', name: '35mm film', description: 'Grainy analogue photo, faded colours.', tint: Color(0xFF7A6A4F), icon: AppIcons.camera),
  PortraitStyle(id: 'track_day', name: 'Track day', description: 'On the circuit, panning shot, tyres working.', tint: Color(0xFF1F7A5C), icon: AppIcons.timer),
  PortraitStyle(id: 'line_art', name: 'Line art', description: 'Clean technical line drawing on white.', tint: Color(0xFF6B7280), icon: AppIcons.pencilSimple),
];

enum PortraitStatus {
  pending, ready, failed;

  static PortraitStatus fromDb(String v) => switch (v) {
        'ready' => ready,
        'failed' => failed,
        _ => pending,
      };
}

/// A row from `car_portraits`: one generation job for one car.
class CarPortrait {
  const CarPortrait({
    required this.id,
    required this.carId,
    required this.styleId,
    required this.status,
    this.url,
    this.error,
    required this.createdAt,
    this.readyAt,
    this.pointsSpent = 0,
    this.refunded = false,
  });

  final String id;
  final String carId;
  final String styleId;
  final PortraitStatus status;
  final String? url;
  final String? error;
  final DateTime createdAt;
  final DateTime? readyAt;
  /// What it cost (0 for the free ones made before portraits cost points).
  final int pointsSpent;
  /// A failed job's points went back.
  final bool refunded;

  PortraitStyle? get style => PortraitStyle.byId(styleId);
  bool get isPending => status == PortraitStatus.pending;
  bool get isReady => status == PortraitStatus.ready && url != null;

  factory CarPortrait.fromMap(Map<String, dynamic> m) => CarPortrait(
        id: m['id'] as String,
        carId: m['car_id'] as String,
        styleId: m['style'] as String,
        status: PortraitStatus.fromDb(m['status'] as String? ?? 'pending'),
        url: m['url'] as String?,
        error: m['error'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        readyAt: m['ready_at'] == null ? null : DateTime.parse(m['ready_at'] as String).toLocal(),
        pointsSpent: (m['points_spent'] as num?)?.toInt() ?? 0,
        refunded: m['refunded_at'] != null,
      );
}
