import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart' show Geolocator, LocationAccuracyStatus;
import '../../../core/geo/latlng.dart';
import '../../../core/map/app_map.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/location/live_position.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_tab_bar.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/geo.dart';
import '../../events/application/event_providers.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/my_events_screen.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../profile/application/profile_providers.dart';
import '../../friends/application/friends_providers.dart';
import '../../friends/domain/friend.dart';
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
import 'widgets/car_marker.dart';
import 'widgets/visibility_sheet.dart';
import '../../settings/application/settings_providers.dart';

/// Home. One dark map, three time layers: Now (friends, live meets, moments),
/// Upcoming (meets on the calendar) and Before (places with history).
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with TickerProviderStateMixin {
  final _map = AppMapController();
  GlyphMarkerFactory? _glyphs;
  MapPinFactory? _pins;
  CarMarkerFactory? _cars;
  List<AppMarker> _markerSet = const [];
  /// What kinds of pin are on the map right now; feeds the key.
  Set<LegendGlyph> _present = const {};
  List<AppCircle> _circles = const [];
  // Radar: one pulse every 5 s on live meets (and a static ring for nearby mode).
  late final AnimationController _radar = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..addListener(_paintCircles);
  Timer? _radarTimer;
  // The pulse around me: one soft ring every 2 s, ~14 frames each, so the
  // polygon layer is not rebuilt at 60 fps.
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..addListener(_onPulse);
  Timer? _pulseTimer;
  int _pulseStep = -1;
  Timer? _idleDebounce;
  int _generation = 0;
  bool _movedToUser = false;
  /// Where the map opens. Resolved before the map is built (a quick read of
  /// the phone's last fix) so the first frame is already "here", not KL.
  ({LatLng target, double zoom})? _initialCamera;
  /// The camera has drifted off me: I am off-screen or > 150 m from the centre.
  bool _awayFromMe = false;
  final _sheet = DraggableScrollableController();
  /// The glass toolbar hides while the sheet is up.
  bool _sheetOpen = false;

  static const _mapOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

  @override
  void initState() {
    super.initState();
    _radarTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && ref.read(mapModeProvider) == MapMode.now) _radar.forward(from: 0);
    });
    _pulseTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _map.isReady && _lastHere != null && !_pulse.isAnimating) _pulse.forward(from: 0);
    });
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

  /// Zoom tiers, Waze-style. 0 = far: everything is a small colour-coded dot
  /// (events and TT red, spots grey, top spots black), no people. 1 = mid:
  /// shapes at 85 %, people as dots, moments. 2 = close: full-size shapes
  /// with name chips, cars with faces.
  static const _midZoom = 13.0;
  static const _closeZoom = 14.5;
  /// Below this nobody else is drawn (I always am): the map is a region, not a street.
  static const _peopleZoom = 11.0;
  int _tier = 0;
  bool get _far => _tier == 0;
  bool get _close => _tier == 2;

  /// Pins grow and shrink with the zoom, not in three fixed jumps. Quantised
  /// to 0.05 so a small pan never re-renders every marker. 0.4 at zoom 10 or
  /// less, ~0.8 at 13, 1.0 around 14.7, 1.3 from zoom 17 up.
  double _zoom = 12;
  double get _glyphScale {
    final t = ((_zoom - 10) / 7).clamp(0.0, 1.0);
    return ((0.4 + t * 0.9) / 0.05).round() * 0.05;
  }
  /// Last position we drew myself at, so a location refresh never blinks me away.
  LatLng? _lastHere;
  bool get _showPeople => _zoom >= _peopleZoom;

  void _onPulse() {
    final step = (_pulse.value * 14).floor();
    if (step == _pulseStep) return;
    _pulseStep = step;
    _paintCircles();
  }

  /// Metres per logical pixel at the current zoom, so ground-anchored rings
  /// can be sized in screen terms (the pulse should look the same at any zoom).
  double get _metresPerPx {
    final lat = (_lastHere ?? kualaLumpur).latitude * math.pi / 180;
    return 156543.03392 * math.cos(lat) / math.pow(2, _zoom);
  }

  void _paintCircles() {
    if (!mounted) return;
    final t = _radar.value;
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
    // The pulse: ~36 px of ground around me, whatever the zoom.
    if (here != null && _pulse.isAnimating) {
      circles.add(pulseCircle(at: here, radiusM: (36 * _metresPerPx).clamp(8.0, 5000.0), t: _pulse.value));
    }
    if (ref.read(mapModeProvider) == MapMode.now) {
      if (_radar.isAnimating) {
        for (final e in ref.read(liveEventsProvider).value ?? const <Event>[]) {
          circles.add(radarCircle(id: 'radar:${e.id}', at: e.latLng, radiusM: 350, t: t));
        }
      }
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
    setState(() => _circles = circles);
  }

  @override
  void dispose() {
    _radarTimer?.cancel();
    _radar.dispose();
    _pulseTimer?.cancel();
    _pulse.dispose();
    _idleDebounce?.cancel();
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

  void _onMapReady() => _moveToUserIfKnown();

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

  void _onCameraIdle() {
    _idleDebounce?.cancel();
    _idleDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!_map.isReady || !mounted) return;
      final bounds = await _map.visibleRegion();
      final zoom = await _map.zoom();
      if (!mounted || bounds == null) return;
      _hadFirstIdle = true;
      ref.read(mapViewportProvider.notifier).set(bounds);
      final tier = _tierFor(zoom);
      final before = (_tier, _glyphScale, _showPeople);
      _zoom = zoom;
      _tier = tier;
      if (before != (_tier, _glyphScale, _showPeople)) _rebuild();
      // Off-screen counts as "away" even when the centre is within 150 m (very close zooms).
      final here = _lastHere;
      if (here != null) _setAway(!bounds.contains(here) || distanceKm(bounds.center, here) > 0.15);
    });
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
    if (away != _awayFromMe && mounted) setState(() => _awayFromMe = away);
  }

  Future<void> _locateMe() async {
    // Glide to what we have now, then again if a fresh fix moves us.
    final known = ref.read(livePositionProvider)?.latLng ?? ref.read(userLocationProvider).value;
    if (known != null) _map.animateTo(known, zoom: 15);
    var loc = await ref.read(livePositionProvider.notifier).refresh();
    if (loc == null) {
      ref.invalidate(userLocationProvider);
      loc = await ref.read(userLocationProvider.future);
    }
    if (!mounted) return;
    if (loc == null) {
      _snack('Location is off. Showing Kuala Lumpur instead.');
      return;
    }
    if (known == null || distanceKm(known, loc) > 0.01) _map.animateTo(loc, zoom: 15);
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

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------- markers ---

  MapPinFactory get _pinFactory => _pins ??= MapPinFactory(devicePixelRatio: MediaQuery.devicePixelRatioOf(context));
  GlyphMarkerFactory get _glyphFactory => _glyphs ??= GlyphMarkerFactory(devicePixelRatio: MediaQuery.devicePixelRatioOf(context));

  /// Balloon for events, feather flag for TT sessions. Dots when far out,
  /// label only when close.
  Future<MapPin> _eventPin(Event e, {String? sub}) {
    // Official clubs get the gold badge; partner events the ink badge. Both keep their colour when far out.
    final official = e.isOfficialClubEvent;
    final partner = e.vendorId != null;
    final color = official ? kGold : (partner ? kInk : kEventRed);
    if (_far) return _glyphFactory.dot(key: e.id, color: color, r: 4.5 * _glyphScale);
    final label = _close ? (e.isInstant ? e.venueName : e.title) : null;
    if (e.type == EventType.tt || e.isInstant) {
      return _glyphFactory.flag(key: e.id, label: label, sub: _close ? sub : null, scale: _glyphScale, color: color);
    }
    return _glyphFactory.balloon(key: e.id, label: label, sub: _close ? sub : null, scale: _glyphScale, color: color, glyph: official ? AppIcons.crown : (partner ? AppIcons.storefront : null));
  }
  CarMarkerFactory get _carFactory => _cars ??= CarMarkerFactory(devicePixelRatio: MediaQuery.devicePixelRatioOf(context), pins: _pinFactory);

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

  Future<void> _rebuild() async {
    final generation = ++_generation;
    final mode = ref.read(mapModeProvider);
    final built = <AppMarker>[];
    final present = <LegendGlyph>{};

    Future<bool> stale() async => generation != _generation || !mounted;
    void noteEvent(Event e) => present.add(e.type == EventType.tt || e.isInstant
        ? LegendGlyph.flag
        : e.isOfficialClubEvent
            ? LegendGlyph.officialEvent
            : e.vendorId != null
                ? LegendGlyph.partnerEvent
                : LegendGlyph.balloon);

    switch (mode) {
      case MapMode.now:
        for (final e in ref.read(liveEventsProvider).value ?? const <Event>[]) {
          final bmp = await _eventPin(e, sub: e.checkinCount > 0 ? 'LIVE · ${e.checkinCount} here' : 'LIVE');
          if (await stale()) return;
          noteEvent(e);
          built.add(AppMarker(
            id: 'event:${e.id}',
            position: e.latLng,
            image: bmp.bytes, size: bmp.size,
            anchor: bmp.anchor,
            zIndex: 3,
            onTap: () => _openAt(e.latLng, () => context.push(Routes.event(e.id))),
          ));
        }
        for (final m in _far ? const <Story>[] : (ref.read(liveMomentsProvider).value ?? const <Story>[])) {
          final at = m.latLng;
          if (at == null) continue;
          final pin = await _pinFactory.moment(key: m.id, imageUrl: m.photoUrl, scale: _glyphScale);
          if (await stale()) return;
          present.add(LegendGlyph.moment);
          built.add(AppMarker(
            id: 'moment:${m.id}',
            position: at,
            image: pin.bytes, size: pin.size,
            anchor: pin.anchor,
            zIndex: 1,
            onTap: () => _openAt(at, () => _openMoment(m)),
          ));
        }
        await _addPartners(built, stale, present);
        await _addPeople(built, stale, present);
      case MapMode.upcoming:
        final now = DateTime.now();
        for (final e in ref.read(mapEventsProvider).value ?? const <Event>[]) {
          final bmp = await _eventPin(e, sub: relativeShort(e.startsAt, now: now));
          if (await stale()) return;
          noteEvent(e);
          built.add(AppMarker(
            id: 'event:${e.id}',
            position: e.latLng,
            image: bmp.bytes, size: bmp.size,
            anchor: bmp.anchor,
            onTap: () => _openAt(e.latLng, () => context.push(Routes.event(e.id))),
          ));
        }
        await _addPartners(built, stale, present);
      case MapMode.spots:
        for (final p in ref.read(spotsProvider).value ?? const <Place>[]) {
          // One language for places: kind colour + silhouette, a red-ringed
          // dot far out for top spots, bigger and named up close.
          final kind = spotKindOf(p.kind);
          final pin = p.isPartner
              ? await _partnerPin(p)
              : _far
                  ? await _glyphFactory.dot(key: p.id, color: spotKindColor(kind), r: (p.recommended ? 5.5 : 4.5) * _glyphScale, ring: p.recommended ? kEventRed : Colors.white)
                  : await _glyphFactory.spot(
                      key: p.id,
                      recommended: p.recommended,
                      kind: kind,
                      label: _close ? p.name : null,
                      sub: _close && p.totalCheckins > 0 ? '${p.totalCheckins} ✓' : null,
                      scale: _close ? _glyphScale * 1.2 : _glyphScale,
                    );
          if (await stale()) return;
          if (p.isPartner) {
            present.add(LegendGlyph.partner);
          } else {
            present.add(legendGlyphForSpot(kind));
            if (p.recommended) present.add(LegendGlyph.topSpot);
          }
          built.add(AppMarker(
            id: 'place:${p.id}',
            position: p.latLng,
            image: pin.bytes, size: pin.size,
            anchor: pin.anchor,
            zIndex: p.isPartner ? 3 : (p.recommended ? 2 : 1),
            onTap: () => _openAt(p.latLng, () => context.push(p.isPartner ? Routes.partner(p.vendorId!) : Routes.place(p.id))),
          ));
        }
    }
    if (mode != MapMode.now) await _addPeople(built, stale, present, onlyMe: true);
    if (mounted) {
      setState(() {
        _markerSet = built;
        _present = present;
      });
    }
  }

  /// A partner's shop: red storefront square far out, the logo signboard
  /// mid-way, and the signboard with the shop's name up close.
  Future<MapPin> _partnerPin(Place p) => _far
      ? _pinFactory.partnerMini(key: p.id, scale: _glyphScale)
      : _pinFactory.partner(key: p.id, logoUrl: p.vendorLogo, scale: _close ? _glyphScale * 1.1 : _glyphScale, name: _close ? (p.vendorName ?? p.name) : null);

  /// Partner shops show on every layer: logo pin when zoomed in, red dot far out.
  Future<void> _addPartners(List<AppMarker> built, Future<bool> Function() stale, Set<LegendGlyph> present) async {
    for (final p in (ref.read(spotsProvider).value ?? const <Place>[]).where((p) => p.isPartner)) {
      present.add(LegendGlyph.partner);
      final pin = await _partnerPin(p);
      if (await stale()) return;
      built.add(AppMarker(
        id: 'place:${p.id}',
        position: p.latLng,
        image: pin.bytes, size: pin.size,
        anchor: pin.anchor,
        zIndex: 2,
        onTap: () => _openAt(p.latLng, () => context.push(Routes.partner(p.vendorId!))),
      ));
    }
  }

  /// Friends, clubmates, nearby strangers and me. Cars when zoomed in, dots
  /// when zoomed out. Colour = relationship, or the colour I gave a friend.
  Future<void> _addPeople(List<AppMarker> built, Future<bool> Function() stale, Set<LegendGlyph> present, {bool onlyMe = false}) async {
    final tags = ref.read(friendTagsProvider).value ?? const <String, String>{};
    if (!onlyMe && !_far && _showPeople) {
      for (final f in ref.read(friendPinsProvider).value ?? const <FriendPin>[]) {
        final stranger = f.isStranger;
        final relation = stranger ? kRelationStranger : (kTagColors[tags[f.user.id]] ?? (f.viaClub ? kRelationClub : kRelationFriend));
        final name = stranger ? '@${f.user.username ?? ''}' : (f.user.displayName ?? f.user.username ?? '');
        final photo = f.carPhoto;
        final pin = !_close
            ? await _carFactory.dot(key: f.user.id, color: relation, scale: _glyphScale)
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
                    faceUrl: f.user.avatarUrl,
                    showFace: !stranger,
                    dim: stranger || !f.isFresh,
                    relation: relation,
                  );
        if (await stale()) return;
        present.add(stranger ? LegendGlyph.nearby : (f.viaClub ? LegendGlyph.club : LegendGlyph.friend));
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
      present.add(LegendGlyph.me);
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
    if (here == null || me == null || _markerSet.isEmpty) return;
    _lastHere = here;
    if (_markerSet.indexWhere((m) => m.id == 'me') < 0) {
      _rebuild();
      return;
    }
    final pin = await _mePin(me);
    if (!mounted) return;
    final idx = _markerSet.indexWhere((m) => m.id == 'me');
    if (idx < 0) return;
    setState(() => _markerSet = [..._markerSet]..[idx] = AppMarker(id: 'me', position: here, image: pin.bytes, size: pin.size, anchor: pin.anchor, zIndex: _meZ));
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
    setState(() => _nearbyBusy = true);
    try {
      await ref.read(eventActionsProvider).checkIn(meet.id);
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
    ref.listen(mapModeProvider, (_, _) {
      _rebuild();
      _paintCircles();
    });
    ref.listen(mapEventsProvider, (_, _) => _rebuild());
    ref.listen(liveEventsProvider, (_, _) => _rebuild());
    ref.listen(liveMomentsProvider, (_, _) => _rebuild());
    ref.listen(friendPinsProvider, (_, _) => _rebuild());
    ref.listen(spotsProvider, (_, _) => _rebuild());
    ref.listen(userLocationProvider, (prev, next) {
      _moveToUserIfKnown();
      // First fix (or lost/regained): everything re-sorts. Afterwards just move my pin.
      if (prev?.value == null || next.value == null) {
        _rebuild();
      } else {
        _updateMe();
      }
      _paintCircles();
    });
    ref.listen(livePositionProvider, (_, _) => _paintCircles());
    ref.listen(myLocationProvider, (_, _) => _paintCircles());
    ref.listen(friendTagsProvider, (_, _) => _rebuild());
    MapPalette.defaultLight = !_isNight;

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
    final reduced = ref.watch(locationPrecisionProvider).value == LocationAccuracyStatus.reduced;

    if (listView) {
      return MyEventsScreen(embedded: true, onShowMap: () => ref.read(mapListViewProvider.notifier).set(false));
    }

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
              onCameraIdle: _onCameraIdle,
              onCameraMove: _onCameraMove,
              // Tap the map while the sheet is up: close it.
              onTap: (_) {
                if (_sheetOpen) _sheet.animateTo(MapSheet.closed, duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
              },
            ),

            // Mode switch + nearby banner
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(70, 12, 70, 0),
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
            ),

            // Left-side key: what the shapes mean on this layer
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 200),
                  // Below the mode switch, and below the "you're at a meet" banner when it shows.
                  padding: EdgeInsets.only(top: 66 + (nearby == null ? 0 : 60) + (reduced ? 54 : 0), left: 12),
                  child: MapLegend(mode: mode, light: !_isNight, present: _present),
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
                  visible: hasLocation && _awayFromMe && !_sheetOpen,
                  onTap: _locateMe,
                ),
              ),
            ),

            // Glass toolbar above the tab bar; fades away while the sheet is up.
            Positioned(
              left: 14,
              right: 14,
              bottom: toolbarBottom,
              child: IgnorePointer(
                ignoring: _sheetOpen,
                child: AnimatedOpacity(
                  opacity: _sheetOpen ? 0 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: AnimatedSlide(
                    offset: _sheetOpen ? const Offset(0, 0.3) : Offset.zero,
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

            MapPalette(light: !_isNight, child: MapSheet(controller: _sheet, onFocus: _focus)),
          ],
        ),
      ),
    );
  }
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
