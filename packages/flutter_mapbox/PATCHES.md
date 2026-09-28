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
