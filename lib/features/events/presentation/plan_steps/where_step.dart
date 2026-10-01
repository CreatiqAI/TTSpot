import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/geo/latlng.dart';
import '../../../../core/map/app_map.dart';
import '../../../../core/places/places_service.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/geo.dart';
import '../../../../core/widgets/pin_picker_screen.dart';
import '../../../../core/widgets/place_search_field.dart';
import '../../../map/application/map_providers.dart';
import '../../application/plan_draft.dart';
import 'wizard_parts.dart';

/// Step "Where?": search a place, or one big "Use my location" that drops
/// the pin where you stand and names the place you're at; nearby places as
/// chips; a small map to nudge the pin.
class WhereStep extends ConsumerStatefulWidget {
  const WhereStep({super.key, required this.draft, required this.showMap, this.nearby});
  final PlanDraft draft;
  /// False in widget tests (the map is a platform view).
  final bool showMap;
  /// Places near me, remembered across steps by the wizard.
  final ValueNotifier<List<PlaceDetails>>? nearby;

  @override
  ConsumerState<WhereStep> createState() => _WhereStepState();
}

class _WhereStepState extends ConsumerState<WhereStep> {
  final _map = AppMapController();
  bool _locating = false;

  PlanDraft get d => widget.draft;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  void _place(LatLng at, {required String name, String? address}) {
    d.setPlace(at, name: name, address: address);
    _map.animateTo(at, zoom: 16);
  }

  /// GPS fix → pin there → the place I'm at (within 80 m), else "Near …".
  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
      } catch (_) {}
      final fallback = ref.read(userLocationProvider).value;
      final lat = pos?.latitude ?? fallback?.latitude;
      final lng = pos?.longitude ?? fallback?.longitude;
      if (lat == null || lng == null) throw const AppException('Turn on location first, or search the place.');
      final here = LatLng(lat, lng);
      // The pin drops right away; the name follows when the lookup returns.
      _place(here, name: d.venue.isEmpty ? 'My spot' : d.venue);
      List<PlaceDetails> list = const [];
      try {
        list = [...await ref.read(placesServiceProvider).nearby(lat, lng)]..sort((a, b) => (a.distanceM ?? 1 << 20).compareTo(b.distanceM ?? 1 << 20));
      } catch (_) {}
      if (!mounted) return;
      widget.nearby?.value = list;
      final at = list.where((p) => p.isHere).firstOrNull;
      final near = list.where((p) => (p.distanceM ?? 1 << 20) <= 300).firstOrNull;
      if (at != null) {
        d.setPlace(here, name: at.name, address: at.address);
      } else if (near != null) {
        d.setPlace(here, name: 'Near ${near.name}', address: near.address);
      } else {
        d.setPlace(here, name: 'My spot');
      }
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _expandMap(LatLng start) async {
    final r = await pickPinFullScreen(context, start: d.pin ?? start);
    if (r == null || !mounted) return;
    if (r.name != null && r.name!.isNotEmpty) {
      _place(r.latLng, name: r.name!);
    } else {
      d.nudgePin(r.latLng);
      _map.animateTo(r.latLng, zoom: 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    final here = ref.watch(userLocationProvider).value;
    final start = d.pin ?? here ?? kualaLumpur;
    // Places around me (cached per ~10 m, shared with the TT pill).
    final auto = here == null ? null : ref.watch(nearbyPlacesProvider(placeKey(here.latitude, here.longitude))).value;
    final remembered = widget.nearby?.value ?? const <PlaceDetails>[];
    final chips = (remembered.isNotEmpty ? remembered : (auto ?? const <PlaceDetails>[])).take(8).toList();

    return ListenableBuilder(
      listenable: d,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          StepHeading('Where?', subtitle: d.session ? 'The mamak, carpark or spot you\'ll be at.' : 'Where should everyone meet?'),
          PlaceSearchField(
            near: (start.latitude, start.longitude),
            hint: 'Search a place or address',
            onPicked: (p) => _place(LatLng(p.lat, p.lng), name: p.name, address: p.address),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton.tonalIcon(
              key: const Key('plan-use-my-location'),
              onPressed: _locating ? null : _useMyLocation,
              icon: _locating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.gpsFix, size: 20),
              label: Text(_locating ? 'Finding you…' : 'Use my location', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand.withValues(alpha: 0.10),
                foregroundColor: AppColors.brand,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              ),
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 16),
            const SectionLabel('NEAR YOU'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in chips)
                  ChoiceChip(
                    label: Text(p.distanceM == null ? p.name : '${p.name} · ${formatDistance(p.distanceM! / 1000)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    selected: d.venue == p.name && d.pin != null && (d.pin!.latitude - p.lat).abs() < 0.0002,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _place(LatLng(p.lat, p.lng), name: p.name, address: p.address),
                  ),
              ],
            ),
          ],
          if (d.pin != null) ...[
            const SizedBox(height: 18),
            const SectionLabel('THE SPOT'),
            if (widget.showMap)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: SizedBox(
                  height: 200,
                  child: _NudgeMap(
                    start: d.pin!,
                    controller: _map,
                    onIdle: d.nudgePin,
                    onExpand: () => _expandMap(start),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('plan-venue'),
              controller: d.venueCtrl,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name of the place', hintText: 'e.g. Sunway Pyramid open carpark', counterText: '', prefixIcon: Icon(AppIcons.mapPin)),
            ),
            if (d.address != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(d.address!, style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
              ),
          ],
        ],
      ),
    );
  }
}

/// Map with a fixed centre pin: drag the map, the pin stays put; wherever it
/// sits when the map stops is the spot.
class _NudgeMap extends StatefulWidget {
  const _NudgeMap({required this.start, required this.controller, required this.onIdle, required this.onExpand});
  final LatLng start;
  final AppMapController controller;
  final ValueChanged<LatLng> onIdle;
  final VoidCallback onExpand;

  @override
  State<_NudgeMap> createState() => _NudgeMapState();
}

class _NudgeMapState extends State<_NudgeMap> {
  LatLng? _target;
  bool _moved = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AppMap(
          controller: widget.controller,
          initialTarget: widget.start,
          initialZoom: 16,
          night: AppColors.dark,
          onCameraMoveStarted: () => _moved = true,
          onCameraMove: (c) => _target = c,
          onCameraIdle: () {
            // Only a drag moves the spot; the first settle is just the map loading.
            if (_moved && _target != null) widget.onIdle(_target!);
          },
          gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)},
        ),
        const IgnorePointer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 34),
              child: Icon(AppIcons.mapPinFill, size: 40, color: AppColors.accent),
            ),
          ),
        ),
        Positioned(
          left: 10,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(8)),
            child: const Text('Drag the map to nudge the pin', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
        Positioned(
          right: 10,
          top: 10,
          child: Material(
            color: AppColors.surface,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              onTap: widget.onExpand,
              customBorder: const CircleBorder(),
              child: SizedBox(width: 40, height: 40, child: Icon(AppIcons.arrowsOut, size: 20, color: AppColors.textPrimary)),
            ),
          ),
        ),
      ],
    );
  }
}
