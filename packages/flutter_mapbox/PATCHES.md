# Local copy of flutter_mapbox 1.0.1 (pub.dev) with TT Spot patches

Upstream: https://github.com/nick92/flutter_mapbox (MIT). Vendored on 2026-09-28
so we can fix things without waiting for a release. Diff against upstream:

1. `FullscreenNavActivity.onCreate()` sets up and attaches `MapboxNavigationApp`
   and defers `setupNavigationComponents()/setupUI()/applyWindowInsets()` to the
   lifecycle's CREATED event (`MapboxNavigationApp.current()` is null until an
   attached owner is CREATED, which is after onCreate returns); `onDestroy()`
   detaches. Without it, full-screen navigation started straight from Dart (no
   embedded view first) crashed with a NullPointerException.

When upstream ships a fix, drop this folder and go back to the pub.dev dependency.

2. `android/build.gradle`: Navigation SDK bumped 3.23.0 -> 3.31.1 so its native
   libraries match the Maps SDK 11.31.1 / Common 24.31.1 that mapbox_maps_flutter
   2.31.1 ships (mixing 3.23 with 11.31 fails at dlopen with a missing symbol).
   The root build.gradle.kts also resolves every Mapbox artifact to its -ndk27 flavour.

3. Full-screen navigation honours the Dart `units` option for banners and the
   trip panel (DistanceFormatterOptions) and hides the map scale bar, which sat
   under the status bar.

4. `ios/flutter_mapbox/Package.swift`: mapbox-navigation-ios pinned exactly to
   3.31.1 (it pins mapbox-maps-ios 11.31.1, the same exact version the map
   plugin requires; 3.24.x wanted an older maps version and SwiftPM failed).

5. iOS full-screen navigation (`NavigationFactory.swift` and
   `SwiftFlutterMapboxPlugin.swift`; `ios/flutter_mapbox/Sources/flutter_mapbox/`
   is what SwiftPM compiles, `ios/Classes/` is kept identical for the podspec).
   Upstream presented from
   `UIApplication.shared.delegate?.window??.rootViewController as! FlutterViewController`.
   TT Spot runs the UIScene lifecycle (`FlutterSceneDelegate`), where the app
   delegate has no window, so that force-cast of nil trapped as soon as the
   route came back: "Navigate in TT Spot" crashed the app on iPhone (0.3.33 to
   0.3.41). Now `NavigationHost.presenter()` uses the plugin registrar's view
   controller, else the foreground scene's key window, else the old delegate
   window, and presents from the topmost controller. Also: a fresh
   NavigationViewController per trip (never re-presents a stale or visible
   one), every early return answers Dart with a FlutterError, a route failure
   is a `ROUTE_FAILED` error instead of a success string, success answers `true`
   once the screen is up, and the multi-leg `_lastKnownLocation!` unwrap is gone.
