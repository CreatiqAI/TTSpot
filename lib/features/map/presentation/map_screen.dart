import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart' show Geolocator, LocationAccuracyStatus, LocationPermission;
import '../../../core/geo/latlng.dart';
import '../../../core/map/app_map.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/location/live_position.dart';
import '../../../core/location/location_gate.dart' show locationGrantedProvider;
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_tab_bar.dart';
import '../../../core/widgets/user_avatar.dart' show DefaultAvatars;
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/geo.dart';
import '../../events/application/event_providers.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/event_car_widgets.dart';
import 'map_list_view.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../profile/application/profile_providers.dart';
import '../../friends/application/friends_providers.dart';
import '../../friends/domain/friend.dart';
import '../../social/application/community_providers.dart';
import '../../social/domain/club.dart';
import '../../social/domain/post.dart';
import '../../social/presentation/story_viewer_screen.dart';
import '../application/map_providers.dart';
import '../../../core/utils/dates.dart';
import 'widgets/map_glyphs.dart';
import 'widgets/location_check_sheet.dart';
import 'widgets/map_legend.dart';
import 'widgets/map_pins.dart';
import 'widgets/map_sheet.dart';
import 'widgets/map_toolbar.dart';
import 'widgets/place_card.dart';
import 'widgets/car_marker.dart';
import 'widgets/visibility_sheet.dart';
import '../../settings/application/settings_providers.dart';

/// Home. One map, three layers: Now (friends, live meets, moments), Upcoming
/// (meets on the calendar) and Spots (places to check in, shown big and
/// named). Spots and partner shops also sit quietly under every other layer.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = AppMapController();
  GlyphMarkerFactory? _glyphs;
  MapPinFactory? _pins;
  CarMarkerFactory? _cars;
  List<AppMarker> _markerSet = const [];
  /// What kinds of pin are on the map right now; feeds the key.
  Set<LegendGlyph> _present = const {};
  List<AppCircle> _circles = const [];
  /// What the accuracy / nearby circles were last drawn from, so a GPS fix
  /// that changes nothing visible never touches the map.
  String _circlesKey = '';
  /// The camera stopped moving a moment ago: time to fetch the view's data.
  Timer? _settle;
  /// The camera moved since the last settle (the map's idle event is only a
  /// fallback for the very first view).
  bool _cameraDirty = false;
  /// When pins were last redrawn for a new zoom while the camera was still
  /// moving (at most a few times a second).
  DateTime _liveRedrawAt = DateTime(0);
  /// The zoom the viewport (and so the spots query) was last set at, and
  /// when: zooming out well past it fetches the wider view before the
  /// gesture ends.
  double _viewportZoom = 99;
  DateTime _viewportAt = DateTime(0);
  int _generation = 0;
  bool _rebuildQueued = false;
  bool _movedToUser = false;
  /// Where the map opens. Resolved before the map is built (a quick read of
  /// the phone's last fix) so the first frame is already "here", not KL.
  ({LatLng target, double zoom})? _initialCamera;
  /// The camera has drifted off me: I am off-screen or > 150 m from the centre.
  bool _awayFromMe = false;
  /// "Back to me" / locate is gliding the camera home: the pill stays hidden
  /// for the flight instead of flickering back while the centre catches up.
  bool _homing = false;
  Timer? _homingTimer;
  final _sheet = DraggableScrollableController();
  /// The glass toolbar hides while the sheet is up.
  bool _sheetOpen = false;
  /// The spot or partner shop whose preview card is up (in place of the
  /// toolbar) and whose pin is drawn picked. Kept after the card closes so
  /// it can slide away with its content.
  Place? _card;
  bool _cardOpen = false;
  final _cardKey = GlobalKey();
  /// The card's laid-out height: the camera centres the place above it.
  double _cardHeight = 0;
  /// How far the card is being dragged down (swipe down = close).
  double _cardDrag = 0;
  bool _cardDragging = false;
  /// The toolbar's clearance from the bottom and the map's own padding for
  /// it, from the last build (the card sits where the toolbar does).
  double _toolbarBottom = 0;
  double _mapPadding = 0;

  static const _mapOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_onSheetMoved);
    _resolveInitialCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(livePositionProvider.notifier).start();
      ref.read(locationPublisherProvider.notifier).start();
    });
  }

  void _onSheetMoved() {
    final open = _sheet.isAttached && _sheet.size > 0.02;
    if (open != _sheetOpen && mounted) setState(() => _sheetOpen = open);
  }

  /// The map follows the app theme (Settings → Appearance).
  bool get _isNight => AppColors.dark;

  /// Zoom tiers, Waze-style. 0 = far: people are dots (or hidden), no
  /// moments. 1 = mid: people as dots, moments. 2 = close: name chips under
  /// the pins, cars with faces. Places and events are teardrops at every
  /// tier, sized by [_pinScale]; below tier 2 the ones that would overlap
  /// merge into count bubbles ([_groups]).
  static const _midZoom = 13.0;
  static const _closeZoom = 14.5;
  int _tier = 0;
  bool get _far => _tier == 0;
  bool get _close => _tier == 2;

  /// Pins grow and shrink with the zoom, not in three fixed jumps. Quantised
  /// to steps of 0.1 (ten sizes in all), so a zoom of less than ~0.8 of a
  /// level usually keeps every bitmap, and the few sizes that exist stay in
  /// the cache. 0.4 at zoom 10 or less, 0.8 at 13, 1.0 around 14.7, 1.3 from
  /// zoom 17 up.
  double _zoom = 12;
  double get _glyphScale => _scaleAt(_zoom);
  static double _scaleAt(double zoom) {
    final t = ((zoom - 10) / 7).clamp(0.0, 1.0);
    return ((0.4 + t * 0.9) * 10).round() / 10;
  }

  /// Teardrop pins (places, events) follow [_glyphScale] but never go under
  /// 0.7 (22 × 28 px), so nothing shrinks to a hard-to-see dot far out.
  double get _pinScale => math.max(_glyphScale, 0.7);

  /// Last position we drew myself at, so a location refresh never blinks me away.
  LatLng? _lastHere;

  /// Metres per logical pixel at the current zoom, so a ring of so many
  /// metres (the radar around a live meet) can be sized in screen px.
  double get _metresPerPx {
    final lat = (_lastHere ?? kualaLumpur).latitude * math.pi / 180;
    return 156543.03392 * math.cos(lat) / math.pow(2, _zoom);
  }

  /// The animated rings: one around me every 2 s, and a radar sweep every
  /// 5 s on each live meet (Now layer). The map draws and eases them itself
  /// (see [AppMapController.setPulse]); this only says where and how big,
  /// and is called when I move, the zoom tier changes or the meets change.
  void _syncPulses() {
    if (!mounted || !_map.isReady) return;
    final here = _lastHere;
    // Out from under my marker: the dot far out, the car badge up close.
    _map.setPulse(
      'me',
      here == null
          ? null
          : AppPulse(points: [here], color: kRelationMe, fromPx: _close ? 26 : 9, toPx: _close ? 62 : 36),
    );
    final live = ref.read(mapModeProvider) == MapMode.now ? (ref.read(liveEventsProvider).value ?? const <Event>[]) : const <Event>[];
    // 350 m of ground at the current zoom (re-sized when the zoom settles).
    final radarPx = (350 / _metresPerPx).clamp(24.0, 400.0);
    _map.setPulse(
      'radar',
      live.isEmpty
          ? null
          : AppPulse(
              points: [for (final e in live) e.latLng],
              color: kEventRed,
              fromPx: radarPx * 0.15,
              toPx: radarPx,
              period: const Duration(seconds: 5),
              duration: const Duration(milliseconds: 1400),
              fill: 0.18,
              stroke: 0.8,
            ),
    );
  }

  /// The still circles under the pins: how sure the phone is of my position,
  /// and the "nearby" sharing radius. Only redrawn when one of them changes.
  void _paintCircles() {
    if (!mounted) return;
    final circles = <AppCircle>[];
    final here = ref.read(userLocationProvider).value ?? _lastHere;
    final live = ref.read(livePositionProvider);
    // How sure the phone is: a soft ring, only when it is worth showing.
    if (live != null && live.accuracyM > 20 && live.accuracyM < 3000) {
      circles.add(AppCircle(
        id: 'me-accuracy',
        center: live.latLng,
        radiusM: live.accuracyM,
        strokeWidth: 1,
        stroke: kRelationMe.withValues(alpha: 0.35),
        fill: kRelationMe.withValues(alpha: 0.08),
        zIndex: 1,
      ));
    }
    if (ref.read(mapModeProvider) == MapMode.now) {
      final my = ref.read(myLocationProvider).value;
      if (my != null && my.shareMode == 'nearby' && here != null) {
        circles.add(AppCircle(
          id: 'nearby-ring',
          center: here,
          radiusM: my.shareRadiusM.toDouble(),
          strokeWidth: 1,
          stroke: AppColors.brand.withValues(alpha: 0.55),
          fill: AppColors.brand.withValues(alpha: 0.05),
        ));
      }
    }
    final key = [for (final c in circles) '${c.id}|${c.center.latitude}|${c.center.longitude}|${c.radiusM}|${c.fill.toARGB32()}'].join(';');
    if (key == _circlesKey) return;
    _circlesKey = key;
    setState(() => _circles = circles);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _homingTimer?.cancel();
    _glyphs?.dispose();
    _pins?.dispose();
    _sheet.dispose();
    _map.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- camera ---

  /// Zoom the map lands on me at: close enough to see my car and the street.
  static const _hereZoom = 14.5;

  /// Land on me from the first frame: a fix we already hold, else the phone's
  /// last known position (a cache read, capped at 300 ms so the map is never
  /// held up), else Kuala Lumpur. A stale cached fix still beats KL as an
  /// opening view; the real fix re-centres us when it lands.
  Future<void> _resolveInitialCamera() async {
    final known = ref.read(livePositionProvider)?.latLng ?? ref.read(userLocationProvider).value;
    if (known != null) {
      _movedToUser = true;
      _lastHere = known;
      _zoom = _hereZoom;
      _tier = _tierFor(_zoom);
      _initialCamera = (target: known, zoom: _hereZoom);
      return;
    }
    LatLng? last;
    var fresh = false;
    try {
      final p = await Geolocator.getLastKnownPosition().timeout(const Duration(milliseconds: 300));
      if (p != null) {
        last = LatLng(p.latitude, p.longitude);
        fresh = DateTime.now().difference(p.timestamp) < LivePositionNotifier.cachedMaxAge;
      }
    } catch (_) {}
    if (!mounted) return;
    if (fresh) _movedToUser = true;
    setState(() {
      _zoom = last == null ? 11.3 : (fresh ? _hereZoom : 13);
      _tier = _tierFor(_zoom);
      _initialCamera = last == null ? (target: kualaLumpur, zoom: 11.3) : (target: last, zoom: fresh ? _hereZoom : 13);
    });
  }

  void _onMapReady() {
    // A "Show on map" that came in before the map was live wins over landing on me.
    _handleFocus();
    _moveToUserIfKnown();
    if (ref.read(mapModeProvider) == MapMode.spots && _pendingFocus == null) _fitNearestSpots();
    // Data that loaded before the map was live (spots from the home tab,
    // a location fix) fires no listener again: draw it now.
    _scheduleRebuild();
    _paintCircles();
    _syncPulses();
  }

  /// The first real fix: jump there straight away if the map has not settled
  /// yet (nobody has seen it, so no need to fly), else glide.
  void _moveToUserIfKnown() {
    final loc = ref.read(userLocationProvider).value;
    // Not live yet: onReady calls us again, so leave the flag alone.
    if (loc == null || _movedToUser || !_map.isReady) return;
    _movedToUser = true;
    _lastHere = loc;
    _hadFirstIdle ? _map.animateTo(loc, zoom: _hereZoom) : _map.moveTo(loc, zoom: _hereZoom);
  }

  static int _tierFor(double zoom) => zoom < _midZoom ? 0 : (zoom < _closeZoom ? 1 : 2);

  bool _hadFirstIdle = false;

  /// The map's idle event. Only the first one matters (the opening view,
  /// where the camera may never have moved). After that the camera's own
  /// events say when it has settled: the idle event also waits for every
  /// tile to load and for any animation on the map to end, which held new
  /// pins back by a second or two after a zoom.
  void _onMapIdle() {
    if (!_hadFirstIdle || _cameraDirty) _scheduleSettle(Duration.zero);
  }

  /// Every camera frame. Restarts the settle timer; while zooming, redraws
  /// the pins for the new zoom a few times a second (sizes and count bubbles
  /// follow the fingers), and zooming out well past the fetched view asks
  /// for the wider view's spots and meets before the gesture ends.
  void _onCameraChanged(AppCameraView view) {
    final zoom = view.zoom;
    _cameraDirty = true;
    _view = view;
    _onCameraMove(view.centre);
    _scheduleSettle(const Duration(milliseconds: 150));
    if (!_hadFirstIdle) return;
    final now = DateTime.now();
    if (_looksAt(zoom) != _looksAt(_zoom) && now.difference(_liveRedrawAt) >= const Duration(milliseconds: 250)) {
      _liveRedrawAt = now;
      _applyZoom(zoom);
      _scheduleRebuild();
    }
    if (zoom < _viewportZoom - 0.6 && now.difference(_viewportAt) >= const Duration(milliseconds: 500)) {
      _viewportAt = now;
      _setViewport(view);
    }
  }

  /// Everything about the pins that depends on the zoom: tier, size, and the
  /// count-bubble grouping, redone every quarter zoom
  /// step below street zoom (below zoom 10 the pin size stops changing, the
  /// grouping must not).
  static (int, double, int) _looksAt(double zoom) =>
      (_tierFor(zoom), _scaleAt(zoom), zoom >= _closeZoom ? -1 : (zoom * 4).round());

  void _applyZoom(double zoom) {
    final tier = _tierFor(zoom);
    final tierChanged = tier != _tier;
    _zoom = zoom;
    _tier = tier;
    if (tierChanged) _syncPulses(); // my ring starts at the dot or at the badge
  }

  void _scheduleSettle(Duration after) {
    _settle?.cancel();
    _settle = Timer(after, _onCameraSettled);
  }

  /// The camera's view from its last event (no platform round trip).
  AppCameraView? _view;

  /// [view] (or, before any camera event, the one read from the map)
  /// becomes the viewport: the spots, meets and moments queries follow it.
  /// Null when the map is not live.
  Future<AppCameraView?> _setViewport([AppCameraView? known]) async {
    final view = known ?? await _map.cameraView();
    if (!mounted || view == null) return null;
    _viewportZoom = view.zoom;
    _viewportAt = DateTime.now();
    ref.read(mapViewportProvider.notifier).set(view.bounds);
    return view;
  }

  /// The camera stopped (150 ms without a camera event): fetch for this view,
  /// redraw if the zoom changed what the pins look like, re-check "away".
  Future<void> _onCameraSettled() async {
    if (!_map.isReady || !mounted) return;
    _cameraDirty = false;
    final view = await _setViewport(_view);
    if (!mounted || view == null) return;
    if (!_hadFirstIdle) {
      // Safety net: one full redraw a few seconds after the map first settles,
      // once location, spots and car photos have had time to arrive. A cold
      // start once ended with only the meet pin until the next layer switch.
      Timer(const Duration(seconds: 3), () {
        if (mounted) _scheduleRebuild();
      });
    }
    _hadFirstIdle = true;
    final before = _looksAt(_zoom);
    _applyZoom(view.zoom);
    if (before != _looksAt(_zoom)) {
      _scheduleRebuild();
    } else {
      _updateKey(); // same pins, new view: the key follows what is in it
    }
    _syncPulses(); // the radar's 350 m in px at this zoom
    _prewarm();
    // Off-screen counts as "away" even when the centre is within 150 m (very
    // close zooms). The camera centre respects the toolbar padding; the
    // bounds' centre does not.
    final here = _lastHere;
    if (here != null) _setAway(!view.bounds.contains(here) || distanceKm(view.centre, here) > 0.15);
  }

  /// Every camera frame: cheap distance check, state changes only on a flip.
  void _onCameraMove(LatLng centre) {
    final here = _lastHere;
    if (here == null) return;
    _setAway(distanceKm(centre, here) > 0.15);
  }

  /// I moved (driving) while the camera stayed put: re-check against the centre.
  Future<void> _checkAway() async {
    final here = _lastHere;
    if (here == null || !_map.isReady) return;
    final centre = await _map.center();
    if (centre != null && mounted) _setAway(distanceKm(centre, here) > 0.15);
  }

  void _setAway(bool away) {
    if (away && _homing) return; // mid-flight home; re-checked when it lands
    if (away != _awayFromMe && mounted) setState(() => _awayFromMe = away);
  }

  /// The locate button and the "Back to me" pill. Glides to the fix we hold,
  /// then again if a fresh one moves us. With no fix at all it asks for what
  /// is missing (location services, the permission) instead of doing nothing.
  Future<void> _locateMe() async {
    final known = ref.read(livePositionProvider)?.latLng ?? ref.read(userLocationProvider).value;
    if (known != null) _flyHome(known);
    var loc = await ref.read(livePositionProvider.notifier).refresh();
    if (loc == null && known == null) {
      if (!await _askForLocation()) return;
      loc = await ref.read(livePositionProvider.notifier).refresh();
    }
    if (loc == null) {
      ref.invalidate(userLocationProvider);
      loc = await ref.read(userLocationProvider.future);
    }
    if (!mounted) return;
    if (loc == null) {
      if (known == null) _snack('No location fix yet. Try again in a moment, ideally with a view of the sky.');
      return;
    }
    if (known == null || distanceKm(known, loc) > 0.01) _flyHome(loc);
  }

  /// Glide to me, make sure my own pin is on the map there, and keep the
  /// "Back to me" pill down: hidden for the flight, re-checked on landing.
  void _flyHome(LatLng at) {
    const ms = 600;
    _lastHere = at;
    _movedToUser = true;
    _homing = true;
    _homingTimer?.cancel();
    _homingTimer = Timer(const Duration(milliseconds: ms + 250), () {
      _homing = false;
      _checkAway();
    });
    _setAway(false);
    _map.animateTo(at, zoom: 15, ms: ms);
    // Draws my marker if it is missing (first fix, or it was never built).
    _updateMe();
  }

  /// Same asks as the location gate (which cannot be reopened once skipped):
  /// location services, then the system prompt, then Settings when it was
  /// denied for good. True when a fix is worth trying for again.
  Future<bool> _askForLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) _snack('Location services are off.', action: SnackBarAction(label: 'Turn on', onPressed: () => Geolocator.openLocationSettings()));
        return false;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (!mounted) return false;
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        _snack('TT Spot needs your location to show you on the map.', action: SnackBarAction(label: 'Settings', onPressed: () => Geolocator.openAppSettings()));
        return false;
      }
      ref.invalidate(locationGrantedProvider);
      await ref.read(livePositionProvider.notifier).start();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _turnOnPrecise() async {
    final ok = await requestPreciseLocation();
    ref.invalidate(locationPrecisionProvider);
    if (ok) await ref.read(livePositionProvider.notifier).refresh();
  }

  void _openSheet({bool full = false}) =>
      _sheet.animateTo(full ? MapSheet.full : MapSheet.half, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);

  void _focus(LatLng target, {double zoom = 15}) {
    _map.animateTo(target, zoom: zoom);
    _sheet.animateTo(MapSheet.closed, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  // ---------------------------------------------------------- spots view ---

  MapFocus? get _pendingFocus => ref.read(mapFocusProvider);

  /// Glide to where another screen asked for; with a place (Search, "Show on
  /// map" on a spot), open its card too.
  void _handleFocus() {
    final f = _pendingFocus;
    if (f == null || !_map.isReady) return;
    // The first GPS fix must not pull the camera back to me afterwards.
    _movedToUser = true;
    Future.microtask(() => ref.read(mapFocusProvider.notifier).clear());
    final place = f.place;
    place == null ? _focus(f.at, zoom: 16) : _openCard(place);
  }

  // ---------------------------------------------------------------- card ---

  /// The camera padding while the card is up: the place lands in the middle
  /// of the map left between the mode switch and the card.
  EdgeInsets get _cardPadding => EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 56, bottom: _toolbarBottom + _cardHeight + 12);

  /// A spot or partner shop was picked (its pin, the list, Search): draw its
  /// pin picked, bring the card up in place of the toolbar, and glide in so
  /// the place sits in the open map above the card, at street zoom.
  Future<void> _openCard(Place p) async {
    _movedToUser = true;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_sheetOpen) _sheet.animateTo(MapSheet.closed, duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
    setState(() {
      _card = p;
      _cardOpen = true;
      _cardDrag = 0;
    });
    _scheduleRebuild();
    // One frame so the card has a size to centre above.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_cardOpen || _card?.id != p.id) return;
    _cardHeight = _cardKey.currentContext?.size?.height ?? 300;
    if (_map.isReady) _map.animateTo(p.latLng, zoom: math.max(_zoom, 16), padding: _cardPadding, ms: 700);
  }

  /// The card grew or shrank (its data came in): keep the place centred.
  void _onCardResized() {
    final h = _cardKey.currentContext?.size?.height;
    final p = _card;
    if (h == null || p == null || !_cardOpen || (h - _cardHeight).abs() < 8) return;
    _cardHeight = h;
    if (_map.isReady) _map.animateTo(p.latLng, padding: _cardPadding, ms: 300);
  }

  /// Map tap, the X or a swipe down: the card goes, the toolbar and
  /// the plain pin come back, and the camera padding eases back to the toolbar's.
  void _closeCard() {
    if (!_cardOpen) return;
    setState(() {
      _cardOpen = false;
      _cardDragging = false;
      _cardDrag = 0;
    });
    _scheduleRebuild();
    _map.animatePadding(EdgeInsets.only(bottom: _mapPadding));
  }

  void _onCardDragEnd(DragEndDetails d) {
    if (_cardDrag > 60 || (d.primaryVelocity ?? 0) > 300) {
      _closeCard();
    } else {
      setState(() {
        _cardDragging = false;
        _cardDrag = 0;
      });
    }
  }

  /// Room around fitted points: the mode switch on top, the round buttons on
  /// the right. The toolbar at the bottom is already the map's own padding.
  EdgeInsets get _fitInsets => EdgeInsets.fromLTRB(44, MediaQuery.paddingOf(context).top + 64, 72, 36);

  /// The Spots layer opens on me and my 5 nearest spots, however far away
  /// they are, so it never opens on an empty street.
  Future<void> _fitNearestSpots() async {
    List<Place> near;
    try {
      near = await ref.read(nearestSpotsProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted || !_map.isReady || ref.read(mapModeProvider) != MapMode.spots || _pendingFocus != null) return;
    final here = ref.read(userLocationProvider).value ?? _lastHere;
    final points = [?here, for (final p in near.take(5)) p.latLng];
    if (points.isEmpty) return;
    if (points.length == 1) {
      await _map.animateTo(points.first, zoom: 15);
      return;
    }
    await _map.fitBounds(boundsAround(points), insets: _fitInsets, maxZoom: 15.5, ms: 700);
  }

  /// "3 spots nearby · closest Wheels Cafe 4.2 km" on Now and Upcoming while
  /// no spot is in view (the map opens on me, usually on a street without
  /// one). Null = no pill: a spot is in view, or it was closed this session.
  String? _spotsHint() {
    if (ref.watch(spotsHintDismissedProvider)) return null;
    final view = ref.watch(mapViewportProvider);
    final inView = ref.watch(spotsProvider).value;
    if (view == null || inView == null || inView.isNotEmpty) return null;
    final saved = ref.watch(savedPlacesProvider).value ?? const <Place>[];
    if (saved.any((p) => view.contains(p.latLng))) return null;
    final origin = ref.watch(mapOriginProvider);
    final near = [...ref.watch(nearestSpotsProvider).value ?? const <Place>[]]
      ..sort((a, b) => distanceKm(origin, a.latLng).compareTo(distanceKm(origin, b.latLng)));
    if (near.isEmpty) return null;
    final closest = near.first;
    final km = formatDistance(distanceKm(origin, closest.latLng));
    final n = near.where((p) => distanceKm(origin, p.latLng) <= 30).length;
    if (n == 0) return 'Nearest spot · ${closest.name} $km';
    return '$n spot${n == 1 ? '' : 's'} nearby · closest ${closest.name} $km';
  }

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  // ------------------------------------------------------------- markers ---

  MapPinFactory get _pinFactory => _pins ??= MapPinFactory(devicePixelRatio: MediaQuery.devicePixelRatioOf(context));
  GlyphMarkerFactory get _glyphFactory => _glyphs ??= GlyphMarkerFactory(devicePixelRatio: MediaQuery.devicePixelRatioOf(context));

  /// Events are teardrops a touch bigger than spots: red with a flag, gold
  /// with a crown for official clubs, ink with a storefront for partners; TT
  /// sessions carry a pennant flag. Label only when close.
  Future<MapPin> _eventPin(Event e, {String? sub, required double pinScale}) {
    final official = e.isOfficialClubEvent;
    final partner = e.vendorId != null;
    final tt = e.type == EventType.tt || e.isInstant;
    return _glyphFactory.teardrop(
      color: official ? kGold : (partner ? kInk : kEventRed),
      glyph: tt ? AppIcons.flagPennantFill : (official ? AppIcons.crownFill : (partner ? AppIcons.storefrontFill : AppIcons.flagFill)),
      label: _close ? (e.isInstant ? e.venueName : e.title) : null,
      sub: _close ? sub : null,
      scale: pinScale * 1.1,
    );
  }
  /// Dropped by [build] when the map switches between day and night (my halo differs).
  CarMarkerFactory get _carFactory => _cars ??= CarMarkerFactory(devicePixelRatio: MediaQuery.devicePixelRatioOf(context), pins: _pinFactory, night: _isNight);

  /// From a zoomed-out view, glide in to the pin first, then open its page.
  /// Up close, open straight away.
  Future<void> _openAt(LatLng at, VoidCallback open) async {
    if (_map.isReady && _zoom < 14.5) {
      await _map.animateTo(at, zoom: 16);
      await Future<void>.delayed(const Duration(milliseconds: 520));
      if (!mounted) return;
    }
    open();
  }

  /// Coalesces redraw requests that arrive together (a new viewport
  /// refreshes four providers at once, each with a loading and a data
  /// event) into one redraw on the next microtask.
  void _scheduleRebuild() {
    if (_rebuildQueued) return;
    _rebuildQueued = true;
    scheduleMicrotask(() {
      _rebuildQueued = false;
      if (mounted) _rebuild();
    });
  }

  /// An async value's data changed (not just its loading flag, which keeps
  /// the old list while a new viewport's query runs).
  static bool _newData<T>(AsyncValue<T>? prev, AsyncValue<T> next) => !identical(prev?.value, next.value);

  /// The teardrops of the last redraw, for [_prewarm].
  List<_Drop> _lastDrops = const [];
  List<List<_Drop>> _lastGroups = const [];

  Future<void> _rebuild() async {
    final generation = ++_generation;
    final mode = ref.read(mapModeProvider);
    final built = <AppMarker>[];
    // Where each kind of pin is drawn: the key lists the kinds in view.
    final keyed = <(LatLng, LegendGlyph)>[];
    // Teardrops (events, spots, partner shops), gathered first so close
    // ones can merge into a count bubble when zoomed out.
    final drops = <_Drop>[];

    Future<bool> stale() async => generation != _generation || !mounted;
    LegendGlyph eventGlyph(Event e) => e.type == EventType.tt || e.isInstant
        ? LegendGlyph.flag
        : e.isOfficialClubEvent
            ? LegendGlyph.officialEvent
            : e.vendorId != null
                ? LegendGlyph.partnerEvent
                : LegendGlyph.balloon;
    _Drop eventDrop(Event e, String sub) => _Drop(
          id: 'event:${e.id}',
          at: e.latLng,
          glyphs: {eventGlyph(e)},
          z: 3, // above the spots underneath
          event: true,
          pin: (scale) => _eventPin(e, sub: sub, pinScale: scale),
          onTap: () => _openAt(e.latLng, () => context.push(Routes.event(e.id))),
        );

    switch (mode) {
      case MapMode.now:
        for (final e in ref.read(liveEventsProvider).value ?? const <Event>[]) {
          drops.add(eventDrop(e, e.checkinCount > 0 ? 'LIVE · ${e.checkinCount} here' : 'LIVE'));
        }
        _addPlaces(drops, focused: false);
      case MapMode.upcoming:
        final now = DateTime.now();
        for (final e in ref.read(mapEventsProvider).value ?? const <Event>[]) {
          drops.add(eventDrop(e, relativeShort(e.startsAt, now: now)));
        }
        _addPlaces(drops, focused: false);
      case MapMode.spots:
        _addPlaces(drops, focused: true);
    }
    // Every pin at once: bitmaps already in the cache come straight back,
    // the rest paint side by side instead of one after another.
    final pinScale = _pinScale;
    final groups = _groups(drops);
    final pins = await Future.wait([
      for (final group in groups)
        group.length == 1
            ? group.first.pin(pinScale)
            // Red when a meet is in it, ink for places only.
            : _glyphFactory.cluster(count: group.length, color: group.any((d) => d.event) ? kEventRed : kInk, scale: pinScale),
    ]);
    if (await stale()) return;
    _lastDrops = drops;
    _lastGroups = groups;
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      final pin = pins[i];
      if (group.length == 1) {
        final d = group.first;
        for (final g in d.glyphs) {
          keyed.add((d.at, g));
        }
        built.add(AppMarker(id: d.id, position: d.at, image: pin.bytes, size: pin.size, anchor: pin.anchor, zIndex: d.z, onTap: d.onTap));
      } else {
        final at = LatLng(
          group.map((d) => d.at.latitude).reduce((a, b) => a + b) / group.length,
          group.map((d) => d.at.longitude).reduce((a, b) => a + b) / group.length,
        );
        keyed.add((at, LegendGlyph.cluster));
        built.add(AppMarker(id: 'group:${group.first.id}', position: at, image: pin.bytes, size: pin.size, anchor: pin.anchor, zIndex: 5, onTap: () => _zoomToGroup(group)));
      }
    }
    // Places and events go up now. Moments and people follow (a moment's
    // photo or a car photo may still be downloading, which on a slow
    // network takes many seconds); until then the ones already on the map
    // stay where they are.
    final withPeople = mode == MapMode.now;
    final withMoments = mode == MapMode.now && !_far;
    bool slow(String id) => id == 'me' || (withPeople && id.startsWith('friend:')) || (withMoments && id.startsWith('moment:'));
    setState(() => _markerSet = [...built, for (final m in _markerSet) if (slow(m.id)) m]);
    _keyed = [...keyed, for (final k in _keyed) if (_slowGlyphs.contains(k.$2)) k];
    _updateKey();
    if (withMoments) {
      final moments = [for (final m in ref.read(liveMomentsProvider).value ?? const <Story>[]) if (m.latLng != null) m];
      final momentPins = await Future.wait([for (final m in moments) _pinFactory.moment(key: m.id, imageUrl: m.photoUrl, scale: _glyphScale)]);
      if (await stale()) return;
      for (var i = 0; i < moments.length; i++) {
        final m = moments[i];
        final at = m.latLng!;
        final pin = momentPins[i];
        keyed.add((at, LegendGlyph.moment));
        built.add(AppMarker(
          id: 'moment:${m.id}',
          position: at,
          image: pin.bytes,
          size: pin.size,
          anchor: pin.anchor,
          zIndex: 1,
          onTap: () => _openAt(at, () => _openMoment(m)),
        ));
      }
    }
    await _addPeople(built, stale, keyed, onlyMe: mode != MapMode.now);
    if (await stale()) return;
    if (kDebugMode) debugPrint('map: ${built.length} markers, tier $_tier, zoom ${_zoom.toStringAsFixed(1)}');
    setState(() => _markerSet = built);
    _keyed = keyed;
    _updateKey();
    _syncPulses();
  }

  bool _prewarming = false;

  /// While the map is still, paints the pins on it at the next size up and
  /// down in the background, so the next zoom finds its bitmaps in the cache
  /// and the pins change size at once. One at a time: never a burst of work.
  Future<void> _prewarm() async {
    if (_prewarming || !mounted) return;
    _prewarming = true;
    final generation = _generation;
    try {
      final here = _glyphScale;
      final sizes = {
        for (final g in [here - 0.1, here + 0.1])
          if (g >= 0.4 - 1e-9 && g <= 1.3 + 1e-9) math.max((g * 10).round() / 10, 0.7),
      }..remove(_pinScale);
      // A bound on the work: with many labelled pins up close, the ones that
      // do not fit in it simply paint on demand.
      var budget = 80;
      for (final scale in sizes) {
        for (final group in _lastGroups) {
          if (!mounted || generation != _generation || _cameraDirty || --budget < 0) return; // the view moved on
          if (group.length == 1) {
            await group.first.pin(scale);
          } else {
            await _glyphFactory.cluster(count: group.length, color: group.any((d) => d.event) ? kEventRed : kInk, scale: scale);
          }
        }
        for (final d in _lastDrops) {
          if (!mounted || generation != _generation || _cameraDirty || --budget < 0) return;
          await d.pin(scale); // the ones inside bubbles now may stand alone next
        }
      }
    } finally {
      _prewarming = false;
    }
  }

  /// Every drawn pin's kind and place, from the last rebuild.
  List<(LatLng, LegendGlyph)> _keyed = const [];
  /// Pins drawn in the second, slower phase of a redraw.
  static const _slowGlyphs = {LegendGlyph.me, LegendGlyph.friend, LegendGlyph.club, LegendGlyph.nearby, LegendGlyph.moment};

  /// The key lists the kinds of pin in view right now (not the ones off
  /// screen, not the ones folded into a count bubble).
  void _updateKey() {
    final view = ref.read(mapViewportProvider);
    final present = {for (final (at, g) in _keyed) if (view == null || view.contains(at)) g};
    if (!setEquals(present, _present) && mounted) setState(() => _present = present);
  }

  /// Teardrops closer than this on screen merge into one count bubble.
  static const _groupPx = 32.0;

  /// Below street zoom, pins that would overlap merge (greedy: each joins
  /// the first group whose first pin is within [_groupPx]). Distances are in
  /// Web Mercator pixels at the current zoom, so the groups hold still while
  /// the map pans. The picked place always stands alone.
  List<List<_Drop>> _groups(List<_Drop> drops) {
    if (_zoom >= _closeZoom) return [for (final d in drops) [d]];
    final world = 256 * math.pow(2, _zoom);
    Offset px(LatLng p) {
      final s = math.sin(p.latitude * math.pi / 180);
      return Offset((p.longitude + 180) / 360 * world, (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * world);
    }

    final out = <List<_Drop>>[];
    final seeds = <(Offset, List<_Drop>)>[];
    for (final d in drops) {
      if (d.alone) {
        out.add([d]);
        continue;
      }
      final p = px(d.at);
      final near = seeds.where((s) => (s.$1 - p).distance < _groupPx).firstOrNull;
      if (near == null) {
        final g = [d];
        seeds.add((p, g));
        out.add(g);
      } else {
        near.$2.add(d);
      }
    }
    return out;
  }

  /// A count bubble: zoom in until its pins come apart.
  void _zoomToGroup(List<_Drop> group) {
    if (!_map.isReady) return;
    _map.fitBounds(boundsAround([for (final d in group) d.at]), insets: _fitInsets, maxZoom: 16, ms: 600);
  }

  /// Spots (car cafés, mamaks, carparks, the check-in places the home Spots
  /// tab lists) and partner shops, on every layer, as teardrops: spots in
  /// their kind's colour and silhouette, partner shops ink with a red
  /// outline and a storefront.
  ///
  /// [focused] = the Spots layer: full size, names and check-in counts up
  /// close. On Now and Upcoming spots sit quietly under the events and
  /// people (zIndex 0), a little smaller, never a label. Partner shops look
  /// the same on every layer.
  ///
  /// My saved spots are always drawn, wherever the camera is (the viewport
  /// query alone would drop them): full size with a bookmark badge, a name
  /// up close on every layer, above the other spots.
  ///
  /// The place whose card is open is drawn 1.4× with a halo, on top and
  /// never folded into a bubble, even when the viewport query has not
  /// brought it in (a search result).
  void _addPlaces(List<_Drop> drops, {required bool focused}) {
    final savedIds = ref.read(savedPlaceIdsProvider);
    final picked = _cardOpen ? _card : null;
    final places = ref.read(mapPlacesProvider);
    for (final p in [...places, if (picked != null && !places.any((x) => x.id == picked.id)) picked]) {
      final kind = spotKindOf(p.kind);
      final saved = savedIds.contains(p.id);
      final selected = p.id == picked?.id;
      double scaleFor(double pinScale) => (p.isPartner || focused || saved ? pinScale : math.max(pinScale * 0.85, 0.7)) * (selected ? 1.4 : 1);
      drops.add(_Drop(
        id: 'place:${p.id}',
        at: p.latLng,
        glyphs: p.isPartner ? {LegendGlyph.partner} : {legendGlyphForSpot(kind), if (p.recommended) LegendGlyph.topSpot, if (saved) LegendGlyph.savedSpot},
        // The picked pin sits over everything but me.
        z: selected ? _meZ - 1 : p.isPartner ? (focused ? 3 : 2) : saved ? (focused ? 3 : 1) : (focused ? (p.recommended ? 2 : 1) : 0),
        alone: selected,
        pin: (pinScale) => p.isPartner
            ? _glyphFactory.teardrop(
                color: kInk,
                outline: kEventRed,
                glyph: AppIcons.storefrontFill,
                selected: selected,
                label: _close ? (p.vendorName ?? p.name) : null,
                scale: scaleFor(pinScale),
              )
            : _glyphFactory.teardrop(
                color: spotKindColor(kind),
                kind: kind,
                recommended: p.recommended,
                saved: saved,
                selected: selected,
                label: (focused || saved) && _close ? p.name : null,
                sub: focused && _close && p.totalCheckins > 0 ? '${p.totalCheckins} ✓' : null,
                scale: scaleFor(pinScale),
              ),
        onTap: () => _openCard(p),
      ));
    }
  }

  /// Friends, clubmates, nearby strangers and me. Cars when zoomed in, dots
  /// at every zoom out from there (never hidden: whoever the "On the map"
  /// list shows is on the map too). Colour = relationship, or the colour I
  /// gave a friend.
  Future<void> _addPeople(List<AppMarker> built, Future<bool> Function() stale, List<(LatLng, LegendGlyph)> keyed, {bool onlyMe = false}) async {
    final tags = ref.read(friendTagsProvider).value ?? const <String, String>{};
    if (!onlyMe) {
      for (final f in ref.read(friendPinsProvider).value ?? const <FriendPin>[]) {
        final stranger = f.isStranger;
        final relation = stranger ? kRelationStranger : (kTagColors[tags[f.user.id]] ?? (f.viaClub ? kRelationClub : kRelationFriend));
        final name = stranger ? '@${f.user.username ?? ''}' : (f.user.displayName ?? f.user.username ?? '');
        final photo = f.carPhoto;
        final pin = !_close
            // Never smaller than ~11 px, so a friend far out stays findable.
            ? await _carFactory.dot(key: f.user.id, color: relation, scale: math.max(_glyphScale, 0.8))
            : photo != null
                // Their car's portrait in a ring of the relationship colour.
                ? await _carFactory.badge(
                    key: f.user.id,
                    coverUrl: photo,
                    name: stranger ? (f.carTitle ?? name) : name,
                    ring: relation,
                    status: stranger ? null : freshnessLabel(f.updatedAt),
                    statusColor: f.isFresh ? const Color(0xFF22C55E) : const Color(0xFF8A919E),
                    headingDeg: f.heading,
                    dim: stranger || !f.isFresh,
                  )
                // No photo yet: the top-down car in their colour.
                : await _carFactory.car(
                    key: f.user.id,
                    colorKey: f.carColor ?? (stranger ? 'grey' : 'silver'),
                    name: stranger ? (f.carTitle ?? name) : name,
                    status: stranger ? null : freshnessLabel(f.updatedAt),
                    statusColor: f.isFresh ? const Color(0xFF22C55E) : const Color(0xFF8A919E),
                    headingDeg: f.heading ?? 0,
                    faceUrl: (f.user.avatarUrl ?? '').isNotEmpty ? f.user.avatarUrl : DefaultAvatars.forSeed(f.user.id, name),
                    showFace: !stranger,
                    dim: stranger || !f.isFresh,
                    relation: relation,
                  );
        if (await stale()) return;
        keyed.add((f.latLng, stranger ? LegendGlyph.nearby : (f.viaClub ? LegendGlyph.club : LegendGlyph.friend)));
        built.add(AppMarker(
          id: 'friend:${f.user.id}',
          position: f.latLng,
          image: pin.bytes, size: pin.size,
          anchor: pin.anchor,
          zIndex: stranger ? 2 : 4,
          onTap: () => _openAt(f.latLng, () => context.push(Routes.profile(f.user.id))),
        ));
      }
    }
    final here = ref.read(userLocationProvider).value ?? _lastHere;
    if (here != null) _lastHere = here;
    final me = ref.read(currentUserIdProvider);
    if (here != null && me != null) {
      final pin = await _mePin(me);
      if (await stale()) return;
      keyed.add((here, LegendGlyph.me));
      built.add(AppMarker(id: 'me', position: here, image: pin.bytes, size: pin.size, anchor: pin.anchor, zIndex: _meZ));
    }
  }

  /// Above every other pin, always.
  static const _meZ = 10;

  /// My marker for the current tier: my car's portrait badge (or the
  /// top-down car when it has no photo) up close, a red dot on a halo further
  /// out. Both carry a heading cone once the phone knows which way I face.
  Future<MapPin> _mePin(String me) {
    final live = ref.read(livePositionProvider);
    final heading = live != null && live.age < const Duration(minutes: 2) ? live.heading : null;
    if (!_close) return _carFactory.meDot(headingDeg: heading, scale: _glyphScale);
    final showColor = ref.read(settingsProvider).showCarColor;
    final myCars = ref.read(userCarsProvider(me)).value ?? const [];
    final myCar = myCars.where((c) => c.isDefault).firstOrNull ?? myCars.firstOrNull;
    return _carFactory.me(coverUrl: myCar?.cover, colorKey: showColor ? (myCar?.color ?? 'red') : 'red', headingDeg: heading);
  }

  /// Only my own pin moved or turned: swap that one marker instead of
  /// rebuilding all. The bitmap is cached per 10° of heading, so this is
  /// usually just a position update on the annotation.
  Future<void> _updateMe() async {
    final here = ref.read(userLocationProvider).value ?? _lastHere;
    final me = ref.read(currentUserIdProvider);
    if (here == null || me == null) return;
    _lastHere = here;
    _syncPulses(); // the ring follows me
    // Not drawn yet (first fix, or a map with nothing else on it): full rebuild.
    if (_markerSet.indexWhere((m) => m.id == 'me') < 0) {
      _scheduleRebuild();
      return;
    }
    final pin = await _mePin(me);
    if (!mounted) return;
    final idx = _markerSet.indexWhere((m) => m.id == 'me');
    if (idx < 0) return;
    setState(() => _markerSet = [..._markerSet]..[idx] = AppMarker(id: 'me', position: here, image: pin.bytes, size: pin.size, anchor: pin.anchor, zIndex: _meZ));
    _keyed = [for (final k in _keyed) if (k.$2 != LegendGlyph.me) k, (here, LegendGlyph.me)];
    _updateKey();
    _checkAway();
  }

  void _openMoment(Story m) {
    final author = m.author;
    if (author == null) return;
    context.push(
      Routes.stories,
      extra: StoryViewerArgs(groups: [StoryGroup(author: author, stories: [m], allSeen: true)], initialGroup: 0),
    );
  }

  // ------------------------------------------------------------- actions ---

  bool _nearbyBusy = false;

  /// One tap on the "You're at ..." card: a manual check-in with a fresh fix.
  /// The card flips to "Checked in" and clears itself.
  Future<void> _checkInNearby(NearbyMeet meet) async {
    if (_nearbyBusy) return;
    final car = await chooseCheckinCar(context, ref, meet.id); // asks only with 2+ cars
    if (car.cancelled || !mounted) return;
    setState(() => _nearbyBusy = true);
    try {
      await ref.read(eventActionsProvider).checkIn(meet.id, carId: car.car?.id);
      ref.read(nearbyMeetProvider.notifier).markCheckedIn();
      ref.invalidate(liveEventsProvider);
    } catch (e) {
      // The meet may have ended or been removed while the card was up.
      ref.read(nearbyMeetProvider.notifier).dismiss();
      ref.invalidate(liveEventsProvider);
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _nearbyBusy = false);
    }
  }

  // --------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    ref.listen(mapModeProvider, (prev, next) {
      _scheduleRebuild();
      _paintCircles();
      _syncPulses();
      if (next == MapMode.spots && prev != MapMode.spots && _pendingFocus == null) _fitNearestSpots();
    });
    ref.listen(savedPlacesProvider, (p, n) {
      if (_newData(p, n)) _scheduleRebuild();
    });
    ref.listen(mapFocusProvider, (_, next) {
      if (next != null) _handleFocus();
    });
    ref.listen(mapEventsProvider, (p, n) {
      if (_newData(p, n)) _scheduleRebuild();
    });
    ref.listen(liveEventsProvider, (p, n) {
      if (!_newData(p, n)) return;
      _scheduleRebuild();
      _syncPulses();
    });
    ref.listen(liveMomentsProvider, (p, n) {
      if (_newData(p, n)) _scheduleRebuild();
    });
    ref.listen(friendPinsProvider, (p, n) {
      if (_newData(p, n)) _scheduleRebuild();
    });
    ref.listen(spotsProvider, (p, n) {
      if (_newData(p, n)) _scheduleRebuild();
    });
    ref.listen(userLocationProvider, (prev, next) {
      _moveToUserIfKnown();
      // First fix (or lost/regained): everything re-sorts. Afterwards just move my pin.
      if (prev?.value == null || next.value == null) {
        _scheduleRebuild();
      } else {
        _updateMe();
      }
      _paintCircles();
    });
    ref.listen(livePositionProvider, (_, _) => _paintCircles());
    ref.listen(myLocationProvider, (_, _) => _paintCircles());
    ref.listen(friendTagsProvider, (p, n) {
      if (_newData(p, n)) _scheduleRebuild();
    });
    MapPalette.defaultLight = !_isNight;
    // Day <-> night keeps this screen (the shell's navigator keeps its
    // state), but my halo is painted per map style: redraw the pins.
    if (_cars != null && _cars!.night != _isNight) {
      _cars = null;
      _scheduleRebuild();
    }

    final mode = ref.watch(mapModeProvider);
    final hasLocation = ref.watch(userLocationProvider).value != null;
    final shareMode = ref.watch(myLocationProvider).value?.shareMode ?? 'friends';
    final nearby = ref.watch(nearbyMeetProvider);
    final listView = ref.watch(mapListViewProvider);
    final loading = switch (mode) {
      MapMode.now => ref.watch(liveEventsProvider).isLoading || ref.watch(friendPinsProvider).isLoading,
      MapMode.upcoming => ref.watch(mapEventsProvider).isLoading,
      MapMode.spots => ref.watch(spotsProvider).isLoading,
    };
    // The shell extends the body under the tab bar, so this inset already
    // includes the bar; guard for the rare case it doesn't.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final barSpace = GlassTabBar.height + GlassTabBar.margin.bottom;
    final toolbarBottom = (bottomInset >= barSpace ? bottomInset : bottomInset + barSpace) + 8;
    final mapPadding = toolbarBottom + MapToolbar.height + 6;
    _toolbarBottom = toolbarBottom;
    _mapPadding = mapPadding;
    final reduced = ref.watch(locationPrecisionProvider).value == LocationAccuracyStatus.reduced;
    final spotsHint = mode == MapMode.spots ? null : _spotsHint();
    // The sheet or the card covers the bottom: the toolbar and the pills above it step aside.
    final bottomBusy = _sheetOpen || _cardOpen;
    final backToMe = hasLocation && _awayFromMe && !bottomBusy;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _isNight ? _mapOverlay : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.mapBg,
        body: Stack(
          children: [
            if (_initialCamera == null)
              // A beat (<= 300 ms) while we read the phone's last fix, so the
              // map is born centred on me instead of flying in from KL.
              const ColoredBox(color: AppColors.mapBg, child: SizedBox.expand())
            else
            AppMap(
              controller: _map,
              initialTarget: _initialCamera!.target,
              initialZoom: _initialCamera!.zoom,
              night: _isNight,
              markers: _markerSet,
              circles: _circles,
              padding: EdgeInsets.only(bottom: mapPadding),
              onReady: _onMapReady,
              onCameraIdle: _onMapIdle,
              onCameraChanged: _onCameraChanged,
              // Tap the map (not a pin) while the card or the sheet is up: close it.
              onTap: (_) {
                if (_cardOpen) {
                  _closeCard();
                } else if (_sheetOpen) {
                  _sheet.animateTo(MapSheet.closed, duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
                }
              },
            ),

            // Mode switch + banners, and the key on the left under them: it
            // moves down with whichever banners show, and stops short of the
            // toolbar and the pills above it ("Back to me", "N spots nearby").
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 70),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ModeSwitch(mode: mode, loading: loading, onChanged: (m) => ref.read(mapModeProvider.notifier).set(m)),
                            if (reduced) ...[
                              const SizedBox(height: 10),
                              _PreciseBanner(onTurnOn: _turnOnPrecise),
                            ],
                            if (nearby != null) ...[
                              const SizedBox(height: 10),
                              _NearbyBanner(
                                title: nearby.title,
                                done: nearby.done,
                                busy: _nearbyBusy,
                                onCheckIn: () => _checkInNearby(nearby),
                                onDismiss: () => ref.read(nearbyMeetProvider.notifier).dismiss(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // The key: what the pins on the map right now mean. Its
                    // list scrolls in whatever room is left; none left, it hides.
                    Flexible(
                      child: Padding(
                        padding: EdgeInsets.only(top: 12, left: 12, bottom: toolbarBottom + (_cardOpen ? _cardHeight + 16 : MapToolbar.height + 120)),
                        child: MapLegend(light: !_isNight, present: _present),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Right-side round buttons
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, right: 14),
                  child: Column(
                    children: [
                      _RoundButton(
                        icon: switch (shareMode) { 'nearby' => AppIcons.broadcast, 'public' => AppIcons.globe, 'ghost' => AppIcons.eyeSlash, _ => AppIcons.eye },
                        tooltip: 'Who can see me',
                        active: shareMode == 'nearby' || shareMode == 'public',
                        light: !_isNight,
                        onTap: () => showVisibilitySheet(context),
                      ),
                      const SizedBox(height: 10),
                      _RoundButton(
                        icon: hasLocation ? AppIcons.gpsFix : AppIcons.crosshair,
                        tooltip: 'My location · hold to check',
                        active: hasLocation && !_awayFromMe,
                        light: !_isNight,
                        onTap: _locateMe,
                        onLongPress: () => showLocationCheckSheet(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // "Back to me": only while the camera has wandered off me.
            Positioned(
              left: 0,
              right: 0,
              bottom: toolbarBottom + MapToolbar.height + 12,
              child: Center(
                child: _BackToMePill(
                  visible: backToMe,
                  onTap: _locateMe,
                ),
              ),
            ),

            // "N spots nearby": no spot in view on Now / Upcoming. Tap = the Spots layer, fitted.
            if (spotsHint != null)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                left: 16,
                right: 16,
                bottom: toolbarBottom + MapToolbar.height + 12 + (backToMe ? 50 : 0),
                child: Center(
                  child: _SpotsNearbyPill(
                    text: spotsHint,
                    visible: !bottomBusy,
                    light: !_isNight,
                    onTap: () => ref.read(mapModeProvider.notifier).set(MapMode.spots),
                    onDismiss: () => ref.read(spotsHintDismissedProvider.notifier).dismiss(),
                  ),
                ),
              ),

            // Glass toolbar above the tab bar; fades away while the sheet or the card is up.
            Positioned(
              left: 14,
              right: 14,
              bottom: toolbarBottom,
              child: IgnorePointer(
                ignoring: bottomBusy,
                child: AnimatedOpacity(
                  opacity: bottomBusy ? 0 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: AnimatedSlide(
                    offset: bottomBusy ? const Offset(0, 0.3) : Offset.zero,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: GestureDetector(
                      onVerticalDragEnd: (d) {
                        if ((d.primaryVelocity ?? 0) < -200) _openSheet();
                      },
                      child: MapToolbar(mode: mode, light: !_isNight, onOpen: _openSheet),
                    ),
                  ),
                ),
              ),
            ),

            // The picked place's card, where the toolbar was. Slides up on
            // open, follows the finger down, and slides away on close.
            if (_card != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: toolbarBottom,
                child: IgnorePointer(
                  ignoring: !_cardOpen,
                  child: AnimatedOpacity(
                    opacity: _cardOpen ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: AnimatedSlide(
                      offset: _cardOpen ? Offset(0, _cardHeight <= 0 ? 0 : _cardDrag / _cardHeight) : const Offset(0, 0.6),
                      duration: _cardDragging ? Duration.zero : const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      child: GestureDetector(
                        onVerticalDragStart: (_) => setState(() => _cardDragging = true),
                        onVerticalDragUpdate: (d) => setState(() => _cardDrag = math.max(0, _cardDrag + d.delta.dy)),
                        onVerticalDragEnd: _onCardDragEnd,
                        child: NotificationListener<SizeChangedLayoutNotification>(
                          onNotification: (_) {
                            WidgetsBinding.instance.addPostFrameCallback((_) => _onCardResized());
                            return true;
                          },
                          child: SizeChangedLayoutNotifier(
                            child: MapPalette(
                              light: !_isNight,
                              child: PlacePreviewCard(key: _cardKey, place: _card!, onClose: _closeCard),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            MapPalette(light: !_isNight, child: MapSheet(controller: _sheet, onFocus: _focus, onPlace: _openCard)),

            // List view (the toolbar's list button) covers the map, which stays live underneath.
            if (listView) const Positioned.fill(child: MapListView()),
          ],
        ),
      ),
    );
  }
}

/// A teardrop waiting to be drawn: an event, a spot or a partner shop.
/// [pin] renders it at a given pin scale (only if it ends up on its own, not
/// in a bubble; [_MapScreenState._prewarm] also calls it for the sizes next
/// to the current one); [glyphs] are the key rows it stands for.
class _Drop {
  const _Drop({required this.id, required this.at, required this.glyphs, required this.z, required this.pin, required this.onTap, this.event = false, this.alone = false});
  final String id;
  final LatLng at;
  final Set<LegendGlyph> glyphs;
  final int z;
  final Future<MapPin> Function(double pinScale) pin;
  final VoidCallback onTap;
  final bool event;
  /// Never merged into a bubble (the place whose card is open).
  final bool alone;
}

// ------------------------------------------------------------------ widgets ---

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.loading, required this.onChanged});
  final MapMode mode;
  final bool loading;
  final ValueChanged<MapMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      dark: true,
      radius: 21,
      padding: const EdgeInsets.all(3),
      child: SizedBox(
        height: 36,
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in MapMode.values)
            GestureDetector(
              onTap: () => onChanged(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: m == mode ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m == mode && loading)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)),
                      ),
                    Text(
                      m.label,
                      style: TextStyle(
                        color: m == mode ? Colors.black : Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

/// "You're at [title]. Check in now" card; one tap checks in, then it reads
/// "Checked in" for a moment before it goes.
class _NearbyBanner extends StatelessWidget {
  const _NearbyBanner({required this.title, required this.done, required this.busy, required this.onCheckIn, required this.onDismiss});
  final String title;
  final bool done;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xF2151820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (done ? AppColors.success : AppColors.primary).withValues(alpha: 0.6)),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          if (done) ...[
            const Icon(AppIcons.checkCircleFill, color: AppColors.success, size: 22),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(done ? 'Checked in' : 'You\'re at', style: TextStyle(color: done ? AppColors.success : AppColors.mapTextSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (!done) ...[
            busy
                ? const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                : TextButton(onPressed: onCheckIn, child: const Text('Check in now')),
            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(AppIcons.x, color: AppColors.mapTextSecondary, size: 18), onPressed: onDismiss),
          ],
        ],
      ),
    );
  }
}


/// iPhone "approximate location": every pin is rounded to a few km.
class _PreciseBanner extends StatelessWidget {
  const _PreciseBanner({required this.onTurnOn});
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      dark: true,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        children: [
          const Icon(AppIcons.warning, color: AppColors.warnColor, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Location is approximate', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          TextButton(onPressed: onTurnOn, style: TextButton.styleFrom(visualDensity: VisualDensity.compact), child: const Text('Turn on precise')),
        ],
      ),
    );
  }
}

/// Floating red pill: "Back to me". Slides in when I am off-screen or the
/// camera is more than 150 m away, and goes once the map is centred again.
class _BackToMePill extends StatelessWidget {
  const _BackToMePill({required this.visible, required this.onTap});
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.6),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: PressScale(
            child: Material(
              color: AppColors.brand,
              shape: const StadiumBorder(),
              elevation: 8,
              shadowColor: Colors.black54,
              child: InkWell(
                onTap: onTap,
                customBorder: const StadiumBorder(),
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(14, 10, 18, 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.navigationArrow, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Back to me', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small pill above the toolbar: "3 spots nearby · closest ...". Tap to see
/// them on the Spots layer; the cross hides it for the session.
class _SpotsNearbyPill extends StatelessWidget {
  const _SpotsNearbyPill({required this.text, required this.visible, required this.light, required this.onTap, required this.onDismiss});
  final String text;
  final bool visible;
  final bool light;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final fg = light ? AppColors.ink : Colors.white;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Material(
          color: light ? Colors.white : AppColors.mapSurface,
          shape: const StadiumBorder(),
          elevation: 6,
          shadowColor: Colors.black45,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 2, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.mapPin, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: 'Hide',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDismiss,
                    icon: Icon(AppIcons.x, size: 16, color: fg.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap, this.onLongPress, this.active = false, this.light = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool active;
  static const double size = 46;
  /// White button on the day map.
  final bool light;

  @override
  Widget build(BuildContext context) {
    if (active) {
      return Tooltip(
        message: tooltip,
        child: PressScale(
          child: Material(
            color: AppColors.brand,
            shape: const CircleBorder(),
            elevation: 6,
            shadowColor: Colors.black54,
            child: InkWell(onTap: onTap, onLongPress: onLongPress, customBorder: const CircleBorder(), child: SizedBox(width: size, height: size, child: Icon(icon, color: Colors.white, size: 22))),
          ),
        ),
      );
    }
    return Tooltip(
      message: tooltip,
      child: PressScale(
        child: GlassPanel(
          circle: true,
          dark: !light,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              customBorder: const CircleBorder(),
              child: SizedBox(width: size, height: size, child: Icon(icon, color: light ? AppColors.ink : Colors.white, size: 22)),
            ),
          ),
        ),
      ),
    );
  }
}
