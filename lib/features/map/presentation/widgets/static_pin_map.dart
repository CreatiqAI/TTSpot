import 'package:flutter/material.dart';

import '../../../../core/geo/latlng.dart';
import '../../../../core/map/app_map.dart';
import '../../../../core/theme/app_theme.dart';
import 'map_glyphs.dart';
import 'map_pins.dart';

/// A small non-interactive map with one red balloon, or a numbered route with
/// a line through its stops. Used on meet, post and spotted pages.
class StaticPinMap extends StatefulWidget {
  const StaticPinMap({super.key, required this.points, this.labels, this.zoom = 14.5, this.route = false});
  final List<LatLng> points;
  /// Optional chip under each pin (e.g. "1. Genting").
  final List<String>? labels;
  /// Zoom when there is a single point; several points fit the view instead.
  final double zoom;
  /// Draw a line through the points, in order.
  final bool route;

  @override
  State<StaticPinMap> createState() => _StaticPinMapState();
}

class _StaticPinMapState extends State<StaticPinMap> {
  final _map = AppMapController();
  GlyphMarkerFactory? _glyphs;
  List<AppMarker> _markers = const [];

  @override
  void dispose() {
    _glyphs?.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    final g = _glyphs ??= GlyphMarkerFactory(devicePixelRatio: MediaQuery.devicePixelRatioOf(context));
    final built = <AppMarker>[];
    for (var i = 0; i < widget.points.length; i++) {
      final label = widget.labels == null || i >= widget.labels!.length ? null : widget.labels![i];
      final MapPin pin = await g.balloon(key: 'static$i', label: label);
      built.add(AppMarker(id: 'p$i', position: widget.points[i], image: pin.bytes, size: pin.size, anchor: pin.anchor, zIndex: i));
    }
    if (mounted) setState(() => _markers = built);
  }

  void _onReady() {
    _build();
    if (widget.points.length > 1) {
      var s = widget.points.first.latitude, n = s, w = widget.points.first.longitude, e = w;
      for (final p in widget.points) {
        if (p.latitude < s) s = p.latitude;
        if (p.latitude > n) n = p.latitude;
        if (p.longitude < w) w = p.longitude;
        if (p.longitude > e) e = p.longitude;
      }
      _map.fitBounds(LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e)), padding: 56, ms: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.points.isEmpty ? const LatLng(3.1390, 101.6869) : widget.points.first;
    return AppMap(
      controller: _map,
      initialTarget: first,
      initialZoom: widget.zoom,
      night: AppColors.dark,
      interactive: false,
      markers: _markers,
      lines: widget.route && widget.points.length > 1 ? [AppLine(id: 'route', points: widget.points, color: AppColors.primary, width: 4)] : const [],
      onReady: _onReady,
    );
  }
}
