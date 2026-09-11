import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Default map centre when location is denied: Kuala Lumpur city centre.
const kualaLumpur = LatLng(3.1390, 101.6869);

/// Klang Valley box used before the map reports its own viewport.
final klangValleyBounds = LatLngBounds(
  southwest: const LatLng(2.70, 101.30),
  northeast: const LatLng(3.50, 101.95),
);

/// Great-circle distance in kilometres.
double distanceKm(LatLng a, LatLng b) {
  const r = 6371.0;
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.sqrt(h));
}

double _rad(double deg) => deg * math.pi / 180;

/// "850 m", "3.2 km", "42 km"
String formatDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.round()} km';
}
