import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart' show CupertinoDatePickerMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/geo.dart';
import '../../../core/widgets/pin_picker_screen.dart';
import '../../../core/widgets/place_search_field.dart';
import '../../../core/widgets/wheel_picker.dart';
import '../../map/application/map_providers.dart';
import '../../social/application/community_providers.dart';
import '../../vendors/application/vendors_providers.dart';
import '../application/create_event_controller.dart';
import '../domain/event.dart';

/// One form, two flavours:
/// * `session` = a TT session anyone can plan (title, when, where, who sees
///   it). No type, no cover. Shows as a feather flag on the map.
/// * otherwise an event hosted by a club (`clubId`) or a partner (`vendorId`).
class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key, this.clubId, this.vendorId, this.session = false});
  final String? clubId;
  final String? vendorId;
  final bool session;

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _title = TextEditingController();
  final _venue = TextEditingController();
  final _description = TextEditingController();
  late EventType _type = widget.session ? EventType.tt : EventType.meet;
  late DateTime _startsAt;
  late bool _friendsOnly = widget.session;
  XFile? _cover;
  LatLng? _pin;
  String? _address;
  GoogleMapController? _map;
  String? _mapStyle;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    if (widget.session) {
      // TT sessions: tonight 9 pm (or in an hour if it's already late).
      final tonight = DateTime(now.year, now.month, now.day, 21);
      _startsAt = tonight.isAfter(now.add(const Duration(minutes: 30))) ? tonight : now.add(const Duration(hours: 1));
      _startsAt = DateTime(_startsAt.year, _startsAt.month, _startsAt.day, _startsAt.hour, _startsAt.minute - _startsAt.minute % 5);
    } else {
      // Events: next Saturday, 8:00 PM.
      var days = (DateTime.saturday - now.weekday) % 7;
      if (days == 0 && now.hour >= 20) days = 7;
      final sat = DateTime(now.year, now.month, now.day).add(Duration(days: days));
      _startsAt = DateTime(sat.year, sat.month, sat.day, 20);
    }
    rootBundle.loadString('assets/map_style_dark.json').then((s) {
      if (mounted) setState(() => _mapStyle = s);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _venue.dispose();
    _description.dispose();
    _map?.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickCover() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AppIcons.images),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(AppIcons.camera),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            if (_cover != null)
              ListTile(
                leading: const Icon(AppIcons.trash, color: AppColors.danger),
                title: const Text('Remove photo', style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _cover = null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final f = await pickCoverImage(source);
      if (f != null) setState(() => _cover = f);
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showWheelPicker(
      context,
      initial: _startsAt.isBefore(now) ? now : _startsAt,
      mode: CupertinoDatePickerMode.date,
      min: DateTime(now.year, now.month, now.day),
      max: now.add(const Duration(days: 365)),
      title: 'Which day?',
    );
    if (d == null) return;
    setState(() => _startsAt = DateTime(d.year, d.month, d.day, _startsAt.hour, _startsAt.minute));
  }

  Future<void> _pickTime() async {
    // The wheel rounds to 5-minute steps; feed it a rounded start so it lands on a row.
    final rounded = DateTime(_startsAt.year, _startsAt.month, _startsAt.day, _startsAt.hour, _startsAt.minute - _startsAt.minute % 5);
    final t = await showWheelPicker(context, initial: rounded, mode: CupertinoDatePickerMode.time, title: 'What time?');
    if (t == null) return;
    setState(() => _startsAt = DateTime(_startsAt.year, _startsAt.month, _startsAt.day, t.hour, t.minute));
  }

  Future<void> _useMyLocation() async {
    final loc = ref.read(userLocationProvider).value ?? await ref.read(userLocationProvider.future);
    if (loc == null) {
      _snack('Location is off. Pan the map to the venue instead.');
      return;
    }
    _map?.animateCamera(CameraUpdate.newLatLngZoom(loc, 15));
  }

  Future<void> _expandMap() async {
    final r = await pickPinFullScreen(context, start: _pin ?? (ref.read(userLocationProvider).value ?? kualaLumpur));
    if (r == null || !mounted) return;
    setState(() {
      _pin = r.latLng;
      if (r.name != null) _address = null; // picked by search inside the picker: name only
    });
    if (r.name != null && r.name!.isNotEmpty) _venue.text = r.name!;
    _map?.animateCamera(CameraUpdate.newLatLngZoom(r.latLng, 16));
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final id = await ref.read(createEventControllerProvider.notifier).submit(
          title: _title.text,
          description: _description.text,
          type: _type,
          startsAt: _startsAt,
          venueName: _venue.text,
          location: _pin,
          cover: _cover,
          clubId: widget.clubId,
          vendorId: widget.vendorId,
          friendsOnly: _friendsOnly,
          address: _address,
        );
    if (id != null && mounted) {
      context.pushReplacement(Routes.event(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(createEventControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) _snack(friendlyError(next.error!));
    });
    final busy = ref.watch(createEventControllerProvider).isLoading;
    final start = ref.watch(userLocationProvider).value ?? kualaLumpur;
    final club = widget.clubId == null ? null : ref.watch(clubProvider(widget.clubId!)).value;
    final vendor = widget.vendorId == null ? null : ref.watch(myVendorProvider).value;
    final session = widget.session;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: busy ? null : () => context.pop()),
        title: Text(session ? 'Plan a TT session' : 'New event'),
        actions: [
          busy
              ? const Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : TextButton(onPressed: _submit, child: const Text('Publish')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (!session) _CoverPicker(file: _cover, onTap: busy ? null : _pickCover),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (session)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
                      child: const Row(
                        children: [
                          Icon(AppIcons.coffee, size: 20),
                          SizedBox(width: 10),
                          Expanded(child: Text('A TT session is casual: pick a mamak, a time, and who should see it. It shows as a flag on the map.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4))),
                        ],
                      ),
                    ),
                  if (club != null) ...[
                    _HostingAs(name: club.name),
                    const SizedBox(height: 14),
                  ],
                  if (vendor != null) ...[
                    _HostingAs(name: vendor.name),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: _title,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: session ? 'Call it something' : 'What\'s the event?', hintText: session ? 'e.g. Friday teh tarik' : 'e.g. Sunway Night Meet', counterText: ''),
                  ),
                  if (!session) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final t in EventType.pickable)
                          ChoiceChip(
                            avatar: ArtIcon(t.art, size: 20),
                            label: Text(t.label),
                            selected: t == _type,
                            showCheckmark: false,
                            onSelected: busy ? null : (_) => setState(() => _type = t),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  const _Label('WHEN'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _TapField(icon: AppIcons.calendarBlank, text: formatDate(_startsAt), onTap: busy ? null : _pickDate),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TapField(icon: AppIcons.clock, text: formatTime(_startsAt), onTap: busy ? null : _pickTime),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _Label('WHERE'),
                  const SizedBox(height: 8),
                  PlaceSearchField(
                    enabled: !busy,
                    near: (start.latitude, start.longitude),
                    hint: 'Search a place or address',
                    onPicked: (d) {
                      final target = LatLng(d.lat, d.lng);
                      setState(() {
                        _pin = target;
                        _address = d.address;
                      });
                      _venue.text = d.name;
                      _map?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
                    },
                  ),
                  const SizedBox(height: 10),
                  _PinMap(
                    start: start,
                    style: _mapStyle,
                    hasPin: _pin != null,
                    onCreated: (c) => _map = c,
                    onIdle: (target) => setState(() {
                      if (_pin != null && (target.latitude - _pin!.latitude).abs() + (target.longitude - _pin!.longitude).abs() > 0.0005) _address = null;
                      _pin = target;
                    }),
                    onMyLocation: busy ? null : _useMyLocation,
                    onExpand: busy ? null : _expandMap,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _venue,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Venue name',
                      hintText: 'e.g. Sunway Pyramid Open Carpark',
                      counterText: '',
                      prefixIcon: Icon(AppIcons.mapPin),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _Label('WHO CAN SEE IT'),
                  const SizedBox(height: 8),
                  _Audience(
                    friendsOnly: _friendsOnly,
                    clubName: club?.name,
                    onChanged: busy ? null : (v) => setState(() => _friendsOnly = v),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _description,
                    maxLength: 2000,
                    minLines: 2,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Details (optional)',
                      hintText: 'Parking, what to bring, who it\'s for…',
                      alignLabelWithHint: true,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    session
                        ? 'Keep it legal and friendly. No street racing.'
                        : 'By publishing you confirm this is a legal, public gathering. No street racing.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two big options, one tap. Friends (default) or everyone on TT Spot.
class _Audience extends StatelessWidget {
  const _Audience({required this.friendsOnly, required this.onChanged, this.clubName});
  final bool friendsOnly;
  final String? clubName;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option({required bool value, required IconData icon, required String title, required String subtitle}) {
      final on = friendsOnly == value;
      return Expanded(
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: on ? AppColors.ink : AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: on ? AppColors.ink : AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: on ? Colors.white : AppColors.textPrimary),
                const SizedBox(height: 8),
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 11.5, height: 1.3, color: on ? Colors.white70 : AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(
          value: true,
          icon: AppIcons.users,
          title: 'Friends',
          subtitle: clubName == null ? 'Your friends and people who join.' : 'Your friends and $clubName members.',
        ),
        const SizedBox(width: 10),
        option(value: false, icon: AppIcons.globe, title: 'Everyone', subtitle: 'Shows on the map for all of TT Spot.'),
      ],
    );
  }
}

class _HostingAs extends StatelessWidget {
  const _HostingAs({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          children: [
            const Icon(AppIcons.shieldCheck, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Hosting as $name', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
          ],
        ),
      );
}

// ---------------------------------------------------------------- pieces ---

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary),
      );
}

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({required this.file, required this.onTap});
  final XFile? file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: file == null
            ? const ColoredBox(
                color: AppColors.surfaceGray,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(AppIcons.cameraPlus, size: 32, color: AppColors.textSecondary),
                    SizedBox(height: 8),
                    Text('Add a cover photo', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(file!.path), fit: BoxFit.cover),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: const Text('Change', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TapField extends StatelessWidget {
  const _TapField({required this.icon, required this.text, required this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
          ],
        ),
      ),
    );
  }
}

/// Map with a fixed centre pin: pan the map, the pin stays put, the venue
/// is wherever the pin ends up when the map stops moving.
class _PinMap extends StatelessWidget {
  const _PinMap({
    required this.start,
    required this.style,
    required this.hasPin,
    required this.onCreated,
    required this.onIdle,
    required this.onMyLocation,
    required this.onExpand,
  });

  final LatLng start;
  final String? style;
  final bool hasPin;
  final void Function(GoogleMapController) onCreated;
  final void Function(LatLng) onIdle;
  final VoidCallback? onMyLocation;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 220,
        child: _PinMapBody(start: start, style: style, hasPin: hasPin, onCreated: onCreated, onIdle: onIdle, onMyLocation: onMyLocation, onExpand: onExpand),
      ),
    );
  }
}

class _PinMapBody extends StatefulWidget {
  const _PinMapBody({
    required this.start,
    required this.style,
    required this.hasPin,
    required this.onCreated,
    required this.onIdle,
    required this.onMyLocation,
    required this.onExpand,
  });

  final LatLng start;
  final String? style;
  final bool hasPin;
  final void Function(GoogleMapController) onCreated;
  final void Function(LatLng) onIdle;
  final VoidCallback? onMyLocation;
  final VoidCallback? onExpand;

  @override
  State<_PinMapBody> createState() => _PinMapBodyState();
}

class _PinMapBodyState extends State<_PinMapBody> {
  LatLng? _target;

  @override
  void initState() {
    super.initState();
    // Pin starts at the initial centre so an un-panned map is still a valid location.
    _target = widget.start;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onIdle(widget.start);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: widget.start, zoom: 13.5),
          style: widget.style,
          onMapCreated: widget.onCreated,
          onCameraMove: (pos) => _target = pos.target,
          onCameraIdle: () {
            if (_target != null) widget.onIdle(_target!);
          },
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)},
        ),
        // Fixed centre pin (tip sits on the map centre)
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
            child: Text(
              widget.hasPin ? 'Drag to adjust · expand for a big map' : 'Drag the map to the meet spot',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        Positioned(
          right: 10,
          top: 10,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              onTap: widget.onExpand,
              customBorder: const CircleBorder(),
              child: const SizedBox(width: 40, height: 40, child: Icon(AppIcons.arrowsOut, size: 20, color: AppColors.textPrimary)),
            ),
          ),
        ),
        Positioned(
          right: 10,
          bottom: 10,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              onTap: widget.onMyLocation,
              customBorder: const CircleBorder(),
              child: const SizedBox(width: 40, height: 40, child: Icon(AppIcons.gpsFix, size: 20, color: AppColors.textPrimary)),
            ),
          ),
        ),
      ],
    );
  }
}
