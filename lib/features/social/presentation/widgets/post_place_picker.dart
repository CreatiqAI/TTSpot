import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/geo/latlng.dart';
import '../../../../core/location/live_position.dart';
import '../../../../core/location/location_gate.dart';
import '../../../../core/places/place_autocomplete.dart';
import '../../../../core/places/places_service.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/geo.dart';
import '../../../map/application/map_providers.dart';
import '../../data/community_repository.dart';
import '../../domain/club.dart';
import '../../domain/post_place.dart';

/// Suggestions for TT Spots carry this prefix instead of a Google place id.
const _spotPrefix = 'spot:';

/// "Where is this?" on the new-post screen:
///   * a search box with live suggestions as you type (TT Spots first, then
///     addresses and places from the `places` Edge Function), and a pick
///     sets the place with its coordinates;
///   * "Use my location": one tap fills the place you are at (or "Near
///     <area>"), and the places around you come up as chips;
///   * the place you picked shows as a chip with an X.
/// Location is only asked for when "Use my location" is tapped; without it
/// the search still works.
class PostPlacePicker extends ConsumerStatefulWidget {
  const PostPlacePicker({super.key, required this.value, required this.onChanged, this.enabled = true});
  final PostPlace? value;
  final ValueChanged<PostPlace?> onChanged;
  final bool enabled;

  @override
  ConsumerState<PostPlacePicker> createState() => _PostPlacePickerState();
}

class _PostPlacePickerState extends ConsumerState<PostPlacePicker> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  late final _auto = PlaceAutocomplete(_suggest)..addListener(_rebuild);

  /// The spots in the last answer, by id, so a pick needs no second lookup.
  final _spots = <String, Place>{};
  List<PostPlace> _around = const [];
  LatLng? _here;
  bool _locating = false;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    // Only what is already known: opening the post screen never prompts.
    _here = ref.read(livePositionProvider)?.latLng;
    final here = _here;
    if (here != null) unawaited(_spotsAround(here));
  }

  @override
  void dispose() {
    _auto.dispose();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _snack(String msg, {SnackBarAction? action}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), action: action));

  /// TT Spots near a fix I already have, as chips. Our own data: free.
  Future<void> _spotsAround(LatLng here) async {
    try {
      final spots = await ref.read(communityRepositoryProvider).nearestSpots(lat: here.latitude, lng: here.longitude, limit: 5);
      if (!mounted || _around.isNotEmpty) return;
      setState(() => _around = placesAround(lat: here.latitude, lng: here.longitude, nearby: const [], spots: spots));
    } catch (_) {}
  }

  /// One search: matching TT Spots and the address suggestions together.
  Future<List<PlaceSuggestion>> _suggest(String q, String token) async {
    final here = _here;
    final spotsF = ref.read(communityRepositoryProvider).searchSpots(q).then<List<Place>>((v) => v, onError: (_) => const <Place>[]);
    List<PlaceSuggestion>? google;
    Object? failure;
    try {
      google = await ref.read(placesServiceProvider).autocomplete(q, lat: here?.latitude, lng: here?.longitude, sessionToken: token);
    } catch (e) {
      failure = e;
    }
    final spots = await spotsF;
    if (google == null && spots.isEmpty) throw failure ?? const AppException('Search failed');
    for (final s in spots) {
      _spots[s.id] = s;
    }
    final spotNames = spots.map((s) => s.name.toLowerCase()).toSet();
    return [
      for (final s in spots) PlaceSuggestion(placeId: '$_spotPrefix${s.id}', main: s.name, secondary: here == null ? 'TT Spot' : 'TT Spot · ${formatDistance(distanceKm(here, s.latLng))}'),
      // The spot already says it; don't list the same name twice.
      for (final g in google ?? const <PlaceSuggestion>[])
        if (!spotNames.contains(g.main.toLowerCase())) g,
    ];
  }

  Future<void> _pick(PlaceSuggestion s) async {
    final token = _auto.pick();
    _focus.unfocus();
    if (s.placeId.startsWith(_spotPrefix)) {
      _auto.finish();
      final spot = _spots[s.placeId.substring(_spotPrefix.length)];
      _ctrl.clear();
      if (spot != null) widget.onChanged(PostPlace.spot(spot));
      return;
    }
    setState(() {
      _resolving = true;
      _ctrl.text = s.main;
    });
    try {
      final d = await ref.read(placesServiceProvider).details(s.placeId, sessionToken: token);
      if (!mounted) return;
      _ctrl.clear();
      // The suggestion's name is the one people typed towards; keep it when details has none.
      widget.onChanged(PostPlace.details(PlaceDetails(placeId: d.placeId, name: d.name.trim().isEmpty ? s.main : d.name, address: d.address.isEmpty ? s.secondary : d.address, lat: d.lat, lng: d.lng)));
    } catch (_) {
      if (mounted) _snack("Couldn't load that place. Try another.");
    } finally {
      _auto.finish();
      if (mounted) setState(() => _resolving = false);
    }
  }

  /// Where I am, asking for what is missing the way the map does: location
  /// services, then the permission prompt, then Settings when it was denied
  /// for good. Null (with a note) when there is no way to know.
  Future<LatLng?> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) _snack('Location is off. Turn it on, or search for the place.', action: SnackBarAction(label: 'Turn on', onPressed: () => Geolocator.openLocationSettings()));
        return null;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        if (mounted) _snack('No location access. You can still search for the place.', action: SnackBarAction(label: 'Settings', onPressed: () => Geolocator.openAppSettings()));
        return null;
      }
      ref.invalidate(locationGrantedProvider);
    } catch (_) {
      return null;
    }
    final fix = await ref.read(livePositionProvider.notifier).refresh();
    if (fix != null) return fix;
    ref.invalidate(userLocationProvider);
    return ref.read(userLocationProvider.future);
  }

  Future<void> _useMyLocation() async {
    FocusScope.of(context).unfocus();
    setState(() => _locating = true);
    try {
      final here = await _locate();
      if (here == null || !mounted) return;
      _here = here;
      final key = placeKey(here.latitude, here.longitude);
      final results = await Future.wait<Object>([
        ref.read(nearbyPlacesProvider(key).future).catchError((Object e) {
          ref.invalidate(nearbyPlacesProvider(key)); // don't keep the failure for this spot
          throw e;
        }),
        ref.read(communityRepositoryProvider).nearestSpots(lat: here.latitude, lng: here.longitude, limit: 5).catchError((Object _) => <Place>[]),
      ]);
      if (!mounted) return;
      final nearby = results[0] as List<PlaceDetails>;
      final spots = results[1] as List<Place>;
      final at = placeAt(lat: here.latitude, lng: here.longitude, nearby: nearby, spots: spots);
      setState(() => _around = placesAround(lat: here.latitude, lng: here.longitude, nearby: nearby, spots: spots));
      if (at != null) {
        widget.onChanged(at);
      } else {
        _snack('Nothing named around here. Search for the place instead.');
      }
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picked = widget.value;
    final busy = _auto.loading || _resolving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (picked != null)
          _PlaceChip(place: picked, onRemove: widget.enabled ? () => widget.onChanged(null) : null)
        else ...[
          TextField(
            controller: _ctrl,
            focusNode: _focus,
            enabled: widget.enabled,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.words,
            onChanged: (v) {
              _auto.onChanged(v);
              setState(() {}); // the clear button
            },
            decoration: InputDecoration(
              hintText: 'Search a place or address',
              prefixIcon: const Icon(AppIcons.magnifyingGlass),
              suffixIcon: busy
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(AppIcons.x, size: 18),
                          onPressed: () {
                            _ctrl.clear();
                            _auto.clear();
                          },
                        ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _auto.items.isEmpty
                ? (_auto.failed && _auto.query.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Text("Couldn't search right now. Check your connection.", style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      )
                    : const SizedBox(width: double.infinity))
                : Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < _auto.items.length; i++) ...[
                          if (i > 0) Divider(height: 1, indent: 52, color: AppColors.divider),
                          _SuggestionTile(suggestion: _auto.items[i], isSpot: _auto.items[i].placeId.startsWith(_spotPrefix), onTap: () => _pick(_auto.items[i])),
                        ],
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: !widget.enabled || _locating ? null : _useMyLocation,
              icon: _locating ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.gpsFix, size: 16),
              label: Text(_locating ? 'Finding you…' : 'Use my location'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
            ),
          ),
        ],
        if (_around.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(picked == null ? 'NEAR YOU' : 'OR NEARBY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          // Sized by its chips (no fixed height), so large text never clips them.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in _around)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: p.isSpot ? Icon(AppIcons.starFill, size: 14, color: picked == p ? AppColors.onInk : AppColors.brand) : null,
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(p.distanceM == null ? p.name : '${p.name} · ${formatDistance(p.distanceM! / 1000)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      selected: picked == p,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: widget.enabled ? (_) => widget.onChanged(picked == p ? null : p) : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.suggestion, required this.isSpot, required this.onTap});
  final PlaceSuggestion suggestion;
  final bool isSpot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(isSpot ? AppIcons.starFill : AppIcons.mapPin, size: 20, color: isSpot ? AppColors.brand : AppColors.textSecondary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(suggestion.main, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (suggestion.secondary.isNotEmpty)
                    Text(suggestion.secondary, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The place on the post: pin, name, short address, X to take it off.
class _PlaceChip extends StatelessWidget {
  const _PlaceChip({required this.place, required this.onRemove});
  final PostPlace place;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final sub = place.isSpot ? 'TT Spot' : (place.address.isEmpty ? null : shortAddress(place.address));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(place.isSpot ? AppIcons.starFill : AppIcons.mapPinFill, size: 18, color: place.isSpot ? AppColors.brand : AppColors.textPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if (sub != null && sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          IconButton(tooltip: 'Remove place', icon: const Icon(AppIcons.x, size: 18), onPressed: onRemove),
        ],
      ),
    );
  }
}
