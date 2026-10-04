import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/geo/latlng.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../core/config/media.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/geo.dart';
import '../../../core/utils/video_frame.dart';
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
import '../domain/post_place.dart';
import '../domain/post_video.dart';
import 'widgets/caption_suggestions.dart';
import 'widgets/chat_media.dart' show fmtMs;
import 'widgets/post_place_picker.dart';
import 'widgets/video_badge.dart';

/// New post / spotted / poll / guide. Instagram "New post" style: X, title, blue Share.
/// A post carries up to 10 photos or one video (60 s, 50 MB), and a place.
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

enum _Media { photoLibrary, photoCamera, videoLibrary, videoCamera }

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
  PostPlace? _place;
  bool _busy = false;

  // ---- the video, when the post is one
  XFile? _video;
  VideoPlayerController? _player;
  /// The still for grids and the feed, grabbed from the preview as it plays.
  Uint8List? _poster;
  final _frameKey = GlobalKey();
  bool _grabbing = false;
  int _grabTries = 0;
  bool _muted = true;

  PostKind get _kind => widget.kind;

  @override
  void initState() {
    super.initState();
    _eventId = widget.eventId;
    _carId = widget.carId;
    _clubId = widget.clubId;
    if (widget.placeId != null) {
      ref.read(placeProvider(widget.placeId!).future).then((p) {
        if (mounted && p != null && _place == null) setState(() => _place = PostPlace.spot(p));
      });
    }
    if (_kind != PostKind.poll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addMedia());
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _title.dispose();
    for (final c in _pollOptions) {
      c.dispose();
    }
    _disposeVideo();
    super.dispose();
  }

  void _disposeVideo() {
    final c = _player;
    _player = null;
    c?.removeListener(_onVideoTick);
    c?.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  /// Photos or a video, from the library or the camera. Once there are
  /// photos only more photos can go in; a video is the whole post.
  Future<void> _addMedia() async {
    if (_busy || _video != null) return;
    final room = kPostMaxPhotos - _photos.length;
    if (room <= 0) {
      _snack('Up to $kPostMaxPhotos photos per post.');
      return;
    }
    final withVideo = _photos.isEmpty;
    final secs = kPostVideoMaxDuration.inSeconds;
    final choice = await showModalBottomSheet<_Media>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(AppIcons.images),
                title: const Text('Photos from library'),
                subtitle: Text('Up to $room', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                onTap: () => Navigator.pop(ctx, _Media.photoLibrary),
              ),
              ListTile(leading: const Icon(AppIcons.camera), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, _Media.photoCamera)),
              if (withVideo) ...[
                ListTile(
                  leading: const Icon(AppIcons.play),
                  title: const Text('Video from library'),
                  subtitle: Text('One video, up to $secs seconds', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  onTap: () => Navigator.pop(ctx, _Media.videoLibrary),
                ),
                ListTile(
                  leading: const Icon(AppIcons.videoCamera),
                  title: const Text('Record a video'),
                  subtitle: Text('Up to $secs seconds', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  onTap: () => Navigator.pop(ctx, _Media.videoCamera),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _Media.photoLibrary:
      case _Media.photoCamera:
        final files = await pickPhotos(context, max: room, source: choice == _Media.photoLibrary ? ImageSource.gallery : ImageSource.camera);
        if (files.isNotEmpty && mounted) setState(() => _photos.addAll(files.take(room)));
      case _Media.videoLibrary:
        await _pickVideo(ImageSource.gallery);
      case _Media.videoCamera:
        await _pickVideo(ImageSource.camera);
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    final XFile? f;
    try {
      f = await ImagePicker().pickVideo(source: source, maxDuration: kPostVideoMaxDuration);
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
      return;
    }
    if (f == null || !mounted) return;
    // Size first: no point opening a file that can't go up.
    final bytes = await f.length();
    final tooBig = postVideoProblem(bytes: bytes);
    if (tooBig != null) {
      _snack(tooBig);
      return;
    }
    final c = VideoPlayerController.file(File(f.path));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      if (mounted) _snack('That video could not be opened. Try another.');
      return;
    }
    // Library picks can skip the picker's 60 s cap.
    final problem = postVideoProblem(bytes: bytes, length: c.value.duration);
    if (problem != null || !mounted) {
      await c.dispose();
      if (problem != null && mounted) _snack(problem);
      return;
    }
    await c.setLooping(true);
    await c.setVolume(0);
    _disposeVideo();
    c.addListener(_onVideoTick);
    setState(() {
      _video = f;
      _player = c;
      _poster = null;
      _grabbing = false;
      _grabTries = 0;
      _muted = true;
    });
    await c.play();
  }

  /// While the preview plays: a frame from just after the start becomes the
  /// still, like the chat preview does.
  void _onVideoTick() {
    final c = _player;
    if (c == null || !mounted) return;
    if (_poster != null || _grabbing || _grabTries >= 3) return;
    if (!c.value.isPlaying || c.value.position < const Duration(milliseconds: 250)) return;
    _grabbing = true;
    _grabTries++;
    grabVideoFrame(_frameKey).then((b) {
      if (!mounted || !identical(c, _player)) return;
      _grabbing = false;
      if (b != null) setState(() => _poster = b);
    });
  }

  /// The still to upload: the grabbed one, one more try now, or a drawn card.
  Future<Uint8List> _ensurePoster() async {
    if (_poster != null) return _poster!;
    final c = _player;
    if (c != null && c.value.isInitialized) {
      try {
        if (!c.value.isPlaying) {
          await c.play();
          await Future<void>.delayed(const Duration(milliseconds: 450));
        }
        await c.pause();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final b = await grabVideoFrame(_frameKey);
        if (b != null) return _poster = b;
      } catch (_) {}
    }
    return placeholderVideoPoster(aspect: c?.value.aspectRatio ?? 9 / 16);
  }

  void _removeVideo() {
    _disposeVideo();
    setState(() {
      _video = null;
      _poster = null;
    });
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _player?.setVolume(_muted ? 0 : 1);
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
    final hasMedia = _photos.isNotEmpty || _video != null;

    // Validation per kind
    if (_kind == PostKind.post && !hasMedia && _caption.text.trim().isEmpty) {
      _snack('Add a photo or video, or write something.');
      return;
    }
    if (_kind == PostKind.spotted && !hasMedia) {
      _snack('A spotted needs a photo or a video.');
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
      var aspect = 1.0;
      String? videoUrl;
      String? posterUrl;
      int? videoMs;
      final c = _player;
      if (_video != null && c != null) {
        final poster = await _ensurePoster();
        await c.pause();
        final up = await repo.uploadPostVideo(userId: me, path: _video!.path, poster: poster);
        videoUrl = up.url;
        posterUrl = up.posterUrl;
        videoMs = c.value.duration.inMilliseconds;
        // The poster doubles as the cover, so every grid shows the still.
        urls.add(up.posterUrl);
        final a = c.value.aspectRatio;
        aspect = a.isFinite && a > 0 ? a : 1.0;
      } else {
        for (final f in _photos) {
          urls.add(await repo.uploadPhoto(userId: me, bytes: await f.readAsBytes()));
        }
        if (_photos.isNotEmpty) aspect = await _aspectOf(_photos.first);
      }

      List<PollOption>? options;
      if (_kind == PostKind.poll) {
        options = [];
        for (var i = 0; i < _pollOptions.length; i++) {
          final text = _pollOptions[i].text.trim();
          if (text.isEmpty) continue;
          String? photoUrl;
          final pf = _pollPhotos[i];
          if (pf != null) photoUrl = await repo.uploadPhoto(userId: me, bytes: await pf.readAsBytes(), folder: 'polls', thumb: false);
          options.add(PollOption(text: text, photoUrl: photoUrl));
        }
      }

      // A TT Spot goes by id. Any other place is kept on the post: its name,
      // address and where it is (the spotted pin wins for a spotted).
      final place = _place;
      final freePlace = place != null && !place.isSpot ? place : null;
      final where = _kind == PostKind.spotted ? (_pin ?? freePlace?.latLng) : freePlace?.latLng;

      final post = await repo.createPost(
        authorId: me,
        kind: _kind,
        title: _kind == PostKind.poll || _kind == PostKind.guide ? _title.text : null,
        caption: _caption.text.trim().isEmpty ? null : _caption.text,
        photoUrls: urls,
        coverAspect: aspect,
        carId: _carId,
        eventId: _eventId,
        placeId: place?.spotId,
        placeName: freePlace?.name,
        placeAddress: (freePlace?.address ?? '').isEmpty ? null : freePlace!.address,
        clubId: _clubId,
        asClub: widget.asClub && _clubId == widget.clubId,
        vendorId: widget.vendorId,
        asVendor: widget.vendorId != null,
        location: where,
        videoUrl: videoUrl,
        videoPosterUrl: posterUrl,
        videoMs: videoMs,
        pollOptions: options,
        pollEndsAt: _kind == PostKind.poll ? DateTime.now().add(Duration(days: _pollDays)) : null,
        guideStops: _kind == PostKind.guide && _stops.isNotEmpty ? _stops : null,
      );
      ref.read(socialActionsProvider).refreshPost(post.id, authorId: me);
      if (_eventId != null) ref.invalidate(postsWhereProvider((column: 'event_id', value: _eventId!)));
      if (widget.vendorId != null) ref.invalidate(postsWhereProvider((column: 'vendor_id', value: widget.vendorId!)));
      if (place?.spotId != null) ref.invalidate(postsWhereProvider((column: 'place_id', value: place!.spotId!)));
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
        bottom: _busy && _video != null
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_kind != PostKind.poll) ...[
              if (_video != null && _player != null)
                _VideoPreview(
                  player: _player!,
                  frameKey: _frameKey,
                  poster: _poster,
                  muted: _muted,
                  onMute: _toggleMute,
                  onRemove: _busy ? null : _removeVideo,
                )
              else
                _PhotoStrip(photos: _photos, onAdd: _busy ? null : _addMedia, onRemove: (i) => setState(() => _photos.removeAt(i))),
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
                              final files = await pickPhotos(context, max: 1, multi: false, small: true);
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
                        child: _pollPhotos[i] == null ? Icon(AppIcons.cameraPlus, size: 18, color: AppColors.textSecondary) : null,
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

            // # suggests tags, @ suggests people, in a row above the keyboard.
            CaptionAssist(
              controller: _caption,
              child: TextField(
                controller: _caption,
                maxLength: 2200,
                minLines: _kind == PostKind.guide ? 5 : 3,
                maxLines: 12,
                textCapitalization: TextCapitalization.sentences,
                scrollPadding: kCaptionAssistScrollPadding,
                decoration: InputDecoration(
                  labelText: _kind == PostKind.guide ? 'The guide' : 'Caption',
                  hintText: switch (_kind) {
                    PostKind.post => 'Write a caption… #tags @friends',
                    PostKind.spotted => 'Where and when? (skip the plate number)',
                    PostKind.poll => 'Add context (optional)',
                    PostKind.guide => 'Route, timing, food stops, what to bring…',
                  },
                  alignLabelWithHint: true,
                  counterText: '',
                ),
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
                  leading: CircleAvatar(radius: 12, backgroundColor: AppColors.textPrimary, child: Text('${i + 1}', style: TextStyle(color: AppColors.onInk, fontSize: 12))),
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

            const _Label('LOCATION'),
            const SizedBox(height: 8),
            PostPlacePicker(value: _place, enabled: !_busy, onChanged: (p) => setState(() => _place = p)),
            const SizedBox(height: 16),

            const _Label('TAG'),
            const SizedBox(height: 8),
            _TagRow(
              carId: _carId,
              eventId: _eventId,
              clubId: _clubId,
              showClub: widget.vendorId == null,
              onCar: (v) => setState(() => _carId = v),
              onEvent: (v) => setState(() => _eventId = v),
              onClub: (v) => setState(() => _clubId = v),
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
      useRootNavigator: true, // above the shell tab bar
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
      Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary));
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
            padding: const EdgeInsets.all(12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.cameraPlus, size: 34, color: AppColors.textSecondary),
                      const SizedBox(width: 14),
                      Icon(AppIcons.videoCamera, size: 34, color: AppColors.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Add photos or a video', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Up to $kPostMaxPhotos photos, or one video up to ${kPostVideoMaxDuration.inSeconds} s', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
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
              if (photos.length < kPostMaxPhotos)
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                    child: Icon(AppIcons.plus, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('${photos.length} of $kPostMaxPhotos · first photo is the cover', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// The picked video, playing muted in a loop in the box the feed will show
/// (tap to pause, speaker to unmute, X to take it off), with the still the
/// grids will use once it has been grabbed.
class _VideoPreview extends StatelessWidget {
  const _VideoPreview({required this.player, required this.frameKey, required this.poster, required this.muted, required this.onMute, required this.onRemove});
  final VideoPlayerController player;
  final GlobalKey frameKey;
  final Uint8List? poster;
  final bool muted;
  final VoidCallback onMute;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final v = player.value;
    final ratio = v.aspectRatio.isFinite && v.aspectRatio > 0 ? v.aspectRatio : 9 / 16;
    final size = v.size.width > 0 && v.size.height > 0 ? v.size : Size(ratio * 1000, 1000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: ratio.clamp(0.8, 1.91),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                // Only the video inside the boundary: the still has no buttons on it.
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(width: size.width, height: size.height, child: RepaintBoundary(key: frameKey, child: VideoPlayer(player))),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => player.value.isPlaying ? player.pause() : player.play(),
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: player,
                    builder: (_, value, _) => value.isPlaying
                        ? const SizedBox.expand()
                        : Center(
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                              child: const Icon(AppIcons.playFill, color: Colors.white, size: 28),
                            ),
                          ),
                  ),
                ),
                Positioned(left: 8, bottom: 8, child: VideoBadge(ms: v.duration.inMilliseconds)),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: _RoundIcon(icon: muted ? AppIcons.speakerSlash : AppIcons.speakerHigh, label: muted ? 'Unmute' : 'Mute', onTap: onMute),
                ),
                if (onRemove != null) Positioned(right: 6, top: 6, child: _RoundIcon(icon: AppIcons.x, label: 'Remove video', onTap: onRemove!)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 36,
                height: 36,
                child: poster == null ? ColoredBox(color: AppColors.surfaceGray) : Image.memory(poster!, fit: BoxFit.cover, cacheWidth: 120, gaplessPlayback: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '1 video · ${fmtMs(v.duration.inMilliseconds)} · ${poster == null ? 'getting the cover…' : 'this still is the cover'}',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      );
}

/// Tag chips: car (my garage), meet (my events), club (my clubs).
class _TagRow extends ConsumerWidget {
  const _TagRow({
    required this.carId,
    required this.eventId,
    required this.clubId,
    this.showClub = true,
    required this.onCar,
    required this.onEvent,
    required this.onClub,
  });

  final String? carId;
  final String? eventId;
  final String? clubId;
  final bool showClub;
  final ValueChanged<String?> onCar;
  final ValueChanged<String?> onEvent;
  final ValueChanged<String?> onClub;

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
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            if (items.isEmpty) Padding(padding: EdgeInsets.all(16), child: Text('Nothing to tag yet.', style: TextStyle(color: AppColors.textSecondary))),
            for (final it in items) ListTile(title: Text(label(it)), onTap: () => Navigator.pop(ctx, it)),
            ListTile(leading: const Icon(AppIcons.x), title: const Text('No tag'), onTap: () => Navigator.pop(ctx, const _None())),
          ],
        ),
      ),
    );
    if (choice == null) return;
    onPick(choice is _None ? null : choice as T);
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
            Icon(icon, size: 16, color: active ? AppColors.onInk : AppColors.textPrimary),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? AppColors.onInk : AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}
