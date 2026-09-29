import 'dart:math';

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
  const PlaceDetails({required this.placeId, required this.name, required this.address, required this.lat, required this.lng, this.distanceM});
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;
  /// Metres from where the lookup was made (nearby results only).
  final int? distanceM;

  /// Close enough to say "I am at the place" rather than "near it".
  static const atRadiusM = 80;
  bool get isHere => distanceM != null && distanceM! <= atRadiusM;
}

/// One search, as Google bills it: every keystroke plus the details call that
/// ends it share a token, so the keystrokes are free and only the pick is paid.
class PlaceSession {
  String? _token;
  DateTime _started = DateTime(0);

  /// The open session's token; starts a new one when none is open or it went stale.
  String get token {
    if (_token == null || DateTime.now().difference(_started) > const Duration(minutes: 3)) {
      _token = _uuidV4();
      _started = DateTime.now();
    }
    return _token!;
  }

  /// After the details call: the next keystroke starts a new session.
  void end() => _token = null;

  static String _uuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

class PlacesService {
  PlacesService(this._ref);
  final Ref _ref;

  Future<List<PlaceSuggestion>> autocomplete(String input, {double? lat, double? lng, String? sessionToken}) async {
    final res = await _ref.read(supabaseProvider).functions.invoke('places', body: {
      'action': 'autocomplete',
      'input': input,
      'lat': ?lat,
      'lng': ?lng,
      'sessionToken': ?sessionToken,
    });
    final data = res.data as Map?;
    if (data == null || data['error'] != null) throw Exception(data?['error'] ?? 'Search failed');
    return (data['suggestions'] as List)
        .map((s) => PlaceSuggestion(placeId: s['placeId'] as String, main: s['main'] as String? ?? '', secondary: s['secondary'] as String? ?? ''))
        .toList();
  }

  /// The closest named places around a point (for "use my location").
  /// Most come from Mapbox (`placeId` starts with `mbx:`): they already carry
  /// coordinates, so never pass one to [details].
  Future<List<PlaceDetails>> nearby(double lat, double lng) async {
    final res = await _ref.read(supabaseProvider).functions.invoke('places', body: {'action': 'nearby', 'lat': lat, 'lng': lng});
    final data = res.data as Map?;
    if (data == null || data['error'] != null) throw Exception(data?['error'] ?? 'Nearby failed');
    return (data['places'] as List)
        .where((p) => p['lat'] != null)
        .map((p) => PlaceDetails(
              placeId: p['placeId'] as String? ?? '',
              name: p['name'] as String? ?? '',
              address: p['address'] as String? ?? '',
              lat: (p['lat'] as num).toDouble(),
              lng: (p['lng'] as num).toDouble(),
              distanceM: (p['distanceM'] as num?)?.toInt(),
            ))
        .toList();
  }

  /// Pass the [PlaceSession] token the suggestion came from; it closes that session.
  Future<PlaceDetails> details(String placeId, {String? sessionToken}) async {
    final res = await _ref.read(supabaseProvider).functions.invoke('places', body: {'action': 'details', 'placeId': placeId, 'sessionToken': ?sessionToken});
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

/// The search session behind [placeSuggestionsProvider]. Whoever resolves one
/// of its suggestions passes this token to `details`, then calls `end()`.
final placeSessionProvider = Provider<PlaceSession>((ref) => PlaceSession());

/// Live Google suggestions for a typed query (debounced inside), for lists
/// that can't host a [PlaceSearchField]. Keyed by query + rough position.
final placeSuggestionsProvider = FutureProvider.autoDispose.family<List<PlaceSuggestion>, PlaceQuery>((ref, q) async {
  if (q.text.trim().length < 2) return const [];
  await Future<void>.delayed(const Duration(milliseconds: 350));
  return ref.read(placesServiceProvider).autocomplete(q.text.trim(), lat: q.lat, lng: q.lng, sessionToken: ref.read(placeSessionProvider).token);
});

/// Nearest named places around a point, cached per ~100 m cell. Used by the
/// TT pill ("TT now here · Mamak Sri Melur") and to prefill the TT sheet.
final nearbyPlacesProvider = FutureProvider.family<List<PlaceDetails>, String>((ref, key) {
  final parts = key.split(',');
  return ref.read(placesServiceProvider).nearby(double.parse(parts[0]), double.parse(parts[1]));
});

/// Cache key for nearby lookups: 4 decimals is about 10 m, so the lookup
/// centre is never rounded off the building you are standing in.
String placeKey(double lat, double lng) => '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

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
