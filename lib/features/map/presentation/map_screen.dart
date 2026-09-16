import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
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
import 'widgets/map_legend.dart';
import 'widgets/map_pins.dart';
import 'widgets/map_sheet.dart';
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

class _MapScreenState extends ConsumerState<MapScreen> with SingleTickerProviderStateMixin {
  GoogleMapController? _map;
  String? _style;
  String? _styleDark;
  String? _styleLight;
  GlyphMarkerFactory? _glyphs;
  MapPinFactory? _pins;
  CarMarkerFactory? _cars;
  Set<Marker> _markerSet = const {};
  Set<Circle> _circles = const {};
  // Radar: one pulse every 5 s on live meets (and a static ring for nearby mode).
  late final AnimationController _radar = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..addListener(_paintCircles);
  Timer? _radarTimer;
  Timer? _idleDebounce;
  int _generation = 0;
  bool _movedToUser = false;
  final _sheet = DraggableScrollableController();

  static const _mapOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

  @override
  void initState() {
    super.initState();
    Future.wait([rootBundle.loadString('assets/map_style_dark.json'), rootBundle.loadString('assets/map_style_light.json')]).then((s) {
      _styleDark = s[0];
      _styleLight = s[1];
      if (mounted) setState(() => _style = _isNight ? _styleDark : _styleLight);
    });
    _radarTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && ref.read(mapModeProvider) == MapMode.now) _radar.forward(from: 0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(locationPublisherProvider.notifier).start());
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

  void _paintCircles() {
    if (!mounted) return;
    final t = _radar.value;
    final circles = <Circle>{};
    if (ref.read(mapModeProvider) == MapMode.now) {
      if (_radar.isAnimating) {
        for (final e in ref.read(liveEventsProvider).value ?? const <Event>[]) {
          circles.add(radarCircle(id: 'radar:${e.id}', at: e.latLng, radiusM: 350, t: t));
        }
      }
      final my = ref.read(myLocationProvider).value;
      final here = ref.read(userLocationProvider).value;
      if (my != null && my.shareMode == 'nearby' && here != null) {
        circles.add(Circle(
          circleId: const CircleId('nearby-ring'),
          center: here,
          radius: my.shareRadiusM.toDouble(),
          strokeWidth: 1,
          strokeColor: AppColors.brand.withValues(alpha: 0.55),
          fillColor: AppColors.brand.withValues(alpha: 0.05),
        ));
      }
    }
    setState(() => _circles = circles);
  }

  @override
  void dispose() {
    _radarTimer?.cancel();
    _radar.dispose();
    _idleDebounce?.cancel();
    _glyphs?.dispose();
    _pins?.dispose();
    _sheet.dispose();
    _map?.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- camera ---

  void _onMapCreated(GoogleMapController c) {
    _map = c;
    _moveToUserIfKnown();
  }

  void _moveToUserIfKnown() {
    final loc = ref.read(userLocationProvider).value;
    if (loc != null && !_movedToUser) {
      _movedToUser = true;
      _map?.animateCamera(CameraUpdate.newLatLngZoom(loc, 12));
    }
  }

  void _onCameraIdle() {
    _idleDebounce?.cancel();
    _idleDebounce = Timer(const Duration(milliseconds: 350), () async {
      final map = _map;
      if (map == null || !mounted) return;
      final bounds = await map.getVisibleRegion();
      final zoom = await map.getZoomLevel();
      if (!mounted) return;
      ref.read(mapViewportProvider.notifier).set(bounds);
      final tier = zoom < _midZoom ? 0 : (zoom < _closeZoom ? 1 : 2);
      final before = (_tier, _glyphScale, _showPeople);
      _zoom = zoom;
      _tier = tier;
      if (before != (_tier, _glyphScale, _showPeople)) _rebuild();
    });
  }

  Future<void> _locateMe() async {
    ref.invalidate(userLocationProvider);
    final loc = await ref.read(userLocationProvider.future);
    if (!mounted) return;
    if (loc == null) {
      _snack('Location is off. Showing Kuala Lumpur instead.');
      return;
    }
    _map?.animateCamera(CameraUpdate.newLatLngZoom(loc, 13));
  }

  void _focus(LatLng target, {double zoom = 15}) {
    _map?.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
    _sheet.animateTo(MapSheet.peek, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
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
    if (_far) return _glyphFactory.dot(key: e.id, color: kEventRed, r: 4.5 * _glyphScale);
    final label = _close ? (e.isInstant ? e.venueName : e.title) : null;
    return e.type == EventType.tt || e.isInstant
        ? _glyphFactory.flag(key: e.id, label: label, sub: _close ? sub : null, scale: _glyphScale)
        : _glyphFactory.balloon(key: e.id, label: label, sub: _close ? sub : null, scale: _glyphScale);
  }
  CarMarkerFactory get _carFactory => _cars ??= CarMarkerFactory(devicePixelRatio: MediaQuery.devicePixelRatioOf(context), pins: _pinFactory);

  /// From a zoomed-out view, glide in to the pin first, then open its page.
  /// Up close, open straight away.
  Future<void> _openAt(LatLng at, VoidCallback open) async {
    final map = _map;
    if (map != null && _zoom < 14.5) {
      await map.animateCamera(CameraUpdate.newLatLngZoom(at, 16));
      await Future<void>.delayed(const Duration(milliseconds: 520));
      if (!mounted) return;
    }
    open();
  }

  Future<void> _rebuild() async {
    final generation = ++_generation;
    final mode = ref.read(mapModeProvider);
    final built = <Marker>{};

    Future<bool> stale() async => generation != _generation || !mounted;

    switch (mode) {
      case MapMode.now:
        for (final e in ref.read(liveEventsProvider).value ?? const <Event>[]) {
          final bmp = await _eventPin(e, sub: e.checkinCount > 0 ? 'LIVE · ${e.checkinCount} here' : 'LIVE');
          if (await stale()) return;
          built.add(Marker(
            markerId: MarkerId('event:${e.id}'),
            position: e.latLng,
            icon: bmp.descriptor,
            anchor: bmp.anchor,
            zIndexInt: 3,
            consumeTapEvents: true,
            onTap: () => _openAt(e.latLng, () => context.push(Routes.event(e.id))),
          ));
        }
        for (final m in _far ? const <Story>[] : (ref.read(liveMomentsProvider).value ?? const <Story>[])) {
          final at = m.latLng;
          if (at == null) continue;
          final pin = await _pinFactory.moment(key: m.id, imageUrl: m.photoUrl, scale: _glyphScale);
          if (await stale()) return;
          built.add(Marker(
            markerId: MarkerId('moment:${m.id}'),
            position: at,
            icon: pin.descriptor,
            anchor: pin.anchor,
            zIndexInt: 1,
            consumeTapEvents: true,
            onTap: () => _openAt(at, () => _openMoment(m)),
          ));
        }
        await _addPartners(built, stale);
        await _addPeople(built, stale);
      case MapMode.upcoming:
        final now = DateTime.now();
        for (final e in ref.read(mapEventsProvider).value ?? const <Event>[]) {
          final bmp = await _eventPin(e, sub: relativeShort(e.startsAt, now: now));
          if (await stale()) return;
          built.add(Marker(
            markerId: MarkerId('event:${e.id}'),
            position: e.latLng,
            icon: bmp.descriptor,
            anchor: bmp.anchor,
            consumeTapEvents: true,
            onTap: () => _openAt(e.latLng, () => context.push(Routes.event(e.id))),
          ));
        }
        await _addPartners(built, stale);
      case MapMode.spots:
        for (final p in ref.read(spotsProvider).value ?? const <Place>[]) {
          final pin = _far
              ? (p.isPartner ? await _pinFactory.partnerMini(key: p.id, scale: _glyphScale) : await _glyphFactory.dot(key: p.id, color: p.recommended ? kInk : kSpotGrey, r: 4.5 * _glyphScale))
              : p.isPartner
                  ? await _pinFactory.partner(key: p.id, logoUrl: p.vendorLogo, scale: _glyphScale)
                  : await _glyphFactory.spot(
                      key: p.id,
                      recommended: p.recommended,
                      label: _close ? p.name : null,
                      sub: _close && p.totalCheckins > 0 ? '${p.totalCheckins} ✓' : null,
                      scale: _glyphScale,
                    );
          if (await stale()) return;
          built.add(Marker(
            markerId: MarkerId('place:${p.id}'),
            position: p.latLng,
            icon: pin.descriptor,
            anchor: pin.anchor,
            zIndexInt: p.isPartner ? 3 : (p.recommended ? 2 : 1),
            consumeTapEvents: true,
            onTap: () => _openAt(p.latLng, () => context.push(p.isPartner ? Routes.partner(p.vendorId!) : Routes.place(p.id))),
          ));
        }
    }
    if (mode != MapMode.now) await _addPeople(built, stale, onlyMe: true);
    if (mounted) setState(() => _markerSet = built);
  }

  /// Partner shops show on every layer: logo pin when zoomed in, red dot far out.
  Future<void> _addPartners(Set<Marker> built, Future<bool> Function() stale) async {
    for (final p in (ref.read(spotsProvider).value ?? const <Place>[]).where((p) => p.isPartner)) {
      final pin = _far ? await _pinFactory.partnerMini(key: p.id, scale: _glyphScale) : await _pinFactory.partner(key: p.id, logoUrl: p.vendorLogo, scale: _glyphScale);
      if (await stale()) return;
      built.add(Marker(
        markerId: MarkerId('place:${p.id}'),
        position: p.latLng,
        icon: pin.descriptor,
        anchor: pin.anchor,
        zIndexInt: 2,
        consumeTapEvents: true,
        onTap: () => _openAt(p.latLng, () => context.push(Routes.partner(p.vendorId!))),
      ));
    }
  }

  /// Friends, clubmates, nearby strangers and me. Cars when zoomed in, dots
  /// when zoomed out. Colour = relationship, or the colour I gave a friend.
  Future<void> _addPeople(Set<Marker> built, Future<bool> Function() stale, {bool onlyMe = false}) async {
    final tags = ref.read(friendTagsProvider).value ?? const <String, String>{};
    final showColor = ref.read(settingsProvider).showCarColor;
    if (!onlyMe && !_far && _showPeople) {
      for (final f in ref.read(friendPinsProvider).value ?? const <FriendPin>[]) {
        final stranger = f.isStranger;
        final relation = stranger ? kRelationStranger : (kTagColors[tags[f.user.id]] ?? (f.viaClub ? kRelationClub : kRelationFriend));
        final name = stranger ? '@${f.user.username ?? ''}' : (f.user.displayName ?? f.user.username ?? '');
        final pin = !_close
            ? await _carFactory.dot(key: f.user.id, color: relation, scale: _glyphScale)
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
        built.add(Marker(
          markerId: MarkerId('friend:${f.user.id}'),
          position: f.latLng,
          icon: pin.descriptor,
          anchor: pin.anchor,
          zIndexInt: stranger ? 2 : 4,
          consumeTapEvents: true,
          onTap: () => _openAt(f.latLng, () => context.push(Routes.profile(f.user.id))),
        ));
      }
    }
    final here = ref.read(userLocationProvider).value ?? _lastHere;
    if (here != null) _lastHere = here;
    final me = ref.read(currentUserIdProvider);
    if (here != null && me != null) {
      final myCar = (ref.read(userCarsProvider(me)).value ?? const []).firstOrNull;
      final pin = !_close
          ? await _carFactory.dot(key: 'me', color: kRelationMe, me: true, scale: _glyphScale)
          : await _carFactory.car(key: 'me', colorKey: showColor ? (myCar?.color ?? 'red') : 'red', name: 'Me', status: 'now', showFace: false, me: true);
      if (await stale()) return;
      built.add(Marker(markerId: const MarkerId('me'), position: here, icon: pin.descriptor, anchor: pin.anchor, zIndexInt: 6));
    }
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

  Future<void> _checkInNearby(({String id, String title}) meet) async {
    try {
      await ref.read(eventActionsProvider).checkIn(meet.id);
      ref.read(nearbyMeetProvider.notifier).dismiss();
      ref.invalidate(liveEventsProvider);
      _snack('Checked in. Have a good one.');
    } catch (e) {
      // The meet may have ended or been removed while the banner was up.
      ref.read(nearbyMeetProvider.notifier).dismiss();
      ref.invalidate(liveEventsProvider);
      _snack(friendlyError(e));
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
    ref.listen(userLocationProvider, (_, _) {
      _moveToUserIfKnown();
      _rebuild();
    });
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
    final sheetPeek = MediaQuery.sizeOf(context).height * MapSheet.peek;

    if (listView) {
      return MyEventsScreen(embedded: true, onShowMap: () => ref.read(mapListViewProvider.notifier).set(false));
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _isNight ? _mapOverlay : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.mapBg,
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: const CameraPosition(target: kualaLumpur, zoom: 11.3),
              style: _style,
              markers: _markerSet,
              circles: _circles,
              onMapCreated: _onMapCreated,
              onCameraIdle: _onCameraIdle,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: false,
              padding: EdgeInsets.only(bottom: sheetPeek),
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
                      if (nearby != null) ...[
                        const SizedBox(height: 10),
                        _NearbyBanner(
                          title: nearby.title,
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
                  padding: EdgeInsets.only(top: nearby == null ? 66 : 126, left: 12),
                  child: MapLegend(mode: mode, light: !_isNight),
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
                        tooltip: 'My location',
                        light: !_isNight,
                        onTap: _locateMe,
                      ),
                    ],
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

class _NearbyBanner extends StatelessWidget {
  const _NearbyBanner({required this.title, required this.onCheckIn, required this.onDismiss});
  final String title;
  final VoidCallback onCheckIn;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xF2151820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.6)),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('You\'re at a meet', style: TextStyle(color: AppColors.mapTextSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          TextButton(onPressed: onCheckIn, child: const Text('Check in')),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(AppIcons.x, color: AppColors.mapTextSecondary, size: 18), onPressed: onDismiss),
        ],
      ),
    );
  }
}


class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap, this.active = false, this.light = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
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
            color: AppColors.ink,
            shape: const CircleBorder(),
            elevation: 6,
            shadowColor: Colors.black54,
            child: InkWell(onTap: onTap, customBorder: const CircleBorder(), child: const SizedBox(width: size, height: size, child: Icon(null))),
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
              customBorder: const CircleBorder(),
              child: SizedBox(width: size, height: size, child: Icon(icon, color: light ? AppColors.ink : Colors.white, size: 22)),
            ),
          ),
        ),
      ),
    );
  }
}
