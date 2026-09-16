import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../events/application/event_providers.dart';
import '../../friends/application/friends_providers.dart';
import '../../map/application/map_providers.dart';
import '../application/community_providers.dart';
import '../application/social_providers.dart';
import '../data/social_repository.dart';

/// A moment: one photo + optional caption. Lives on the map for 24 hours,
/// and forever in the album of the meet or place it was taken at.
class CreateStoryScreen extends ConsumerStatefulWidget {
  const CreateStoryScreen({super.key, this.eventId, this.placeId});
  final String? eventId;
  final String? placeId;

  @override
  ConsumerState<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

enum _Kind { photo, video }

class _CreateStoryScreenState extends ConsumerState<CreateStoryScreen> {
  XFile? _photo;
  XFile? _video;
  VideoPlayerController? _player;
  final _posterKey = GlobalKey();
  final _caption = TextEditingController();
  bool _busy = false;
  bool _tagLocation = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  @override
  void dispose() {
    _caption.dispose();
    _player?.dispose();
    super.dispose();
  }

  /// Photo or video, from the camera or the library.
  Future<void> _pick() async {
    final choice = await showModalBottomSheet<(_Kind, ImageSource)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(AppIcons.camera), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, (_Kind.photo, ImageSource.camera))),
            ListTile(leading: const Icon(AppIcons.videoCamera), title: const Text('Record a video'), subtitle: Text('Up to 30 seconds', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)), onTap: () => Navigator.pop(ctx, (_Kind.video, ImageSource.camera))),
            ListTile(leading: const Icon(AppIcons.images), title: const Text('Photo from library'), onTap: () => Navigator.pop(ctx, (_Kind.photo, ImageSource.gallery))),
            ListTile(leading: const Icon(AppIcons.play), title: const Text('Video from library'), onTap: () => Navigator.pop(ctx, (_Kind.video, ImageSource.gallery))),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final picker = ImagePicker();
    if (choice.$1 == _Kind.photo) {
      final f = await picker.pickImage(source: choice.$2, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (f == null) return;
      _player?.dispose();
      setState(() { _photo = f; _video = null; _player = null; });
      return;
    }
    final f = await picker.pickVideo(source: choice.$2, maxDuration: const Duration(seconds: 30));
    if (f == null) return;
    final c = VideoPlayerController.file(File(f.path));
    try {
      await c.initialize();
      c.setLooping(true);
      c.play();
    } catch (_) {
      c.dispose();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That video could not be opened.')));
      return;
    }
    _player?.dispose();
    if (mounted) setState(() { _video = f; _photo = null; _player = c; });
  }

  /// A still of the video for thumbnails, pins and the viewer while it loads.
  /// Grabs the frame on screen; if that fails, draws a dark card with a play mark.
  Future<Uint8List> _poster() async {
    try {
      _player?.pause();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final boundary = _posterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final img = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        img.dispose();
        if (bytes != null && bytes.lengthInBytes > 2000) return bytes.buffer.asUint8List();
      }
    } catch (_) {}
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const w = 720.0, h = 1280.0;
    canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(0, h), [const Color(0xFF2A2F3A), const Color(0xFF0F1115)]));
    canvas.drawCircle(const Offset(w / 2, h / 2), 96, Paint()..color = Colors.white.withValues(alpha: 0.18));
    canvas.drawPath(Path()..moveTo(w / 2 - 28, h / 2 - 44)..lineTo(w / 2 + 44, h / 2)..lineTo(w / 2 - 28, h / 2 + 44)..close(), Paint()..color = Colors.white);
    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bytes!.buffer.asUint8List();
  }

  Future<void> _share() async {
    final me = ref.read(currentUserIdProvider);
    if ((_photo == null && _video == null) || me == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(socialRepositoryProvider);
      double? lat, lng;
      if (_tagLocation) {
        try {
          final p = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 6)),
          );
          lat = p.latitude;
          lng = p.longitude;
        } catch (_) {
          final last = ref.read(userLocationProvider).value;
          lat = last?.latitude;
          lng = last?.longitude;
        }
      }
      final my = ref.read(myLocationProvider).value;
      final eventId = widget.eventId ?? (_tagLocation ? my?.eventId : null);
      final placeId = widget.placeId ?? (eventId == null && _tagLocation ? my?.placeId : null);

      String url;
      String? videoUrl;
      if (_video != null) {
        url = await repo.uploadPoster(userId: me, bytes: await _poster());
        final ext = _video!.path.toLowerCase().endsWith('.mov') ? 'mov' : 'mp4';
        videoUrl = await repo.uploadStoryVideo(userId: me, bytes: await _video!.readAsBytes(), ext: ext);
      } else {
        url = await repo.uploadPhoto(userId: me, bytes: await _photo!.readAsBytes(), folder: 'stories');
      }
      await repo.createStory(
        me: me,
        photoUrl: url,
        videoUrl: videoUrl,
        caption: _caption.text.trim().isEmpty ? null : _caption.text,
        lat: lat,
        lng: lng,
        eventId: eventId,
        placeId: placeId,
      );
      ref.invalidate(storiesProvider);
      ref.invalidate(liveMomentsProvider);
      ref.invalidate(userMomentsProvider(me));
      if (eventId != null) {
        ref.invalidate(eventMomentsProvider(eventId));
        ref.invalidate(eventRecapProvider(eventId));
      }
      if (placeId != null) ref.invalidate(placeMomentsProvider(placeId));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final my = ref.watch(myLocationProvider).value;
    final eventTitle = widget.eventId != null
        ? ref.watch(eventDetailProvider(widget.eventId!)).value?.event.title
        : my?.eventId != null
            ? ref.watch(eventDetailProvider(my!.eventId!)).value?.event.title
            : null;
    final placeName = widget.placeId != null ? ref.watch(placeProvider(widget.placeId!)).value?.name : my?.placeName;
    final where = eventTitle ?? placeName;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _busy ? null : () => context.pop()),
        title: const Text('New moment', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (_photo != null || _video != null) IconButton(tooltip: 'Change', icon: const Icon(AppIcons.images), onPressed: _busy ? null : _pick),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _video != null && _player != null
                ? RepaintBoundary(
                    key: _posterKey,
                    child: Center(child: AspectRatio(aspectRatio: _player!.value.aspectRatio, child: VideoPlayer(_player!))),
                  )
                : _photo == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(AppIcons.cameraPlus, color: Colors.white, size: 40),
                            const SizedBox(height: 12),
                            const Text('A photo or a short video', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            const Text('Gone from the map in 24 hours. Stays in the album of the meet or spot.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12.5)),
                            const SizedBox(height: 16),
                            FilledButton(onPressed: _pick, style: FilledButton.styleFrom(minimumSize: const Size(160, 44)), child: const Text('Choose')),
                          ],
                        ),
                      )
                    : Image.file(File(_photo!.path), fit: BoxFit.contain),
          ),
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Row(
                    children: [
                      if (_tagLocation) ...[
                        ArtIcon(eventTitle != null ? AppArt.flag : AppArt.pin, size: 18),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          where == null
                              ? (_tagLocation ? 'Pinned to where you are' : 'Not pinned to the map')
                              : (_tagLocation ? where : 'Not pinned to the map'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Switch(value: _tagLocation, onChanged: (v) => setState(() => _tagLocation = v)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _caption,
                          maxLength: 200,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Add a caption…',
                            hintStyle: const TextStyle(color: Colors.white54),
                            counterText: '',
                            filled: true,
                            fillColor: Colors.white12,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: (_photo == null && _video == null) || _busy ? null : _share,
                        style: FilledButton.styleFrom(minimumSize: const Size(90, 46), backgroundColor: AppColors.primary),
                        child: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Share'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
