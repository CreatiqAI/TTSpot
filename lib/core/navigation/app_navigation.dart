import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_mapbox/flutter_mapbox.dart';
import 'package:geolocator/geolocator.dart';

import '../geo/latlng.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart' show AppException;

/// In-app turn-by-turn on Mapbox's Navigation SDK. Full screen, voice and
/// banner instructions, live traffic, reroutes. Waze stays the default "go";
/// this is for the cases Waze can't do: staying with the convoy and friends.
class AppNavigation {
  AppNavigation._();

  static MapBoxNavigation? _nav;
  static bool _running = false;
  static bool get isRunning => _running;

  static MapBoxNavigation get _instance => _nav ??= MapBoxNavigation(onRouteEvent: _onEvent);

  static void _onEvent(RouteEvent e) {
    switch (e.eventType) {
      case MapBoxEvent.navigation_running:
        _running = true;
      case MapBoxEvent.navigation_finished:
      case MapBoxEvent.navigation_cancelled:
      case MapBoxEvent.route_build_failed:
      case MapBoxEvent.route_build_no_routes_found:
        _running = false;
      default:
        break;
    }
    if (kDebugMode && e.eventType != MapBoxEvent.progress_change) debugPrint('nav: ${e.eventType}');
  }

  /// A start is in flight (fix, route, screen). A second tap is ignored
  /// instead of asking the native side for a second navigation screen.
  static bool _starting = false;

  /// Starts guidance from where the phone is now to [to]. Throws an
  /// [AppException] with a short, friendly message when it cannot (no fix,
  /// no route, the navigation screen could not open), so callers can offer
  /// Waze or Google Maps instead. Never lets a platform error escape raw.
  static Future<void> start({required LatLng to, required String name, List<LatLng> via = const []}) async {
    if (_starting) return;
    _starting = true;
    try {
      await _start(to: to, name: name, via: via);
    } on AppException {
      _running = false;
      rethrow;
    } on PlatformException catch (e) {
      if (e.code == 'ALREADY_NAVIGATING') return; // it is on screen already
      _running = false;
      if (kDebugMode) debugPrint('nav: start failed: ${e.code} ${e.message}');
      throw AppException(e.code == 'ROUTE_FAILED'
          ? 'Couldn\'t find a route there right now. Check your connection, or use another app.'
          : 'In-app navigation couldn\'t start. Use another app for this trip.');
    } catch (e) {
      // MissingPluginException, a bad argument, anything else native.
      _running = false;
      if (kDebugMode) debugPrint('nav: start failed: $e');
      throw const AppException('In-app navigation couldn\'t start. Use another app for this trip.');
    } finally {
      _starting = false;
    }
  }

  static Future<void> _start({required LatLng to, required String name, required List<LatLng> via}) async {
    final from = await _here();
    if (from == null) throw const AppException('Turn on location so we know where you are starting from.');
    final points = <WayPoint>[
      WayPoint(id: 'origin', name: 'You', latitude: from.latitude, longitude: from.longitude),
      for (var i = 0; i < via.length; i++) WayPoint(id: 'via$i', name: 'Stop ${i + 1}', latitude: via[i].latitude, longitude: via[i].longitude),
      WayPoint(id: 'dest', name: name, latitude: to.latitude, longitude: to.longitude),
    ];
    final options = MapBoxOptions(
      initialLatitude: from.latitude,
      initialLongitude: from.longitude,
      zoom: 15,
      tilt: 0,
      bearing: 0,
      enableRefresh: true,
      alternatives: true,
      voiceInstructionsEnabled: true,
      bannerInstructionsEnabled: true,
      allowsUTurnAtWayPoints: true,
      // iOS limits traffic-aware routing to three stops
      mode: points.length > 3 ? MapBoxNavigationMode.driving : MapBoxNavigationMode.drivingWithTraffic,
      units: VoiceUnits.metric,
      simulateRoute: false,
      longPressDestinationEnabled: false,
      mapStyleUrlDay: 'mapbox://styles/mapbox/navigation-day-v1',
      mapStyleUrlNight: 'mapbox://styles/mapbox/navigation-night-v1',
      language: 'en',
      isOptimized: false,
      animateBuildRoute: true,
    );
    _running = true;
    await _instance.startNavigation(wayPoints: points, options: options);
  }

  static Future<void> stop() async {
    if (!_running) return;
    try {
      await _instance.finishNavigation();
    } catch (_) {}
    _running = false;
  }

  static Future<LatLng?> _here() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 2)) return LatLng(last.latitude, last.longitude);
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)));
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }
}

/// Icon tile for the Directions chooser row.
class NavigateTileIcon extends StatelessWidget {
  const NavigateTileIcon({super.key, required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: AppColors.brand),
      );
}
