import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../geo/latlng.dart';

/// The map, on Mapbox. Everything the app needs from a map goes through here
/// so screens never touch the SDK: bitmap markers with a fractional anchor,
/// circles in metres, lines, camera moves in Google-style zoom units
/// (Mapbox zoom is one level lower for the same view; we convert), and a
/// day / night switch on the Standard style.

/// A rendered bitmap placed on the map. [anchor] is the fraction of the image
/// that sits on the coordinate (0.5, 1 = bottom centre). [size] is logical px.
class AppMarker {
  const AppMarker({
    required this.id,
    required this.position,
    required this.image,
    required this.size,
    this.anchor = const Offset(0.5, 1),
    this.zIndex = 0,
    this.onTap,
  });
  final String id;
  final LatLng position;
  final Uint8List image;
  final Size size;
  final Offset anchor;
  final int zIndex;
  final VoidCallback? onTap;

  AppMarker copyWith({LatLng? position}) =>
      AppMarker(id: id, position: position ?? this.position, image: image, size: size, anchor: anchor, zIndex: zIndex, onTap: onTap);
}

/// A filled circle with a real-world radius.
class AppCircle {
  const AppCircle({required this.id, required this.center, required this.radiusM, required this.fill, this.stroke, this.strokeWidth = 1, this.zIndex = 0});
  final String id;
  final LatLng center;
  final double radiusM;
  final Color fill;
  final Color? stroke;
  final double strokeWidth;
  final int zIndex;
}

class AppLine {
  const AppLine({required this.id, required this.points, required this.color, this.width = 4});
  final String id;
  final List<LatLng> points;
  final Color color;
  final double width;
}

mb.Point _pt(LatLng p) => mb.Point(coordinates: mb.Position(p.longitude, p.latitude));
LatLng _ll(mb.Point p) => LatLng(p.coordinates.lat.toDouble(), p.coordinates.lng.toDouble());

/// Mapbox counts zoom one level lower than Google for the same view.
double _mbZoom(double googleZoom) => googleZoom - 1;

/// Drives one [AppMap]. Create it in the screen's state; it becomes live once
/// the map is created (see [isReady]) and calls before that are ignored.
class AppMapController {
  mb.MapboxMap? _map;
  mb.PointAnnotationManager? _points;
  mb.PolygonAnnotationManager? _polys;
  mb.PolylineAnnotationManager? _lines;
  final _live = <String, (mb.PointAnnotation, AppMarker)>{};
  final _byAnnotation = <String, String>{};
  Future<void> _queue = Future.value();
  bool _disposed = false;

  bool get isReady => _map != null;

  Future<void> _attach(mb.MapboxMap map) async {
    _map = map;
    _polys = await map.annotations.createPolygonAnnotationManager();
    _lines = await map.annotations.createPolylineAnnotationManager();
    _points = await map.annotations.createPointAnnotationManager();
    _points!.tapEvents(onTap: (a) {
      final id = _byAnnotation[a.id];
      if (id != null) _live[id]?.$2.onTap?.call();
    });
  }

  void dispose() {
    _disposed = true;
    _map = null;
    _points = null;
    _polys = null;
    _lines = null;
    _live.clear();
    _byAnnotation.clear();
  }

  /// Runs map work one call at a time so a rebuild never races an earlier one.
  Future<void> _serial(Future<void> Function() job) {
    final next = _queue.then((_) async {
      if (_disposed) return;
      try {
        await job();
      } catch (_) {
        // the platform view may be gone (screen popped mid-flight); nothing to do
      }
    });
    _queue = next;
    return next;
  }

  // -------------------------------------------------------------- camera ---

  Future<void> animateTo(LatLng target, {double? zoom, int ms = 600}) async {
    final map = _map;
    if (map == null) return;
    await map.flyTo(mb.CameraOptions(center: _pt(target), zoom: zoom == null ? null : _mbZoom(zoom)), mb.MapAnimationOptions(duration: ms));
  }

  Future<void> moveTo(LatLng target, {double? zoom}) async {
    await _map?.setCamera(mb.CameraOptions(center: _pt(target), zoom: zoom == null ? null : _mbZoom(zoom)));
  }

  Future<void> fitBounds(LatLngBounds b, {double padding = 48, int ms = 600}) async {
    final map = _map;
    if (map == null) return;
    final cam = await map.cameraForCoordinateBounds(
      mb.CoordinateBounds(southwest: _pt(b.southwest), northeast: _pt(b.northeast), infiniteBounds: false),
      mb.MbxEdgeInsets(top: padding, left: padding, bottom: padding, right: padding),
      null,
      null,
      null,
      null,
    );
    await map.flyTo(cam, mb.MapAnimationOptions(duration: ms));
  }

  Future<LatLngBounds?> visibleRegion() async {
    final map = _map;
    if (map == null) return null;
    final s = await map.getCameraState();
    final b = await map.coordinateBoundsForCamera(mb.CameraOptions(center: s.center, zoom: s.zoom, bearing: s.bearing, pitch: s.pitch, padding: s.padding));
    return LatLngBounds(southwest: _ll(b.southwest), northeast: _ll(b.northeast));
  }

  /// Google-style zoom (Mapbox + 1), so the tier thresholds in the app stay as they were.
  Future<double> zoom() async {
    final s = await _map?.getCameraState();
    return (s?.zoom ?? 11) + 1;
  }

  Future<void> setPadding(EdgeInsets p) async {
    await _map?.setCamera(mb.CameraOptions(padding: mb.MbxEdgeInsets(top: p.top, left: p.left, bottom: p.bottom, right: p.right)));
    await _ornaments(p);
  }

  Future<void> _ornaments(EdgeInsets p) async {
    final map = _map;
    if (map == null) return;
    try {
      await map.logo.updateSettings(mb.LogoSettings(marginLeft: 8, marginBottom: p.bottom + 6));
      await map.attribution.updateSettings(mb.AttributionSettings(marginLeft: 96, marginBottom: p.bottom + 4));
    } catch (_) {}
  }

  /// Standard style light preset: day or night. Also re-applies the label
  /// settings, since a preset change can happen before the style has loaded.
  Future<void> setNight(bool night) => applyStyle(night: night);

  /// Everything we set on the Standard style once it has loaded: the light
  /// preset, and fewer labels. Mapbox's own shop / restaurant / ATM labels
  /// fight with our pins at street zoom, so they go; roads and place names
  /// stay so the map still reads as a map.
  Future<void> applyStyle({required bool night}) async {
    final map = _map;
    if (map == null) return;
    try {
      await map.style.setStyleImportConfigProperties('basemap', {
        'lightPreset': night ? 'night' : 'day',
        'showPointOfInterestLabels': false,
        'showTransitLabels': false,
        'showRoadLabels': true,
        'showPlaceLabels': true,
      });
    } catch (_) {
      // Older style versions reject unknown keys as a batch; fall back to the one we can't do without.
      try {
        await map.style.setStyleImportConfigProperty('basemap', 'lightPreset', night ? 'night' : 'day');
      } catch (_) {}
    }
  }

  /// Where the camera is pointed right now (null before the map is live).
  Future<LatLng?> center() async {
    final s = await _map?.getCameraState();
    return s == null ? null : _ll(s.center);
  }

  // ------------------------------------------------------------- markers ---

  Future<void> setMarkers(List<AppMarker> markers) => _serial(() => _applyMarkers(markers));

  Future<void> _applyMarkers(List<AppMarker> markers) async {
    final pm = _points;
    if (pm == null) return;
    final wanted = {for (final m in markers) m.id: m};
    final toDelete = <mb.PointAnnotation>[];
    final toUpdate = <mb.PointAnnotation>[];
    final keep = <String>{};
    for (final e in _live.entries.toList()) {
      final w = wanted[e.key];
      final (a, old) = e.value;
      if (w != null && identical(w.image, old.image) && w.anchor == old.anchor && w.zIndex == old.zIndex) {
        if (w.position != old.position) {
          a.geometry = _pt(w.position);
          toUpdate.add(a);
        }
        _live[e.key] = (a, w);
        keep.add(e.key);
      } else {
        toDelete.add(a);
        _byAnnotation.remove(a.id);
        _live.remove(e.key);
      }
    }
    final toCreate = [for (final m in markers) if (!keep.contains(m.id)) m];
    if (toDelete.isNotEmpty) await pm.deleteMulti(toDelete);
    for (final a in toUpdate) {
      await pm.update(a);
    }
    if (toCreate.isNotEmpty) {
      final created = await pm.createMulti([for (final m in toCreate) _options(m)]);
      for (var i = 0; i < toCreate.length && i < created.length; i++) {
        final a = created[i];
        if (a == null) continue;
        _live[toCreate[i].id] = (a, toCreate[i]);
        _byAnnotation[a.id] = toCreate[i].id;
      }
    }
  }

  mb.PointAnnotationOptions _options(AppMarker m) => mb.PointAnnotationOptions(
        geometry: _pt(m.position),
        image: m.image,
        iconAnchor: mb.IconAnchor.CENTER,
        // shift the image so its anchor point, not its centre, sits on the coordinate
        iconOffset: [(0.5 - m.anchor.dx) * m.size.width, (0.5 - m.anchor.dy) * m.size.height],
        symbolSortKey: m.zIndex.toDouble(),
      );

  // ---------------------------------------------------- circles + lines ---

  Future<void> setCircles(List<AppCircle> circles) => _serial(() async {
        final pm = _polys;
        if (pm == null) return;
        await pm.deleteAll();
        if (circles.isEmpty) return;
        final sorted = [...circles]..sort((a, b) => a.zIndex.compareTo(b.zIndex));
        await pm.createMulti([
          for (final c in sorted)
            mb.PolygonAnnotationOptions(
              geometry: mb.Polygon(coordinates: [_ring(c.center, c.radiusM)]),
              fillColor: c.fill.withValues(alpha: 1).toARGB32(),
              fillOpacity: c.fill.a,
              fillOutlineColor: (c.stroke ?? c.fill).toARGB32(),
              fillSortKey: c.zIndex.toDouble(),
            ),
        ]);
      });

  Future<void> setLines(List<AppLine> lines) => _serial(() async {
        final lm = _lines;
        if (lm == null) return;
        await lm.deleteAll();
        if (lines.isEmpty) return;
        await lm.createMulti([
          for (final l in lines)
            mb.PolylineAnnotationOptions(
              geometry: mb.LineString(coordinates: [for (final p in l.points) mb.Position(p.longitude, p.latitude)]),
              lineColor: l.color.toARGB32(),
              lineWidth: l.width,
              lineJoin: mb.LineJoin.ROUND,
            ),
        ]);
      });

  static List<mb.Position> _ring(LatLng c, double radiusM, {int n = 48}) {
    final latR = radiusM / 111320.0;
    final lngR = radiusM / (111320.0 * math.cos(c.latitude * math.pi / 180));
    return [
      for (var i = 0; i <= n; i++)
        mb.Position(c.longitude + lngR * math.sin(2 * math.pi * i / n), c.latitude + latR * math.cos(2 * math.pi * i / n)),
    ];
  }
}

/// The map widget. Declarative [markers] / [circles] / [lines] are applied
/// whenever the lists change; camera moves go through the [controller].
class AppMap extends StatefulWidget {
  const AppMap({
    super.key,
    required this.controller,
    required this.initialTarget,
    this.initialZoom = 12,
    this.night = true,
    this.padding = EdgeInsets.zero,
    this.markers = const [],
    this.circles = const [],
    this.lines = const [],
    this.interactive = true,
    this.gestureRecognizers,
    this.onReady,
    this.onTap,
    this.onCameraIdle,
    this.onCameraMove,
    this.onCameraMoveStarted,
  });

  final AppMapController controller;
  final LatLng initialTarget;
  /// Google-style zoom.
  final double initialZoom;
  final bool night;
  final EdgeInsets padding;
  final List<AppMarker> markers;
  final List<AppCircle> circles;
  final List<AppLine> lines;
  /// False = a static preview: no pan, no zoom.
  final bool interactive;
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;
  final VoidCallback? onReady;
  final ValueChanged<LatLng>? onTap;
  final VoidCallback? onCameraIdle;
  final ValueChanged<LatLng>? onCameraMove;
  final VoidCallback? onCameraMoveStarted;

  @override
  State<AppMap> createState() => _AppMapState();
}

class _AppMapState extends State<AppMap> {
  Future<void> _onCreated(mb.MapboxMap map) async {
    final c = widget.controller;
    await c._attach(map);
    if (!mounted) return;
    try {
      await map.compass.updateSettings(mb.CompassSettings(enabled: false));
      await map.scaleBar.updateSettings(mb.ScaleBarSettings(enabled: false));
      await map.gestures.updateSettings(mb.GesturesSettings(
        rotateEnabled: false,
        pitchEnabled: false,
        scrollEnabled: widget.interactive,
        pinchToZoomEnabled: widget.interactive,
        doubleTapToZoomInEnabled: widget.interactive,
        doubleTouchToZoomOutEnabled: widget.interactive,
        quickZoomEnabled: widget.interactive,
      ));
    } catch (_) {}
    await c._ornaments(widget.padding);
    await c.setMarkers(widget.markers);
    await c.setCircles(widget.circles);
    await c.setLines(widget.lines);
    widget.onReady?.call();
  }

  @override
  void didUpdateWidget(AppMap old) {
    super.didUpdateWidget(old);
    final c = widget.controller;
    if (!identical(old.markers, widget.markers)) c.setMarkers(widget.markers);
    if (!identical(old.circles, widget.circles)) c.setCircles(widget.circles);
    if (!identical(old.lines, widget.lines)) c.setLines(widget.lines);
    if (old.night != widget.night) c.setNight(widget.night);
    if (old.padding != widget.padding) c.setPadding(widget.padding);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.padding;
    return mb.MapWidget(
      key: const ValueKey('mapbox'),
      styleUri: mb.MapboxStyles.STANDARD,
      // ignore: deprecated_member_use
      cameraOptions: mb.CameraOptions(
        center: _pt(widget.initialTarget),
        zoom: _mbZoom(widget.initialZoom),
        padding: mb.MbxEdgeInsets(top: p.top, left: p.left, bottom: p.bottom, right: p.right),
      ),
      gestureRecognizers: widget.gestureRecognizers,
      onMapCreated: _onCreated,
      onStyleLoadedListener: (_) => widget.controller.setNight(widget.night),
      onMapLoadErrorListener: (e) => debugPrint('AppMap load error: ${e.type} ${e.message}'),
      onMapIdleListener: (_) => widget.onCameraIdle?.call(),
      onCameraChangeListener: (d) => widget.onCameraMove?.call(_ll(d.cameraState.center)),
      onScrollListener: (_) => widget.onCameraMoveStarted?.call(),
      // ignore: deprecated_member_use
      onTapListener: (ctx) => widget.onTap?.call(_ll(ctx.point)),
    );
  }
}
