import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/places/places_service.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/place_search_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../map/application/map_providers.dart';
import '../data/community_repository.dart';

/// "Suggest a spot": pick the place, say what kind it is, add a photo and a
/// line about parking. Admins approve it into the Spots layer; you get points.
class SuggestSpotScreen extends ConsumerStatefulWidget {
  const SuggestSpotScreen({super.key});

  @override
  ConsumerState<SuggestSpotScreen> createState() => _SuggestSpotScreenState();
}

class _SuggestSpotScreenState extends ConsumerState<SuggestSpotScreen> {
  PlaceDetails? _place;
  String _kind = 'mamak';
  final _note = TextEditingController();
  XFile? _photo;
  bool _busy = false;

  static const _kinds = [('mamak', 'Mamak / café'), ('carpark', 'Carpark'), ('route', 'Driving road'), ('mall', 'Mall'), ('circuit', 'Circuit'), ('other', 'Other')];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final files = await pickPhotos(context, max: 1, multi: false);
    if (files.isNotEmpty) setState(() => _photo = files.first);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final p = _place;
    if (p == null) {
      _snack('Search and pick the place first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final me = ref.read(currentUserIdProvider)!;
      String? photoUrl;
      if (_photo != null) {
        photoUrl = await ref.read(communityRepositoryProvider).uploadPhoto(userId: me, bytes: await _photo!.readAsBytes(), folder: 'spots');
      }
      await ref.read(supabaseProvider).from('place_suggestions').insert({
        'user_id': me,
        'name': p.name,
        'address': p.address,
        'lat': p.lat,
        'lng': p.lng,
        'google_place_id': p.placeId.isEmpty ? null : p.placeId,
        'kind': _kind,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'photo_url': photoUrl,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks. TT Spot will check it and add it to the map. 30 points when it goes live.')));
      context.pop();
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final here = ref.watch(userLocationProvider).value;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _busy ? null : () => context.pop()),
        title: const Text('Suggest a spot'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text(
              'Know a good mamak, carpark or driving road? Put it on the map for everyone.',
              style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),
            const _Label('WHERE'),
            const SizedBox(height: 8),
            PlaceSearchField(
              enabled: !_busy,
              near: here == null ? null : (here.latitude, here.longitude),
              hint: 'Search the place',
              onPicked: (d) => setState(() => _place = d),
            ),
            if (_place != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Row(
                  children: [
                    const Icon(AppIcons.mapPin, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_place!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(_place!.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            const _Label('WHAT KIND'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in _kinds)
                  ChoiceChip(label: Text(k.$2), selected: _kind == k.$1, showCheckmark: false, onSelected: _busy ? null : (_) => setState(() => _kind = k.$1)),
              ],
            ),
            const SizedBox(height: 18),
            const _Label('PHOTO (OPTIONAL)'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _busy ? null : _pickPhoto,
              child: Container(
                height: 150,
                decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.border)),
                clipBehavior: Clip.antiAlias,
                child: _photo == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(AppIcons.cameraPlus, size: 28, color: AppColors.textSecondary),
                          SizedBox(height: 6),
                          Text('Add a photo of the spot', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                        ],
                      )
                    : Image.file(File(_photo!.path), fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _note,
              maxLength: 500,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Why is it good? (optional)', hintText: 'Parking, best time, what to order…', alignLabelWithHint: true, counterText: ''),
            ),
            const SizedBox(height: 22),
            PrimaryButton(label: 'Send suggestion', loading: _busy, onPressed: _busy ? null : _submit),
            const SizedBox(height: 10),
            const Text(
              'TT Spot checks every suggestion. Public places only, no private homes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary));
}
