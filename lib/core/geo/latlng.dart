/// Plain coordinates, independent of whichever map SDK draws them.
/// Same shape as the old google_maps_flutter types so call sites stay put.
class LatLng {
  const LatLng(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) => other is LatLng && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}

class LatLngBounds {
  const LatLngBounds({required this.southwest, required this.northeast});
  final LatLng southwest;
  final LatLng northeast;

  bool contains(LatLng p) =>
      p.latitude >= southwest.latitude && p.latitude <= northeast.latitude && p.longitude >= southwest.longitude && p.longitude <= northeast.longitude;

  LatLng get center => LatLng((southwest.latitude + northeast.latitude) / 2, (southwest.longitude + northeast.longitude) / 2);

  @override
  bool operator ==(Object other) => other is LatLngBounds && other.southwest == southwest && other.northeast == northeast;

  @override
  int get hashCode => Object.hash(southwest, northeast);

  @override
  String toString() => 'LatLngBounds($southwest → $northeast)';
}
