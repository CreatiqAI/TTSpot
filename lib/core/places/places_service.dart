import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_client.dart';

/// Address search for the meet form. Calls the `places` Edge Function, which
/// holds the Google key and talks to the Places API (New).
class PlaceSuggestion {
  const PlaceSuggestion({required this.placeId, required this.main, required this.secondary});
  final String placeId;
  final String main;
  final String secondary;
}

class PlaceDetails {
  const PlaceDetails({required this.placeId, required this.name, required this.address, required this.lat, required this.lng});
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;
}

class PlacesService {
  PlacesService(this._ref);
  final Ref _ref;

  Future<List<PlaceSuggestion>> autocomplete(String input, {double? lat, double? lng}) async {
    final res = await _ref.read(supabaseProvider).functions.invoke('places', body: {
      'action': 'autocomplete',
      'input': input,
      'lat': ?lat,
      'lng': ?lng,
    });
    final data = res.data as Map?;
    if (data == null || data['error'] != null) throw Exception(data?['error'] ?? 'Search failed');
    return (data['suggestions'] as List)
        .map((s) => PlaceSuggestion(placeId: s['placeId'] as String, main: s['main'] as String? ?? '', secondary: s['secondary'] as String? ?? ''))
        .toList();
  }

  /// The closest named places around a point (for "use my location").
  Future<List<PlaceDetails>> nearby(double lat, double lng) async {
    final res = await _ref.read(supabaseProvider).functions.invoke('places', body: {'action': 'nearby', 'lat': lat, 'lng': lng});
    final data = res.data as Map?;
    if (data == null || data['error'] != null) throw Exception(data?['error'] ?? 'Nearby failed');
    return (data['places'] as List)
        .where((p) => p['lat'] != null)
        .map((p) => PlaceDetails(placeId: p['placeId'] as String? ?? '', name: p['name'] as String? ?? '', address: p['address'] as String? ?? '', lat: (p['lat'] as num).toDouble(), lng: (p['lng'] as num).toDouble()))
        .toList();
  }

  Future<PlaceDetails> details(String placeId) async {
    final res = await _ref.read(supabaseProvider).functions.invoke('places', body: {'action': 'details', 'placeId': placeId});
    final d = res.data as Map?;
    if (d == null || d['error'] != null || d['lat'] == null) throw Exception(d?['error'] ?? 'Place lookup failed');
    return PlaceDetails(
      placeId: d['placeId'] as String? ?? placeId,
      name: d['name'] as String? ?? '',
      address: d['address'] as String? ?? '',
      lat: (d['lat'] as num).toDouble(),
      lng: (d['lng'] as num).toDouble(),
    );
  }
}

final placesServiceProvider = Provider<PlacesService>((ref) => PlacesService(ref));

/// Live Google suggestions for a typed query (debounced inside), for lists
/// that can't host a [PlaceSearchField]. Keyed by query + rough position.
final placeSuggestionsProvider = FutureProvider.autoDispose.family<List<PlaceSuggestion>, PlaceQuery>((ref, q) async {
  if (q.text.trim().length < 2) return const [];
  await Future<void>.delayed(const Duration(milliseconds: 350));
  return ref.read(placesServiceProvider).autocomplete(q.text.trim(), lat: q.lat, lng: q.lng);
});

/// Nearest named places around a point, cached per ~100 m cell. Used by the
/// TT pill ("TT now here · Mamak Sri Melur") and to prefill the TT sheet.
final nearbyPlacesProvider = FutureProvider.family<List<PlaceDetails>, String>((ref, key) {
  final parts = key.split(',');
  return ref.read(placesServiceProvider).nearby(double.parse(parts[0]), double.parse(parts[1]));
});

String placeKey(double lat, double lng) => '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';

/// "Jalan PJS 11/7, Bandar Sunway" from a full Google address.
String shortAddress(String address) {
  final parts = address.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty && !RegExp(r'^\d{5}').hasMatch(p) && p != 'Malaysia').toList();
  return parts.take(2).join(', ');
}

class PlaceQuery {
  const PlaceQuery(this.text, {this.lat, this.lng});
  final String text;
  final double? lat;
  final double? lng;

  @override
  bool operator ==(Object other) =>
      other is PlaceQuery && other.text == text && other.lat?.toStringAsFixed(2) == lat?.toStringAsFixed(2) && other.lng?.toStringAsFixed(2) == lng?.toStringAsFixed(2);
  @override
  int get hashCode => Object.hash(text, lat?.toStringAsFixed(2), lng?.toStringAsFixed(2));
}
