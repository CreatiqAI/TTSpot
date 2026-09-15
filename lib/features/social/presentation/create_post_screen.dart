import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/geo.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/pin_map.dart';
import '../../events/application/my_events_provider.dart';
import '../../events/domain/event.dart';
import '../../map/application/map_providers.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/domain/car.dart';
import '../application/community_providers.dart';
import '../application/social_providers.dart';
import '../data/social_repository.dart';
import '../domain/club.dart';
import '../domain/post.dart';

/// New post / spotted / poll / guide. Instagram "New post" style: X, title, blue Share.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key, required this.kind, this.eventId, this.carId, this.placeId, this.clubId, this.asClub = false, this.vendorId});
  final PostKind kind;
  final String? eventId;
  final String? carId;
  final String? placeId;
  final String? clubId;
  /// Publish under the club's name (owner / admin only).
  final bool asClub;
  /// Posting as a partner business.
  final String? vendorId;

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _photos = <XFile>[];
  final _caption = TextEditingController();
  final _title = TextEditingController();
  final _pollOptions = [TextEditingController(), TextEditingController()];
  final _pollPhotos = <int, XFile>{};
  int _pollDays = 3;
  final _stops = <GuideStop>[];
  LatLng? _pin;
  String? _carId;
  String? _eventId;
  String? _clubId;
  Place? _place;
  bool _busy = false;

  PostKind get _kind => widget.kind;

  @override
  void initState() {
    super.initState();
    _eventId = widget.eventId;
    _carId = widget.carId;
    _clubId = widget.clubId;
    if (widget.placeId != null) {
      ref.read(placeProvider(widget.placeId!).future).then((p) {
        if (mounted && p != null) setState(() => _place = p);
      });
    }
    if (_kind != PostKind.poll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addPhotos());
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _title.dispose();
    for (final c in _pollOptions) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _addPhotos() async {
    final room = 10 - _photos.length;
    if (room <= 0) {
      _snack('Up to 10 photos per post.');
      return;
    }
    final files = await pickPhotos(context, max: room);
    if (files.isNotEmpty) setState(() => _photos.addAll(files));
  }

  Future<double> _aspectOf(XFile f) async {
    try {
      final bytes = await f.readAsBytes();
      final img = await decodeImageFromList(bytes);
      final a = img.width / img.height;
      img.dispose();
      return a.isFinite && a > 0 ? a : 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final me = ref.read(currentUserIdProvider);
    if (me == null) return;

    // Validation per kind
    if (_kind == PostKind.post && _photos.isEmpty && _caption.text.trim().isEmpty) {
      _snack('Add a photo or write something.');
      return;
    }
    if (_kind == PostKind.spotted && _photos.isEmpty) {
      _snack('A spotted needs a photo.');
      return;
    }
    if (_kind == PostKind.poll) {
      if (_title.text.trim().isEmpty) {
        _snack('Ask a question.');
        return;
      }
      if (_pollOptions.where((c) => c.text.trim().isNotEmpty).length < 2) {
        _snack('Give at least two options.');
        return;
      }
    }
    if (_kind == PostKind.guide && _title.text.trim().isEmpty) {
      _snack('Give the guide a title.');
      return;
    }

    setState(() => _busy = true);
    try {
      final repo = ref.read(socialRepositoryProvider);
      final urls = <String>[];
      for (final f in _photos) {
        urls.add(await repo.uploadPhoto(userId: me, bytes: await f.readAsBytes()));
      }
      final aspect = _photos.isEmpty ? 1.0 : await _aspectOf(_photos.first);

      List<PollOption>? options;
      if (_kind == PostKind.poll) {
        options = [];
        for (var i = 0; i < _pollOptions.length; i++) {
          final text = _pollOptions[i].text.trim();
          if (text.isEmpty) continue;
          String? photoUrl;
          final pf = _pollPhotos[i];
          if (pf != null) photoUrl = await repo.uploadPhoto(userId: me, bytes: await pf.readAsBytes(), folder: 'polls');
          options.add(PollOption(text: text, photoUrl: photoUrl));
        }
      }

      final post = await repo.createPost(
        authorId: me,
        kind: _kind,
        title: _kind == PostKind.poll || _kind == PostKind.guide ? _title.text : null,
        caption: _caption.text.trim().isEmpty ? null : _caption.text,
        photoUrls: urls,
        coverAspect: aspect,
        carId: _carId,
        eventId: _eventId,
        placeId: _place?.id,
        clubId: _clubId,
        asClub: widget.asClub && _clubId == widget.clubId,
        vendorId: widget.vendorId,
        asVendor: widget.vendorId != null,
        location: _kind == PostKind.spotted ? _pin : null,
        pollOptions: options,
        pollEndsAt: _kind == PostKind.poll ? DateTime.now().add(Duration(days: _pollDays)) : null,
        guideStops: _kind == PostKind.guide && _stops.isNotEmpty ? _stops : null,
      );
      ref.read(socialActionsProvider).refreshPost(post.id, authorId: me);
      if (_eventId != null) ref.invalidate(postsWhereProvider((column: 'event_id', value: _eventId!)));
      if (widget.vendorId != null) ref.invalidate(postsWhereProvider((column: 'vendor_id', value: widget.vendorId!)));
      if (mounted) context.pushReplacement(Routes.post(post.id));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_kind) {
      PostKind.post => 'New post',
      PostKind.spotted => 'Spotted',
      PostKind.poll => 'New poll',
      PostKind.guide => 'New guide',
    };
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _busy ? null : () => context.pop()),
        title: Text(title),
        actions: [
          _busy
              ? const Padding(padding: EdgeInsets.only(right: 20), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
              : TextButton(onPressed: _submit, child: const Text('Share')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_kind != PostKind.poll) ...[
              _PhotoStrip(photos: _photos, onAdd: _busy ? null : _addPhotos, onRemove: (i) => setState(() => _photos.removeAt(i))),
              const SizedBox(height: 16),
            ],

            if (_kind == PostKind.poll || _kind == PostKind.guide) ...[
              TextField(
                controller: _title,
                maxLength: 100,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _kind == PostKind.poll ? 'Question' : 'Title',
                  hintText: _kind == PostKind.poll ? 'e.g. Which exhaust for the Myvi?' : 'e.g. Top 5 sunrise drives from KL',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (_kind == PostKind.poll) ...[
              const _Label('OPTIONS'),
              const SizedBox(height: 8),
              for (var i = 0; i < _pollOptions.length; i++) ...[
                Row(
                  children: [
                    GestureDetector(
                      onTap: _busy
                          ? null
                          : () async {
                              final files = await pickPhotos(context, max: 1, multi: false);
                              if (files.isNotEmpty) setState(() => _pollPhotos[i] = files.first);
                            },
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppColors.border),
                          image: _pollPhotos[i] == null ? null : DecorationImage(image: FileImage(File(_pollPhotos[i]!.path)), fit: BoxFit.cover),
                        ),
                        child: _pollPhotos[i] == null ? const Icon(AppIcons.cameraPlus, size: 18, color: AppColors.textSecondary) : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _pollOptions[i],
                        maxLength: 60,
                        decoration: InputDecoration(hintText: 'Option ${i + 1}', counterText: ''),
                      ),
                    ),
                    if (_pollOptions.length > 2)
                      IconButton(
                        icon: const Icon(AppIcons.x, size: 20),
                        onPressed: () => setState(() {
                          _pollOptions.removeAt(i).dispose();
                          _pollPhotos.remove(i);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (_pollOptions.length < 4)
                TextButton.icon(
                  onPressed: () => setState(() => _pollOptions.add(TextEditingController())),
                  icon: const Icon(AppIcons.plus, size: 18),
                  label: const Text('Add option'),
                ),
              const SizedBox(height: 8),
              const _Label('RUNS FOR'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final d in [1, 3, 7])
                    ChoiceChip(label: Text('$d day${d == 1 ? '' : 's'}'), selected: _pollDays == d, showCheckmark: false, onSelected: (_) => setState(() => _pollDays = d)),
                ],
              ),
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _caption,
              maxLength: 2200,
              minLines: _kind == PostKind.guide ? 5 : 3,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _kind == PostKind.guide ? 'The guide' : 'Caption',
                hintText: switch (_kind) {
                  PostKind.post => 'Write a caption…',
                  PostKind.spotted => 'Where and when? (skip the plate number)',
                  PostKind.poll => 'Add context (optional)',
                  PostKind.guide => 'Route, timing, food stops, what to bring…',
                },
                alignLabelWithHint: true,
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),

            if (_kind == PostKind.spotted) ...[
              const _Label('WHERE YOU SAW IT'),
              const SizedBox(height: 8),
              PinMap(
                start: ref.watch(userLocationProvider).value ?? kualaLumpur,
                onChanged: (p) => _pin = p,
                hint: 'Drag the map to where you spotted it',
              ),
              const SizedBox(height: 16),
            ],

            if (_kind == PostKind.guide) ...[
              const _Label('STOPS'),
              const SizedBox(height: 8),
              for (var i = 0; i < _stops.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 12, backgroundColor: AppColors.textPrimary, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12))),
                  title: Text(_stops[i].name),
                  trailing: IconButton(icon: const Icon(AppIcons.x, size: 20), onPressed: () => setState(() => _stops.removeAt(i))),
                ),
              TextButton.icon(
                onPressed: _busy ? null : () => _addStop(context),
                icon: const Icon(AppIcons.mapPinPlus, size: 18),
                label: const Text('Add a stop'),
              ),
              const SizedBox(height: 8),
            ],

            const _Label('TAG'),
            const SizedBox(height: 8),
            _TagRow(
              carId: _carId,
              eventId: _eventId,
              clubId: _clubId,
              place: _place,
              showClub: widget.vendorId == null,
              onCar: (v) => setState(() => _carId = v),
              onEvent: (v) => setState(() => _eventId = v),
              onClub: (v) => setState(() => _clubId = v),
              onPlace: (v) => setState(() => _place = v),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addStop(BuildContext context) async {
    final name = TextEditingController();
    LatLng? pin;
    final start = _stops.isNotEmpty ? _stops.last.latLng : (ref.read(userLocationProvider).value ?? kualaLumpur);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(ctx).bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add a stop', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Stop name, e.g. Gombak R&R')),
            const SizedBox(height: 12),
            PinMap(start: start, onChanged: (p) => pin = p, height: 200, hint: 'Drag to the stop'),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add stop')),
          ],
        ),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty && pin != null) {
      setState(() => _stops.add(GuideStop(name: name.text.trim(), lat: pin!.latitude, lng: pin!.longitude)));
    }
    name.dispose();
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary));
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos, required this.onAdd, required this.onRemove});
  final List<XFile> photos;
  final VoidCallback? onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return GestureDetector(
        onTap: onAdd,
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(AppIcons.cameraPlus, size: 36, color: AppColors.textSecondary),
                SizedBox(height: 8),
                Text('Add photos', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AspectRatio(aspectRatio: 4 / 3, child: Image.file(File(photos.first.path), fit: BoxFit.cover)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < photos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(photos[i].path), width: 72, height: 72, fit: BoxFit.cover)),
                      Positioned(
                        top: 3,
                        right: 3,
                        child: GestureDetector(
                          onTap: () => onRemove(i),
                          child: Container(width: 20, height: 20, decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(AppIcons.x, size: 13, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              if (photos.length < 10)
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                    child: const Icon(AppIcons.plus, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('${photos.length} of 10 · first photo is the cover', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// Tag chips: car (my garage), meet (my events), club (my clubs), place (search).
class _TagRow extends ConsumerWidget {
  const _TagRow({
    required this.carId,
    required this.eventId,
    required this.clubId,
    required this.place,
    this.showClub = true,
    required this.onCar,
    required this.onEvent,
    required this.onClub,
    required this.onPlace,
  });

  final String? carId;
  final String? eventId;
  final String? clubId;
  final Place? place;
  final bool showClub;
  final ValueChanged<String?> onCar;
  final ValueChanged<String?> onEvent;
  final ValueChanged<String?> onClub;
  final ValueChanged<Place?> onPlace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final cars = me == null ? const <Car>[] : ref.watch(userCarsProvider(me)).value ?? const <Car>[];
    final events = ref.watch(myEventsProvider).value;
    final allEvents = [...?events?.upcoming, ...?events?.past];
    final clubs = ref.watch(myClubsProvider).value ?? const <Club>[];

    final carName = cars.where((c) => c.id == carId).firstOrNull?.title;
    final eventName = allEvents.where((e) => e.id == eventId).firstOrNull?.title;
    final clubName = clubs.where((c) => c.id == clubId).firstOrNull?.name;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _TagChip(
          icon: AppIcons.car,
          label: carName ?? 'Car',
          active: carId != null,
          onTap: () => _pickFrom<Car>(context, 'Tag a car', cars, (c) => c.title, (c) => onCar(c?.id)),
        ),
        _TagChip(
          icon: AppIcons.flagCheckered,
          label: eventName ?? 'Meet',
          active: eventId != null,
          onTap: () => _pickFrom<Event>(context, 'Tag a meet', allEvents, (e) => e.title, (e) => onEvent(e?.id)),
        ),
        _TagChip(
          icon: AppIcons.mapPin,
          label: place?.name ?? 'Place',
          active: place != null,
          onTap: () => _pickPlace(context, ref),
        ),
        if (showClub) _TagChip(
          icon: AppIcons.shield,
          label: clubName ?? 'Club',
          active: clubId != null,
          onTap: () => _pickFrom<Club>(context, 'Tag a club', clubs, (c) => c.name, (c) => onClub(c?.id)),
        ),
      ],
    );
  }

  Future<void> _pickFrom<T>(BuildContext context, String title, List<T> items, String Function(T) label, void Function(T?) onPick) async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            if (items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing to tag yet.', style: TextStyle(color: AppColors.textSecondary))),
            for (final it in items) ListTile(title: Text(label(it)), onTap: () => Navigator.pop(ctx, it)),
            ListTile(leading: const Icon(AppIcons.x), title: const Text('No tag'), onTap: () => Navigator.pop(ctx, const _None())),
          ],
        ),
      ),
    );
    if (choice == null) return;
    onPick(choice is _None ? null : choice as T);
  }

  Future<void> _pickPlace(BuildContext context, WidgetRef ref) async {
    final query = TextEditingController();
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => SizedBox(
            height: 420,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: query,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Search places', prefixIcon: Icon(AppIcons.magnifyingGlass)),
                    onChanged: (_) => setSheet(() {}),
                  ),
                ),
                Expanded(
                  child: Consumer(
                    builder: (ctx, ref, _) {
                      final results = ref.watch(placeSearchProvider(query.text)).value ?? const <Place>[];
                      return ListView(
                        children: [
                          for (final p in results)
                            ListTile(
                              leading: ArtIcon(p.kindArt, size: 26),
                              title: Text(p.name),
                              subtitle: Text(p.kindLabel),
                              onTap: () => Navigator.pop(ctx, p),
                            ),
                          ListTile(leading: const Icon(AppIcons.x), title: const Text('No place'), onTap: () => Navigator.pop(ctx, const _None())),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    query.dispose();
    if (picked == null) return;
    onPlace(picked is _None ? null : picked as Place);
  }
}

class _None {
  const _None();
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.textPrimary : AppColors.surfaceGray,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : AppColors.textPrimary),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? Colors.white : AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}
