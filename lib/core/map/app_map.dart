import 'dart:async';
import 'dart:convert';
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
///
/// [image] must be a PNG drawn at the screen's device pixel ratio (size x
/// devicePixelRatio pixels, as MapPinFactory / GlyphMarkerFactory do). Both
/// plugins register the bitmap at the screen density, so it shows at [size]
/// logical px on either platform: Android adds it at
/// `displayMetrics.density` (what Flutter reports as devicePixelRatio there)
/// and iOS decodes it with `UIImage(data:scale: UIScreen.main.scale)` (what
/// Flutter reports there). The offset maths in `_options` relies on that.
class AppMarker {
  const AppMarker({
    required this.id,
    required this.position,
    required this.image,
    required this.size,
    this.anchor = const Offset(0.5, 1),
    this.zIndex = 0,
    this.onTap,
    this.onLongPress,
  });
  final String id;
  final LatLng position;
  final Uint8List image;
  final Size size;
  final Offset anchor;
  final int zIndex;
  final VoidCallback? onTap;
  /// A long press on the pin (e.g. a friend's colour picker).
  final VoidCallback? onLongPress;

  AppMarker copyWith({LatLng? position}) =>
      AppMarker(id: id, position: position ?? this.position, image: image, size: size, anchor: anchor, zIndex: zIndex, onTap: onTap, onLongPress: onLongPress);
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

/// A ring that grows out of each of [points] and fades, once every [period]:
/// from [fromPx] to [toPx] screen px (logical) over [duration], fill and
/// stroke fading from [fill] / [stroke] opacity to nothing. Drawn and eased
/// by the map's renderer (see [AppMapController.setPulse]), so it stays
/// smooth and costs no bitmaps and no annotation updates.
class AppPulse {
  const AppPulse({
    required this.points,
    required this.color,
    required this.fromPx,
    required this.toPx,
    this.period = const Duration(seconds: 2),
    this.duration = const Duration(milliseconds: 1300),
    this.fill = 0.14,
    this.stroke = 0.7,
    this.strokeWidth = 2,
  });
  final List<LatLng> points;
  final Color color;
  final double fromPx;
  final double toPx;
  final Duration period;
  final Duration duration;
  final double fill;
  final double stroke;
  final double strokeWidth;
}

class _PulseState {
  AppPulse? spec;
  Timer? timer;
  /// The pause between a ring's snap and its growth.
  Timer? start;
  /// GeoJSON wanted, and the last sent to the map.
  String? data;
  String? sent;
  bool added = false;
  bool adding = false;
  bool underPins = false;
}

/// What the camera shows: the visible bounds, the Google-style zoom and the
/// centre (which respects the camera padding; the bounds' centre does not).
typedef AppCameraView = ({LatLngBounds bounds, double zoom, LatLng centre});

/// Reported on every camera frame, worked out in Dart from the camera event
/// and the map's size, so reading the view never waits on the platform.
typedef AppCameraCallback = void Function(AppCameraView view);

/// The view of a camera with no rotation and no pitch (the only kind the
/// app's maps allow) on a map of [size] logical px with camera padding [pad]
/// (logical px). Web Mercator on Mapbox's 512 px tiles: the camera centre
/// sits in the middle of the area the padding leaves, and the bounds are the
/// whole map's corners. The padding is the one we set, not the event's: the
/// Android plugin reports that in physical px, iOS in points.
AppCameraView _viewOf(mb.CameraState s, Size size, EdgeInsets pad) {
  final centre = _ll(s.center);
  final zoom = s.zoom.toDouble();
  final world = 512 * math.pow(2, zoom).toDouble();
  final lat = centre.latitude.clamp(-85.0511, 85.0511) * math.pi / 180;
  final cx = (centre.longitude + 180) / 360 * world;
  final cy = (0.5 - math.log(math.tan(math.pi / 4 + lat / 2)) / (2 * math.pi)) * world;
  // Where the centre is drawn on the map: the middle of the padded area.
  final px = pad.left + (size.width - pad.left - pad.right) / 2;
  final py = pad.top + (size.height - pad.top - pad.bottom) / 2;
  LatLng at(double sx, double sy) {
    final x = cx + sx - px, y = cy + sy - py;
    final lng = x / world * 360 - 180;
    final n = math.pi * (1 - 2 * y / world);
    final la = math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
    return LatLng(la, lng);
  }

  final nw = at(0, 0), se = at(size.width, size.height);
  return (
    bounds: LatLngBounds(southwest: LatLng(se.latitude, nw.longitude), northeast: LatLng(nw.latitude, se.longitude)),
    zoom: zoom + 1,
    centre: centre,
  );
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
  /// Live annotations by our marker id. The annotation object is what the
  /// plugin handed back from createMulti; its `id` is the handle every later
  /// update / delete / tap uses on both platforms.
  final _live = <String, (mb.PointAnnotation, AppMarker)>{};
  final _byAnnotation = <String, String>{};
  Future<void> _queue = Future.value();
  bool _disposed = false;
  /// Latest requested markers / circles / lines. A burst of updates (a zoom
  /// redraw, then the data it fetched) collapses to one job each: the queued
  /// job applies whatever is newest when it runs.
  List<AppMarker>? _wantMarkers;
  List<AppCircle>? _wantCircles;
  List<AppLine>? _wantLines;

  bool get isReady => _map != null;

  /// The camera padding we last asked for (logical px), for the camera view
  /// worked out in Dart (see [AppCameraCallback]).
  EdgeInsets _padding = EdgeInsets.zero;

  /// The pins' layer (and source) id, named so pulse rings can sit under it.
  static const _pointsLayer = 'tt-points';

  Future<void> _attach(mb.MapboxMap map) async {
    _map = map;
    _polys = await map.annotations.createPolygonAnnotationManager();
    _lines = await map.annotations.createPolylineAnnotationManager();
    final points = _points = await map.annotations.createPointAnnotationManager(id: _pointsLayer);
    // Pins always draw, like the Google markers this map replaced. Left unset,
    // the symbol layer's collision rules decide, and those differ in practice
    // between the two SDKs' annotation managers: a pin sitting on top of
    // another (me at a spot, a friend at a meet) could simply not be placed.
    // With overlap allowed, symbolSortKey also means the same thing on both:
    // a higher zIndex draws on top. (With collisions on, the spec flips it and
    // the LOWER sort key wins placement, so "me" at zIndex 10 would lose.)
    try {
      await points.setIconAllowOverlap(true);
    } catch (e) {
      if (kDebugMode) debugPrint('AppMap: iconAllowOverlap failed: $e');
    }
    // Taps: both plugins report the same annotation id they returned from
    // createMulti, and both consume the tap once we listen (the map's own
    // onTap does not fire for a pin), so one lookup works on either platform.
    points.tapEvents(onTap: (a) {
      final id = _byAnnotation[a.id];
      if (id != null) _live[id]?.$2.onTap?.call();
    });
    points.longPressEvents(onLongPress: (a) {
      final id = _byAnnotation[a.id];
      if (id != null) _live[id]?.$2.onLongPress?.call();
    });
  }

  /// Whether an update must carry the bitmap again.
  ///
  /// Android (PointAnnotationController.kt `updateAnnotation`) patches the
  /// live annotation and only touches the icon when `image` is non-null, so a
  /// geometry-only update can and should leave it null: every bitmap it is
  /// sent is registered as a new style image (named by the Bitmap's hash) and
  /// never removed, so re-sending it on each GPS fix would pile up images.
  ///
  /// iOS (PointAnnotationController.swift `update` -> `toPointAnnotation()`)
  /// builds a brand-new annotation from the Flutter object and sets an image
  /// only when `image` is non-null. An update without the bytes therefore
  /// replaces the pin with one that has no icon: that is how my own marker
  /// vanished on iPhone after the first location fix and after "Back to me".
  /// It reuses the annotation's `iconImage` name, so re-sending the bytes
  /// just refreshes the same style image rather than adding one.
  static bool get _updateNeedsImage => defaultTargetPlatform != TargetPlatform.android;

  void dispose() {
    _disposed = true;
    for (final p in _pulses.values) {
      p.timer?.cancel();
      p.start?.cancel();
    }
    _pulses.clear();
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
      } catch (e, st) {
        // the platform view may be gone (screen popped mid-flight); log in debug so a bad
        // annotation option never fails silently
        if (kDebugMode) debugPrint('AppMap: annotation job failed: $e\n$st');
      }
    });
    _queue = next;
    return next;
  }

  // -------------------------------------------------------------- camera ---

  /// Glide to [target]. With [padding], the camera's padding changes in the
  /// same flight: [target] lands in the middle of what the padding leaves
  /// (e.g. the map above a card), with no jump before or after.
  Future<void> animateTo(LatLng target, {double? zoom, EdgeInsets? padding, int ms = 600}) async {
    final map = _map;
    if (map == null) return;
    if (padding != null) _padding = padding;
    await map.flyTo(mb.CameraOptions(center: _pt(target), zoom: zoom == null ? null : _mbZoom(zoom), padding: padding == null ? null : _insets(padding)), mb.MapAnimationOptions(duration: ms));
  }

  /// Ease the camera's padding to [p] without moving the target, e.g. back
  /// to the toolbar's when a card closes.
  Future<void> animatePadding(EdgeInsets p, {int ms = 300}) async {
    _padding = p;
    await _map?.easeTo(mb.CameraOptions(padding: _insets(p)), mb.MapAnimationOptions(duration: ms));
  }

  static mb.MbxEdgeInsets _insets(EdgeInsets p) => mb.MbxEdgeInsets(top: p.top, left: p.left, bottom: p.bottom, right: p.right);

  Future<void> moveTo(LatLng target, {double? zoom}) async {
    await _map?.setCamera(mb.CameraOptions(center: _pt(target), zoom: zoom == null ? null : _mbZoom(zoom)));
  }

  /// Fit [b] on screen. With [insets], the map's own camera padding (the
  /// toolbar at the bottom of the home map) is kept as it is and [insets] is
  /// a margin around the points inside it (room for the mode switch at the
  /// top and the round buttons at the side); the zoom never goes past
  /// [maxZoom] (Google-style), so two points close together do not land at
  /// street level. Without [insets], [padding] applies evenly on every side
  /// (the static preview maps, which have no camera padding).
  Future<void> fitBounds(LatLngBounds b, {double padding = 48, EdgeInsets? insets, double maxZoom = 16, int ms = 600}) async {
    final map = _map;
    if (map == null) return;
    if (insets != null) {
      final state = await map.getCameraState();
      final centre = _pt(b.center);
      final corners = [
        _pt(b.southwest),
        _pt(b.northeast),
        _pt(LatLng(b.southwest.latitude, b.northeast.longitude)),
        _pt(LatLng(b.northeast.latitude, b.southwest.longitude)),
      ];
      mb.Point? at;
      double? zoom;
      try {
        // Keeps the camera's padding (principal point above the toolbar) and
        // adjusts the zoom so every corner fits inside the margin.
        final cam = await map.cameraForCoordinatesPadding(
          corners,
          mb.CameraOptions(center: centre, padding: state.padding, bearing: 0, pitch: 0),
          mb.MbxEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right),
          _mbZoom(maxZoom),
          null,
        );
        at = cam.center;
        zoom = cam.zoom?.toDouble();
      } catch (e) {
        if (kDebugMode) debugPrint('AppMap: cameraForCoordinatesPadding failed: $e');
      }
      if (zoom == null) {
        // Older SDK path: the even-padding fit, re-centred under our padding.
        final pad = [insets.top, insets.left, insets.bottom + state.padding.bottom, insets.right].reduce(math.max);
        final cam = await map.cameraForCoordinateBounds(
          mb.CoordinateBounds(southwest: _pt(b.southwest), northeast: _pt(b.northeast), infiniteBounds: false),
          mb.MbxEdgeInsets(top: pad, left: pad, bottom: pad, right: pad),
          0,
          0,
          _mbZoom(maxZoom),
          null,
        );
        zoom = cam.zoom?.toDouble();
      }
      await map.flyTo(
        mb.CameraOptions(center: at ?? centre, zoom: zoom == null ? null : math.min(zoom, _mbZoom(maxZoom)), padding: state.padding),
        mb.MapAnimationOptions(duration: ms),
      );
      return;
    }
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

  /// What the camera shows right now, read from the platform (two calls).
  /// Screens that get [AppMap.onCameraChanged] already hold the same view,
  /// worked out without a round trip; this is for before the first event.
  Future<AppCameraView?> cameraView() async {
    final map = _map;
    if (map == null) return null;
    final s = await map.getCameraState();
    final b = await map.coordinateBoundsForCamera(mb.CameraOptions(center: s.center, zoom: s.zoom, bearing: s.bearing, pitch: s.pitch, padding: s.padding));
    return (bounds: LatLngBounds(southwest: _ll(b.southwest), northeast: _ll(b.northeast)), zoom: s.zoom + 1, centre: _ll(s.center));
  }

  /// Google-style zoom (Mapbox + 1), so the tier thresholds in the app stay as they were.
  Future<double> zoom() async {
    final s = await _map?.getCameraState();
    return (s?.zoom ?? 11) + 1;
  }

  Future<void> setPadding(EdgeInsets p) async {
    _padding = p;
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

  Future<void> setMarkers(List<AppMarker> markers) {
    final first = _wantMarkers == null;
    _wantMarkers = markers;
    if (!first) return _queue; // an earlier job will pick these up
    return _serial(() async {
      final m = _wantMarkers;
      _wantMarkers = null;
      if (m != null) await _applyMarkers(m);
    });
  }

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
          // The bytes we already hold (identical to what the pin was created
          // with); see [_updateNeedsImage] for why iOS needs them here.
          a.image = _updateNeedsImage ? w.image : null;
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
    for (final a in toUpdate) {
      await pm.update(a);
    }
    // New pins go up before the ones they replace come down, so a pin that
    // is only changing size or grouping never blinks off in between.
    if (toCreate.isNotEmpty) {
      final created = await pm.createMulti([for (final m in toCreate) _options(m)]);
      for (var i = 0; i < toCreate.length && i < created.length; i++) {
        final a = created[i];
        if (a == null) continue;
        // Both plugins hand back a PNG re-encode of the bitmap. We never send
        // that copy back: a geometry update sets `image` itself, per platform
        // (see [_updateNeedsImage]), from the original bytes in the AppMarker.
        a.image = null;
        _live[toCreate[i].id] = (a, toCreate[i]);
        _byAnnotation[a.id] = toCreate[i].id;
      }
    }
    if (toDelete.isNotEmpty) await pm.deleteMulti(toDelete);
    if (kDebugMode) debugPrint('AppMap: +${toCreate.length} -${toDelete.length} ~${toUpdate.length} -> ${_live.length} live');
  }

  mb.PointAnnotationOptions _options(AppMarker m) => mb.PointAnnotationOptions(
        geometry: _pt(m.position),
        image: m.image,
        iconAnchor: mb.IconAnchor.CENTER,
        // Shift the image so its anchor point, not its centre, sits on the
        // coordinate. icon-offset is in the icon's display units (logical px,
        // times icon-size, which we leave at 1) on both SDKs, and the image
        // displays at m.size logical px on both (see [AppMarker]), so the
        // same numbers land the tip in the same place on iPhone and Android.
        iconOffset: [(0.5 - m.anchor.dx) * m.size.width, (0.5 - m.anchor.dy) * m.size.height],
        // Draw order: higher on top (overlap is allowed, see _attach).
        symbolSortKey: m.zIndex.toDouble(),
      );

  // ---------------------------------------------------- circles + lines ---

  Future<void> setCircles(List<AppCircle> circles) {
    final first = _wantCircles == null;
    _wantCircles = circles;
    if (!first) return _queue;
    return _serial(() async {
      final c = _wantCircles;
      _wantCircles = null;
      if (c != null) await _applyCircles(c);
    });
  }

  Future<void> setLines(List<AppLine> lines) {
    final first = _wantLines == null;
    _wantLines = lines;
    if (!first) return _queue;
    return _serial(() async {
      final l = _wantLines;
      _wantLines = null;
      if (l != null) await _applyLines(l);
    });
  }

  Future<void> _applyCircles(List<AppCircle> circles) async {
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
  }

  Future<void> _applyLines(List<AppLine> lines) async {
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
  }

  // -------------------------------------------------------------- pulses ---

  final _pulses = <String, _PulseState>{};
  /// The style has loaded: runtime sources and layers can be added.
  bool _styleReady = false;

  static String _pulseLayerId(String id) => 'tt-pulse-$id';
  static String _pulseSourceId(String id) => 'tt-pulse-$id-src';
  static const _noPoints = '{"type":"FeatureCollection","features":[]}';

  /// Starts, moves or stops (null, or no points) the pulse named [id]. Cheap
  /// to call on every GPS fix: only a change of points reaches the map.
  void setPulse(String id, AppPulse? pulse) {
    if (_disposed) return;
    final s = _pulses.putIfAbsent(id, _PulseState.new);
    if (pulse == null || pulse.points.isEmpty) {
      s.timer?.cancel();
      s.timer = null;
      s.start?.cancel();
      s.spec = null;
      _setPulseData(id, s, _noPoints);
      return;
    }
    final restart = s.spec == null || s.spec!.period != pulse.period;
    s.spec = pulse;
    _setPulseData(id, s, _featureCollection(pulse.points));
    if (restart) {
      s.timer?.cancel();
      s.timer = Timer.periodic(pulse.period, (_) => _firePulse(id));
      _firePulse(id); // the first ring now, not a period from now
    }
  }

  static String _featureCollection(List<LatLng> points) => jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          for (final p in points)
            {
              'type': 'Feature',
              'properties': const <String, Object>{},
              'geometry': {'type': 'Point', 'coordinates': [p.longitude, p.latitude]},
            },
        ],
      });

  void _setPulseData(String id, _PulseState s, String data) {
    if (s.data == data) return;
    s.data = data;
    _syncPulseData(id, s);
  }

  Future<void> _syncPulseData(String id, _PulseState s) async {
    final map = _map;
    if (map == null || !s.added || s.sent == s.data) return;
    final data = s.data ?? _noPoints;
    s.sent = data;
    try {
      await map.style.setStyleSourceProperty(_pulseSourceId(id), 'data', data);
    } catch (e) {
      s.sent = null;
      if (kDebugMode) debugPrint('AppMap: pulse data failed: $e');
    }
  }

  /// Adds the pulse's source and circle layer, under the pins (above the
  /// accuracy / nearby circles). Needs a loaded style; re-run after a reload.
  Future<void> _ensurePulse(String id, _PulseState s) async {
    final map = _map;
    if (map == null || !_styleReady || s.added || s.adding) return;
    s.adding = true;
    try {
      final style = map.style;
      final src = _pulseSourceId(id), layer = _pulseLayerId(id);
      final data = s.data ?? _noPoints;
      if (await style.styleSourceExists(src)) {
        await style.setStyleSourceProperty(src, 'data', data);
      } else {
        await style.addSource(mb.GeoJsonSource(id: src, data: data));
      }
      s.sent = data;
      if (!await style.styleLayerExists(layer)) {
        final l = mb.CircleLayer(
          id: layer,
          sourceId: src,
          circleRadius: 0,
          circleOpacity: 0,
          circleStrokeOpacity: 0,
          circleStrokeWidth: 2,
          // Full colour at night too: the Standard style's night lighting
          // would otherwise dim a runtime layer.
          circleEmissiveStrength: 1,
          circlePitchAlignment: mb.CirclePitchAlignment.MAP,
        );
        s.underPins = await style.styleLayerExists(_pointsLayer);
        s.underPins ? await style.addLayerAt(l, mb.LayerPosition(below: _pointsLayer)) : await style.addLayer(l);
      }
      s.added = true;
    } catch (e) {
      if (kDebugMode) debugPrint('AppMap: pulse layer failed: $e');
    } finally {
      s.adding = false;
    }
    await _syncPulseData(id, s);
  }

  /// The style (re)loaded: runtime layers are gone with the old one.
  void _onStyleLoaded() {
    _styleReady = true;
    for (final e in _pulses.entries) {
      e.value.added = false;
      e.value.sent = null;
      if (e.value.spec != null) _ensurePulse(e.key, e.value);
    }
  }

  static String _css(Color c) => 'rgba(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()},1)';

  /// One ring. The map's renderer does the animating: the ring is snapped
  /// to its start (no transition), then a moment later its end values are
  /// set with a transition of [AppPulse.duration], which the renderer eases
  /// at the display's frame rate. Two small calls per ring, no bitmaps, no
  /// annotation updates. The pause is so the snap renders before the
  /// transition starts from it (two changes inside one frame would merge).
  Future<void> _firePulse(String id) async {
    final s = _pulses[id];
    final spec = s?.spec;
    final map = _map;
    if (s == null || spec == null || map == null || _disposed) return;
    if (!s.added) {
      await _ensurePulse(id, s);
      if (!s.added) return;
    }
    final layer = _pulseLayerId(id);
    try {
      if (!s.underPins && await map.style.styleLayerExists(_pointsLayer)) {
        // Added before the pins' layer existed: tuck it under them now.
        await map.style.moveStyleLayer(layer, mb.LayerPosition(below: _pointsLayer));
        s.underPins = true;
      }
      const snap = {'duration': 0, 'delay': 0};
      final colour = _css(spec.color);
      await map.style.setStyleLayerProperties(layer, jsonEncode({
        'paint': {
          'circle-radius-transition': snap,
          'circle-opacity-transition': snap,
          'circle-stroke-opacity-transition': snap,
          'circle-color': colour,
          'circle-stroke-color': colour,
          'circle-stroke-width': spec.strokeWidth,
          'circle-radius': spec.fromPx,
          'circle-opacity': spec.fill,
          'circle-stroke-opacity': spec.stroke,
        },
      }));
    } catch (e) {
      if (kDebugMode) debugPrint('AppMap: pulse snap failed: $e');
      return;
    }
    s.start?.cancel();
    s.start = Timer(const Duration(milliseconds: 70), () async {
      final spec = s.spec;
      final map = _map;
      if (spec == null || map == null || _disposed) return;
      final ease = {'duration': spec.duration.inMilliseconds, 'delay': 0};
      try {
        await map.style.setStyleLayerProperties(layer, jsonEncode({
          'paint': {
            'circle-radius-transition': ease,
            'circle-opacity-transition': ease,
            'circle-stroke-opacity-transition': ease,
            'circle-radius': spec.toPx,
            'circle-opacity': 0,
            'circle-stroke-opacity': 0,
          },
        }));
      } catch (e) {
        if (kDebugMode) debugPrint('AppMap: pulse grow failed: $e');
      }
    });
  }

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
    this.onCameraChanged,
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
  /// Every camera frame, with the zoom (Google-style): lets a screen react
  /// while the camera moves and tell when it has settled, without waiting
  /// for the map's idle event (which also waits for every tile to load and
  /// for any animation on the map to finish).
  final AppCameraCallback? onCameraChanged;
  final VoidCallback? onCameraMoveStarted;

  @override
  State<AppMap> createState() => _AppMapState();
}

class _AppMapState extends State<AppMap> {
  @override
  void initState() {
    super.initState();
    widget.controller._padding = widget.padding; // the MapWidget starts with it
  }

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

  /// The map's laid-out size, for [_viewOf].
  Size _size = Size.zero;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        _size = box.biggest;
        return _map();
      });

  Widget _map() {
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
      onStyleLoadedListener: (_) {
        widget.controller._onStyleLoaded();
        widget.controller.setNight(widget.night);
      },
      onMapLoadErrorListener: (e) => debugPrint('AppMap load error: ${e.type} ${e.message}'),
      onMapIdleListener: (_) => widget.onCameraIdle?.call(),
      onCameraChangeListener: (d) {
        widget.onCameraMove?.call(_ll(d.cameraState.center));
        final changed = widget.onCameraChanged;
        if (changed != null && _size.width > 0 && _size.height > 0) changed(_viewOf(d.cameraState, _size, widget.controller._padding));
      },
      onScrollListener: (_) => widget.onCameraMoveStarted?.call(),
      // ignore: deprecated_member_use
      onTapListener: (ctx) => widget.onTap?.call(_ll(ctx.point)),
    );
  }
}
