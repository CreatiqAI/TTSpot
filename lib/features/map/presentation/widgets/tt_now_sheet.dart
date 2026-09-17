import 'package:flutter/cupertino.dart' show CupertinoTimerPicker, CupertinoTimerPickerMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/places/places_service.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../../core/utils/geo.dart';
import '../../../../core/widgets/pin_picker_screen.dart';
import '../../../../core/widgets/place_search_field.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/profile.dart';
import '../../../events/application/event_providers.dart';
import '../../../friends/application/friends_providers.dart';
import '../../../social/application/chat_providers.dart';
import '../../application/map_providers.dart';

/// The place picked in the sheet last time, so closing and reopening (and the
/// map pill) keep it while you're still near it.
class TtPlaceNotifier extends Notifier<PlaceDetails?> {
  @override
  PlaceDetails? build() => null;
  void set(PlaceDetails? p) => state = p;
}

final ttPlaceProvider = NotifierProvider<TtPlaceNotifier, PlaceDetails?>(TtPlaceNotifier.new);

/// "TT now": where (prefilled), how long (1 h default), who (all friends
/// ticked). Start makes the meet and drops an invite card in each ticked
/// friend's chat.
Future<void> showTtNowSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _TtNowSheet(),
  );
}

class _TtNowSheet extends ConsumerStatefulWidget {
  const _TtNowSheet();

  @override
  ConsumerState<_TtNowSheet> createState() => _TtNowSheetState();
}

class _TtNowSheetState extends ConsumerState<_TtNowSheet> {
  final _venue = TextEditingController();
  PlaceDetails? _picked;
  bool _changing = false;
  int _minutes = 60;
  Set<String>? _invited; // null until friends load, then all ticked
  bool _busy = false;
  bool _prefilled = false;
  bool _locating = false;
  List<PlaceDetails> _around = const [];

  @override
  void dispose() {
    _venue.dispose();
    super.dispose();
  }

  /// One tap: GPS fix, then the closest named places to pick from.
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
      if (lat == null || lng == null) throw const AppException('Turn on location first.');
      final list = await ref.read(placesServiceProvider).nearby(lat, lng);
      if (!mounted) return;
      if (list.isEmpty) {
        // nothing named here: pin the raw spot
        setState(() {
          _picked = PlaceDetails(placeId: '', name: 'My spot', address: '', lat: lat, lng: lng);
          _venue.text = 'My spot';
          _changing = false;
          _around = const [];
        });
        ref.read(ttPlaceProvider.notifier).set(_picked);
      } else {
        setState(() {
          _around = list;
          _picked = list.first;
          _venue.text = list.first.name;
          _changing = false;
        });
        ref.read(ttPlaceProvider.notifier).set(_picked);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pinOnMap() async {
    final here = ref.read(userLocationProvider).value;
    final r = await pickPinFullScreen(context, start: _picked != null ? LatLng(_picked!.lat, _picked!.lng) : (here ?? kualaLumpur));
    if (r == null || !mounted) return;
    setState(() {
      _picked = PlaceDetails(placeId: '', name: r.name ?? 'Pinned spot', address: '', lat: r.latLng.latitude, lng: r.latLng.longitude);
      _venue.text = r.name ?? 'Pinned spot';
      _changing = false;
      _around = const [];
    });
    ref.read(ttPlaceProvider.notifier).set(_picked);
  }

  Future<void> _customDuration() async {
    var d = Duration(minutes: _minutes);
    final ok = await showModalBottomSheet<bool>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(children: [
                const Expanded(child: Text('How long?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Done')),
              ]),
            ),
            SizedBox(
              height: 200,
              child: CupertinoTimerPicker(mode: CupertinoTimerPickerMode.hm, initialTimerDuration: d, minuteInterval: 15, onTimerDurationChanged: (v) => d = v),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (ok == true && d.inMinutes >= 15) setState(() => _minutes = d.inMinutes.clamp(15, 480));
  }

  Future<void> _go(List<Profile> friends) async {
    setState(() => _busy = true);
    try {
      double? lat = _picked?.lat;
      double? lng = _picked?.lng;
      if (lat == null || lng == null) {
        Position? pos;
        try {
          pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
        } catch (_) {
          pos = null;
        }
        final fallback = ref.read(userLocationProvider).value;
        lat = pos?.latitude ?? fallback?.latitude;
        lng = pos?.longitude ?? fallback?.longitude;
      }
      if (lat == null || lng == null) throw const AppException('Turn on location so friends know where to come.');

      final invitees = (_invited ?? friends.map((f) => f.id).toSet()).toList();
      final id = await ref.read(eventActionsProvider).ttNow(lat: lat, lng: lng, venue: _venue.text, minutes: _minutes, invitees: invitees, address: _picked?.address);
      ref.invalidate(liveEventsProvider);
      // one invite card in each friend's chat
      final chat = ref.read(chatActionsProvider);
      for (final uid in invitees) {
        try {
          final conv = await chat.openDm(uid);
          await chat.attach(conv, eventId: id);
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      context.push(Routes.event(id));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  String get _durationLabel => _minutes % 60 == 0 ? '${_minutes ~/ 60} h' : (_minutes > 60 ? '${_minutes ~/ 60} h ${_minutes % 60} min' : '$_minutes min');

  @override
  Widget build(BuildContext context) {
    final my = ref.watch(myLocationProvider).value;
    final here = ref.watch(userLocationProvider).value;
    final friends = ref.watch(friendsProvider).value ?? const <Profile>[];
    final pins = ref.watch(friendPinsProvider).value ?? const [];
    final liveIds = {for (final p in pins) if (p.isFresh) p.user.id};
    // Auto-fill with the nearest named place + street address from GPS.
    final nearby = here == null ? null : ref.watch(nearbyPlacesProvider(placeKey(here.latitude, here.longitude))).value;
    final remembered = ref.read(ttPlaceProvider);
    if (!_prefilled && remembered != null && here != null && distanceKm(here, LatLng(remembered.lat, remembered.lng)) < 1.0) {
      _picked = remembered;
      _venue.text = remembered.name;
      _around = nearby ?? const [];
      _prefilled = true;
    } else if (!_prefilled && nearby != null && nearby.isNotEmpty) {
      _around = nearby;
      _picked = nearby.first;
      _venue.text = nearby.first.name;
      _prefilled = true;
    } else if (!_prefilled && my?.placeName != null && here == null) {
      _venue.text = my!.placeName!;
      _prefilled = true;
    }
    final invited = _invited ?? friends.map((f) => f.id).toSet();
    final preset = const [60, 120, 180];

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TT now', style: TextStyle(fontFamily: AppFonts.display, fontSize: 28, fontWeight: FontWeight.w700, height: 1)),
            const SizedBox(height: 12),
            // ---- where
            if (_changing || _venue.text.trim().isEmpty)
              PlaceSearchField(
                controller: _venue,
                autofocus: _changing,
                enabled: !_busy,
                near: here == null ? null : (here.latitude, here.longitude),
                hint: 'Where are you?',
                icon: AppIcons.mapPin,
                onChanged: (_) {
                  if (_picked != null) setState(() => _picked = null);
                },
                onPicked: (d) {
                  setState(() {
                    _picked = d;
                    _venue.text = d.name;
                    _changing = false;
                  });
                  ref.read(ttPlaceProvider.notifier).set(d);
                },
              )
            else
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Row(
                  children: [
                    const Icon(AppIcons.mapPin, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_venue.text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          if (_picked?.address != null) Text(_picked!.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    TextButton(onPressed: _busy ? null : () => setState(() => _changing = true), child: const Text('Change')),
                  ],
                ),
              ),
            if (_changing || _venue.text.trim().isEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy || _locating ? null : _useMyLocation,
                      icon: _locating ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.gpsFix, size: 16),
                      label: const Text('Use my location'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pinOnMap,
                      icon: const Icon(AppIcons.mapPinPlus, size: 16),
                      label: const Text('Pin on map'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 10)),
                    ),
                  ),
                ],
              ),
            ],
            if (_around.length > 1) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('ALSO NEAR YOU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
                  const Spacer(),
                  Text('swipe for more', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 2),
                  Icon(AppIcons.caretRight, size: 12, color: AppColors.textMuted),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 34,
                child: ShaderMask(
                  shaderCallback: (r) => const LinearGradient(colors: [Colors.white, Colors.white, Colors.transparent], stops: [0, 0.85, 1]).createShader(r),
                  blendMode: BlendMode.dstIn,
                  child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final p in _around)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          selected: _picked?.placeId == p.placeId,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            setState(() {
                              _picked = p;
                              _venue.text = p.name;
                            });
                            ref.read(ttPlaceProvider.notifier).set(p);
                          },
                        ),
                      ),
                    const SizedBox(width: 40),
                  ],
                ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // ---- how long
            Text('HOW LONG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final m in preset) ...[
                  Expanded(child: _Chip(label: '${m ~/ 60} h', on: _minutes == m, onTap: _busy ? null : () => setState(() => _minutes = m))),
                  const SizedBox(width: 6),
                ],
                Expanded(child: _Chip(label: preset.contains(_minutes) ? 'Custom' : _durationLabel, on: !preset.contains(_minutes), onTap: _busy ? null : _customDuration)),
              ],
            ),
            const SizedBox(height: 16),
            // ---- who
            Row(
              children: [
                Text('INVITE · ${invited.length} of ${friends.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
                const Spacer(),
                TextButton(
                  onPressed: _busy || friends.isEmpty ? null : () => setState(() => _invited = invited.length == friends.length ? <String>{} : friends.map((f) => f.id).toSet()),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                  child: Text(invited.length == friends.length ? 'Clear' : 'Select all'),
                ),
              ],
            ),
            if (friends.isEmpty)
              Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No friends yet. Your TT still shows on the map for people you add later.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in friends)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: UserAvatar(url: f.avatarUrl, name: f.displayName ?? f.username, size: 36),
                        title: Text(f.displayName ?? '@${f.username}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        subtitle: Text(liveIds.contains(f.id) ? 'On the map now' : '@${f.username ?? ''}', style: TextStyle(fontSize: 11.5, color: liveIds.contains(f.id) ? AppColors.success : AppColors.textSecondary)),
                        trailing: Icon(invited.contains(f.id) ? AppIcons.checkCircleFill : AppIcons.checkCircle, color: invited.contains(f.id) ? AppColors.brand : AppColors.textMuted),
                        onTap: _busy ? null : () => setState(() => _invited = invited.contains(f.id) ? ({...invited}..remove(f.id)) : {...invited, f.id}),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : () => _go(friends),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(invited.isEmpty ? 'Start TT' : 'Start TT · invite ${invited.length} friend${invited.length == 1 ? '' : 's'}'),
            ),
            const SizedBox(height: 6),
            Text('Ends by itself in $_durationLabel, or when you end it. Friends see it on the map.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: on ? AppColors.textPrimary : AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
          child: Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: on ? AppColors.onInk : AppColors.textPrimary)),
        ),
      );
}
