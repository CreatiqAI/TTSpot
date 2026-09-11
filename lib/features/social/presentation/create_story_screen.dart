import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
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

class _CreateStoryScreenState extends ConsumerState<CreateStoryScreen> {
  XFile? _photo;
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
    super.dispose();
  }

  Future<void> _pick() async {
    final files = await pickPhotos(context, max: 1, multi: false);
    if (files.isNotEmpty) setState(() => _photo = files.first);
  }

  Future<void> _share() async {
    final me = ref.read(currentUserIdProvider);
    if (_photo == null || me == null) return;
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

      final url = await repo.uploadPhoto(userId: me, bytes: await _photo!.readAsBytes(), folder: 'stories');
      await repo.createStory(
        me: me,
        photoUrl: url,
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
          if (_photo != null) IconButton(icon: const Icon(AppIcons.images), onPressed: _busy ? null : _pick),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _photo == null
                ? Center(
                    child: TextButton.icon(
                      onPressed: _pick,
                      icon: const Icon(AppIcons.cameraPlus, color: Colors.white),
                      label: const Text('Pick a photo', style: TextStyle(color: Colors.white)),
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
                        onPressed: _photo == null || _busy ? null : _share,
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
