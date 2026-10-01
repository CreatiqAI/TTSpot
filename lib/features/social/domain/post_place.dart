import '../../../core/geo/latlng.dart';
import '../../../core/places/places_service.dart';
import '../../../core/utils/geo.dart';
import 'club.dart';

/// Where a new post is: one of our TT Spots (linked, so the post shows on the
/// spot's page) or any named place or address from the search.
class PostPlace {
  const PostPlace({required this.name, this.address = '', this.lat, this.lng, this.spotId, this.distanceM, this.approximate = false, this.key});

  factory PostPlace.spot(Place p, {int? distanceM}) =>
      PostPlace(name: p.name, lat: p.lat, lng: p.lng, spotId: p.id, distanceM: distanceM, key: 'spot:${p.id}');

  factory PostPlace.details(PlaceDetails d) =>
      PostPlace(name: d.name.trim(), address: d.address.trim(), lat: d.lat, lng: d.lng, distanceM: d.distanceM, key: d.placeId.isEmpty ? null : d.placeId);

  final String name;
  final String address;
  final double? lat;
  final double? lng;

  /// Set for a TT Spot: saved as the post's place_id.
  final String? spotId;

  /// Metres from me (lists around me only).
  final int? distanceM;

  /// "Near <area>": only the area is shared, never the spot I stand on.
  final bool approximate;

  /// The search's place id, to tell chips apart.
  final String? key;

  bool get isSpot => spotId != null;
  LatLng? get latLng => lat == null || lng == null ? null : LatLng(lat!, lng!);

  /// Same place, for the selected chip.
  String get id => key ?? '$name@${lat?.toStringAsFixed(4)},${lng?.toStringAsFixed(4)}';

  @override
  bool operator ==(Object other) => other is PostPlace && other.id == id;
  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PostPlace($name${isSpot ? ', spot' : ''}${approximate ? ', approx' : ''})';
}

/// Within this many metres a place counts as where I am.
const kPlaceHereM = PlaceDetails.atRadiusM;

/// Spots this close show as chips around me.
const kSpotChipKm = 1.0;

int _metres(LatLng a, double lat, double lng) => (distanceKm(a, LatLng(lat, lng)) * 1000).round();

/// ~1 km grid, so "Near <area>" never gives away a home.
double _coarse(double v) => (v * 100).roundToDouble() / 100;

/// "Use my location": what to call where I am at ([lat], [lng]), from what
/// is around ([nearby] from the places lookup, [spots] from ours).
///   1. a TT Spot within 80 m (the closest),
///   2. else any named place within 80 m (the closest),
///   3. else `Near <area>` from the nearest address that names one,
///   4. else `Near <the nearest place>` when it is within 500 m.
/// The last two keep only a ~1 km position. Null when nothing fits.
PostPlace? placeAt({required double lat, required double lng, required List<PlaceDetails> nearby, List<Place> spots = const []}) {
  final here = LatLng(lat, lng);
  final spotsByDistance = [for (final s in spots) (s, _metres(here, s.lat, s.lng))]..sort((a, b) => a.$2.compareTo(b.$2));
  if (spotsByDistance.isNotEmpty && spotsByDistance.first.$2 <= kPlaceHereM) {
    return PostPlace.spot(spotsByDistance.first.$1, distanceM: spotsByDistance.first.$2);
  }
  final named = [for (final p in nearby) if (p.name.trim().isNotEmpty) (p, p.distanceM ?? _metres(here, p.lat, p.lng))]..sort((a, b) => a.$2.compareTo(b.$2));
  if (named.isNotEmpty && named.first.$2 <= kPlaceHereM) {
    final p = named.first.$1;
    return PostPlace.details(PlaceDetails(placeId: p.placeId, name: p.name, address: p.address, lat: p.lat, lng: p.lng, distanceM: named.first.$2));
  }
  for (final (p, _) in named) {
    final area = areaFromAddress(p.address);
    if (area != null) return PostPlace(name: 'Near $area', lat: _coarse(lat), lng: _coarse(lng), approximate: true);
  }
  if (named.isNotEmpty && named.first.$2 <= 500) {
    return PostPlace(name: 'Near ${named.first.$1.name.trim()}', lat: _coarse(lat), lng: _coarse(lng), approximate: true);
  }
  return null;
}

/// The chips to offer around me: TT Spots within [spotRadiusKm] first, then
/// the named places from the lookup that are not one of those spots, each
/// group nearest first, at most [max].
List<PostPlace> placesAround({required double lat, required double lng, required List<PlaceDetails> nearby, List<Place> spots = const [], double spotRadiusKm = kSpotChipKm, int max = 10}) {
  final here = LatLng(lat, lng);
  final near = [for (final s in spots) (s, _metres(here, s.lat, s.lng))].where((e) => e.$2 <= spotRadiusKm * 1000).toList()..sort((a, b) => a.$2.compareTo(b.$2));
  final out = <PostPlace>[for (final (s, m) in near) PostPlace.spot(s, distanceM: m)];
  final others = [for (final p in nearby) if (p.name.trim().isNotEmpty) (p, p.distanceM ?? _metres(here, p.lat, p.lng))]..sort((a, b) => a.$2.compareTo(b.$2));
  for (final (p, m) in others) {
    if (near.any((s) => _samePlace(s.$1.name, s.$1.lat, s.$1.lng, p.name, p.lat, p.lng))) continue;
    final chip = PostPlace.details(PlaceDetails(placeId: p.placeId, name: p.name, address: p.address, lat: p.lat, lng: p.lng, distanceM: m));
    if (out.contains(chip)) continue;
    out.add(chip);
  }
  return out.take(max).toList();
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// One place listed twice (our spot and the search's entry): one name starts
/// the other and they are within 100 m.
bool _samePlace(String aName, double aLat, double aLng, String bName, double bLat, double bLng) {
  final x = _norm(aName), y = _norm(bName);
  if (x.length < 3 || y.length < 3) return false;
  return (x.startsWith(y) || y.startsWith(x) || x.contains(y) || y.contains(x)) && _metres(LatLng(aLat, aLng), bLat, bLng) < 100;
}

final _streetOrUnit = RegExp(
  r'^(no\.?|lot|unit|blok|block|level|lvl|tingkat|aras|lorong|lrg\.?|jalan|jln\.?|persiaran|lebuh|lebuhraya|lengkok|lingkaran|off|road|rd\.?|street|st\.?|avenue|ave\.?|lane|highway|expressway)\b',
  caseSensitive: false,
);

const _states = {
  'selangor', 'johor', 'penang', 'pulau pinang', 'perak', 'kedah', 'kelantan', 'terengganu', 'pahang', 'negeri sembilan',
  'melaka', 'malacca', 'perlis', 'sabah', 'sarawak', 'labuan', 'wilayah persekutuan', 'wilayah persekutuan kuala lumpur',
  'wilayah persekutuan putrajaya', 'wilayah persekutuan labuan', 'federal territory of kuala lumpur', 'kuala lumpur federal territory',
  'federal territory of putrajaya',
};

/// The neighbourhood an address is in, for "Near …":
/// "12, Jalan Datuk Sulaiman, Taman Tun Dr Ismail, 60000 Kuala Lumpur,
/// Wilayah Persekutuan Kuala Lumpur, Malaysia" → "Taman Tun Dr Ismail".
/// Skips house numbers, streets, postcodes, the country and states (a state
/// only when nothing else is left). Null when the address names no area.
String? areaFromAddress(String address) {
  String? state;
  for (final raw in address.split(',')) {
    var part = raw.trim().replaceFirst(RegExp(r'^\d{5}\s*'), '').trim();
    part = part.replaceFirst(RegExp(r'\s+\d{5}$'), '').trim();
    if (part.isEmpty || part.toLowerCase() == 'malaysia') continue;
    if (RegExp(r'^[\d#]').hasMatch(part) || _streetOrUnit.hasMatch(part)) continue;
    if (_states.contains(part.toLowerCase())) {
      state ??= part;
      continue;
    }
    return part;
  }
  return state;
}
