import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/geo.dart';
import '../../events/application/event_providers.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/my_events_screen.dart';
import '../../friends/application/friends_providers.dart';
import '../../friends/domain/friend.dart';
import '../../social/domain/club.dart';
import '../../social/domain/post.dart';
import '../../social/presentation/story_viewer_screen.dart';
import '../application/map_providers.dart';
import 'widgets/event_marker_bitmap.dart';
import 'widgets/map_pins.dart';
import 'widgets/map_sheet.dart';
import 'widgets/tt_now_sheet.dart';

/// Home. One dark map, three time layers: Now (friends, live meets, moments),
/// Upcoming (meets on the calendar) and Before (places with history).
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  GoogleMapController? _map;
  String? _style;
  EventMarkerFactory? _eventMarkers;
  MapPinFactory? _pins;
  Set<Marker> _markerSet = const {};
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
    rootBundle.loadString('assets/map_style_dark.json').then((s) {
      if (mounted) setState(() => _style = s);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(locationPublisherProvider.notifier).start());
  }

  @override
  void dispose() {
    _idleDebounce?.cancel();
    _eventMarkers?.dispose();
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
      if (!mounted) return;
      ref.read(mapViewportProvider.notifier).set(bounds);
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
  EventMarkerFactory get _eventFactory =>
      _eventMarkers ??= EventMarkerFactory(devicePixelRatio: MediaQuery.devicePixelRatioOf(context));

  Future<void> _rebuild() async {
    final generation = ++_generation;
    final mode = ref.read(mapModeProvider);
    final built = <Marker>{};

    Future<bool> stale() async => generation != _generation || !mounted;

    switch (mode) {
      case MapMode.now:
        final now = DateTime.now();
        for (final e in ref.read(liveEventsProvider).value ?? const <Event>[]) {
          final bmp = await _eventFactory.forEvent(e, now: now, label: e.checkinCount > 0 ? 'LIVE · ${e.checkinCount} here' : 'LIVE');
          if (await stale()) return;
          built.add(Marker(
            markerId: MarkerId('event:${e.id}'),
            position: e.latLng,
            icon: bmp.descriptor,
            anchor: bmp.anchor,
            zIndexInt: 3,
            consumeTapEvents: true,
            onTap: () => context.push(Routes.event(e.id)),
          ));
        }
        for (final m in ref.read(liveMomentsProvider).value ?? const <Story>[]) {
          final at = m.latLng;
          if (at == null) continue;
          final pin = await _pinFactory.moment(key: m.id, imageUrl: m.photoUrl);
          if (await stale()) return;
          built.add(Marker(
            markerId: MarkerId('moment:${m.id}'),
            position: at,
            icon: pin.descriptor,
            anchor: pin.anchor,
            zIndexInt: 1,
            consumeTapEvents: true,
            onTap: () => _openMoment(m),
          ));
        }
        for (final f in ref.read(friendPinsProvider).value ?? const <FriendPin>[]) {
          final name = f.user.displayName ?? f.user.username ?? '';
          final pin = await _pinFactory.avatar(
            key: f.user.id,
            imageUrl: f.user.avatarUrl,
            name: name,
            ring: f.isFresh ? AppColors.primary : const Color(0xFF6B7280),
            dimmed: !f.isFresh,
          );
          if (await stale()) return;
          built.add(Marker(
            markerId: MarkerId('friend:${f.user.id}'),
            position: f.latLng,
            icon: pin.descriptor,
            anchor: pin.anchor,
            zIndexInt: 4,
            consumeTapEvents: true,
            onTap: () => context.push(Routes.profile(f.user.id)),
          ));
        }
      case MapMode.upcoming:
        final now = DateTime.now();
        for (final e in ref.read(mapEventsProvider).value ?? const <Event>[]) {
          final bmp = await _eventFactory.forEvent(e, now: now);
          if (await stale()) return;
          built.add(Marker(
            markerId: MarkerId('event:${e.id}'),
            position: e.latLng,
            icon: bmp.descriptor,
            anchor: bmp.anchor,
            consumeTapEvents: true,
            onTap: () => context.push(Routes.event(e.id)),
          ));
        }
      case MapMode.spots:
        for (final p in ref.read(spotsProvider).value ?? const <Place>[]) {
          final pin = await _pinFactory.spot(
            key: p.id,
            imageUrl: p.coverUrl,
            art: p.kindArt,
            title: p.name,
            count: '${p.totalCheckins} ✓',
            recommended: p.recommended,
          );
          if (await stale()) return;
          built.add(Marker(
            markerId: MarkerId('place:${p.id}'),
            position: p.latLng,
            icon: pin.descriptor,
            anchor: pin.anchor,
            zIndexInt: p.recommended ? 2 : 1,
            consumeTapEvents: true,
            onTap: () => context.push(Routes.place(p.id)),
          ));
        }
    }
    if (mounted) setState(() => _markerSet = built);
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

  Future<void> _toggleGhost() async {
    final ghost = ref.read(myLocationProvider).value?.ghost ?? false;
    try {
      await ref.read(locationPublisherProvider.notifier).setGhost(!ghost);
      _snack(!ghost ? 'Ghost mode on. Friends can\'t see you.' : 'You\'re back on the map.');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _checkInNearby(({String id, String title}) meet) async {
    try {
      await ref.read(eventActionsProvider).checkIn(meet.id);
      ref.read(nearbyMeetProvider.notifier).dismiss();
      ref.invalidate(liveEventsProvider);
      _snack('Checked in. Have a good one.');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  // --------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    ref.listen(mapModeProvider, (_, _) => _rebuild());
    ref.listen(mapEventsProvider, (_, _) => _rebuild());
    ref.listen(liveEventsProvider, (_, _) => _rebuild());
    ref.listen(liveMomentsProvider, (_, _) => _rebuild());
    ref.listen(friendPinsProvider, (_, _) => _rebuild());
    ref.listen(spotsProvider, (_, _) => _rebuild());
    ref.listen(userLocationProvider, (_, _) => _moveToUserIfKnown());

    final mode = ref.watch(mapModeProvider);
    final hasLocation = ref.watch(userLocationProvider).value != null;
    final ghost = ref.watch(myLocationProvider).value?.ghost ?? false;
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
      value: _mapOverlay,
      child: Scaffold(
        backgroundColor: AppColors.mapBg,
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: const CameraPosition(target: kualaLumpur, zoom: 11.3),
              style: _style,
              markers: _markerSet,
              onMapCreated: _onMapCreated,
              onCameraIdle: _onCameraIdle,
              myLocationEnabled: hasLocation,
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

            // Right-side round buttons
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, right: 14),
                  child: Column(
                    children: [
                      _RoundButton(
                        icon: AppIcons.list,
                        tooltip: 'List view',
                        onTap: () => ref.read(mapListViewProvider.notifier).set(true),
                      ),
                      const SizedBox(height: 10),
                      _RoundButton(
                        icon: ghost ? AppIcons.eyeSlash : AppIcons.eye,
                        tooltip: ghost ? 'Ghost mode on' : 'Friends can see you',
                        active: ghost,
                        onTap: _toggleGhost,
                      ),
                      const SizedBox(height: 10),
                      _RoundButton(
                        icon: hasLocation ? AppIcons.gpsFix : AppIcons.crosshair,
                        tooltip: 'My location',
                        onTap: _locateMe,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Action row: moment · TT now · new meet
            Positioned(
              left: 16,
              right: 16,
              bottom: sheetPeek + 12,
              child: Row(
                children: [
                  _RoundButton(
                    icon: AppIcons.camera,
                    tooltip: 'Add a moment',
                    size: 52,
                    onTap: () => context.push(Routes.createMoment(eventId: ref.read(myLocationProvider).value?.eventId)),
                  ),
                  const Spacer(),
                  _TtNowButton(onTap: () => showTtNowSheet(context)),
                  const Spacer(),
                  _RoundButton(
                    icon: AppIcons.plus,
                    tooltip: 'Plan a meet',
                    size: 52,
                    onTap: () => context.push(Routes.createEvent),
                  ),
                ],
              ),
            ),

            MapSheet(controller: _sheet, onFocus: _focus),
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
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xF2151820),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
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

class _TtNowButton extends StatelessWidget {
  const _TtNowButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warnColor,
      shape: const StadiumBorder(),
      elevation: 8,
      shadowColor: Colors.black54,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ArtIcon(AppArt.coffee, size: 26),
              SizedBox(width: 8),
              Text('TT now', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap, this.active = false, this.size = 46});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? Colors.white : const Color(0xF2151820),
        shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
        elevation: 6,
        shadowColor: Colors.black54,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: active ? Colors.black : Colors.white, size: size > 46 ? 24 : 22),
          ),
        ),
      ),
    );
  }
}
