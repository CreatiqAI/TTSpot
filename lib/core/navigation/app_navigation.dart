import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mapbox/flutter_mapbox.dart';
import 'package:geolocator/geolocator.dart';

import '../geo/latlng.dart';
import '../theme/app_theme.dart';

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

  /// Starts guidance from where the phone is now to [to]. Throws with a
  /// friendly message when there is no fix.
  static Future<void> start({required LatLng to, required String name, List<LatLng> via = const []}) async {
    final from = await _here();
    if (from == null) throw Exception('Turn on location so we know where you are starting from.');
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
