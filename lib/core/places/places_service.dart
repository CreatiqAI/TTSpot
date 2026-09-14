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
