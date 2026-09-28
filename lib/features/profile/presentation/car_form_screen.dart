import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../application/profile_providers.dart';
import '../data/profile_repository.dart';
import '../domain/car.dart';
import '../domain/car_recognition.dart';
import 'widgets/car_color_picker.dart';
import 'widgets/car_scan_widgets.dart';

/// Add or edit a car. Pass [carId] to edit.
///
/// Adding: the first photo goes through the recogniser like onboarding does
/// (same scanning card, then the big model name, spec tiles and colour from
/// the photo) when make and model are still empty. Everything stays editable.
class CarFormScreen extends ConsumerStatefulWidget {
  const CarFormScreen({super.key, this.carId});
  final String? carId;

  @override
  ConsumerState<CarFormScreen> createState() => _CarFormScreenState();
}

class _CarFormScreenState extends ConsumerState<CarFormScreen> {
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  String? _color;
  final _description = TextEditingController();
  final _kept = <String>[];
  final _new = <Uint8List>[];
  bool _loaded = false;
  Car? _loadedCar;

  // recognition
  bool _recognizing = false;
  /// The photo being scanned, shown in the scanning card.
  Uint8List? _scanBytes;
  DateTime? _scanStart;
  /// The recogniser is back; the status rows go green before the reveal.
  bool _scanDone = false;
  /// A scan ran and found nothing it was sure of.
  bool _scanMissed = false;
  CarRecognition? _guess;
  bool _guessed = false;

  bool get _isEdit => widget.carId != null;

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _year.dispose();
    _description.dispose();
    super.dispose();
  }

  void _prefill(Car c) {
    if (_loaded) return;
    _loaded = true;
    _loadedCar = c;
    _make.text = c.make;
    _model.text = c.model;
    _year.text = c.year?.toString() ?? '';
    _color = c.color;
    _description.text = c.description ?? '';
    _kept.addAll(c.photoUrls);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addPhoto() async {
    if (_kept.length + _new.length >= 5) {
      _snack('Up to 5 photos per car.');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(AppIcons.images), title: const Text('Choose from library'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
            ListTile(leading: const Icon(AppIcons.camera), title: const Text('Take photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    Uint8List bytes;
    try {
      final f = await pickCarPhoto(source);
      if (f == null) return;
      bytes = await f.readAsBytes();
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
      return;
    }
    if (!mounted) return;

    // Nothing typed yet (or only our earlier guess, and no photo left) → let
    // the photo fill the form in. Never overwrite what the member typed.
    final blank = _make.text.trim().isEmpty && _model.text.trim().isEmpty;
    final untouchedGuess = _guessed && _guess!.matches(_make.text, _model.text) && _kept.isEmpty && _new.isEmpty;
    if (_isEdit || !(blank || untouchedGuess)) {
      setState(() => _new.add(bytes));
      return;
    }
    final started = DateTime.now();
    setState(() {
      _recognizing = true;
      _scanBytes = bytes;
      _scanStart = started;
      _scanDone = false;
    });
    final prepared = await prepareCarPhoto(ref.read(profileRepositoryProvider), bytes);
    if (!mounted) return;
    // Let the status rows finish ticking before the reveal, like onboarding.
    setState(() => _scanDone = true);
    final left = kCarScanHold - DateTime.now().difference(started);
    await Future<void>.delayed((left.isNegative ? Duration.zero : left) + const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() {
      _recognizing = false;
      _scanBytes = null;
      _new.add(prepared.bytes);
      // The member may have typed while TiTi was looking: keep their words.
      final untouched = (_make.text.trim().isEmpty && _model.text.trim().isEmpty) || (_guessed && _guess!.matches(_make.text, _model.text));
      if (!untouched) return;
      final g = prepared.guess;
      if (g != null && g.confident) {
        _guess = g;
        _guessed = true;
        _scanMissed = false;
        _make.text = g.make;
        _model.text = g.model;
        _year.text = g.year?.toString() ?? '';
        _color = g.color ?? _color;
      } else {
        if (_guessed) {
          _make.clear();
          _model.clear();
          _year.clear();
        }
        _guess = null;
        _guessed = false;
        _scanMissed = true;
      }
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    // Spec line / body style only while they still describe this make + model.
    String? specs;
    String? bodyStyle;
    final g = _guess;
    if (g != null && g.matches(_make.text, _model.text)) {
      specs = g.specLine;
      bodyStyle = g.bodyStyle;
    } else if (_loadedCar != null && _loadedCar!.make.trim().toLowerCase() == _make.text.trim().toLowerCase() && _loadedCar!.model.trim().toLowerCase() == _model.text.trim().toLowerCase()) {
      specs = _loadedCar!.specs;
      bodyStyle = _loadedCar!.bodyStyle;
    }
    final id = await ref.read(carFormControllerProvider.notifier).save(
          carId: widget.carId,
          make: _make.text,
          model: _model.text,
          yearText: _year.text,
          description: _description.text,
          color: _color,
          keptPhotoUrls: _kept,
          newPhotos: _new,
          specs: specs,
          bodyStyle: bodyStyle,
        );
    if (id != null && mounted) {
      if (_isEdit) {
        context.pop();
      } else {
        context.pushReplacement(Routes.car(id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(carFormControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) _snack(friendlyError(next.error!));
    });
    final busy = ref.watch(carFormControllerProvider).isLoading || _recognizing;

    if (_isEdit) {
      final car = ref.watch(carProvider(widget.carId!));
      if (car.value == null && !car.hasError) {
        return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
      }
      if (car.value != null) _prefill(car.value!);
    }

    final yearHint = _guess?.yearRange;
    final make = _make.text.trim();
    final model = _model.text.trim();
    final tiles = carSpecTiles(_guess, make, model);
    final cover = _new.isNotEmpty ? _new.first : null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: busy ? null : () => context.pop()),
        title: Text(_isEdit ? 'Edit car' : 'Add car'),
        actions: [
          busy
              ? const Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : TextButton(onPressed: _save, child: Text(_isEdit ? 'Save' : 'Add')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_recognizing && _scanBytes != null) ...[
              CarScanningCard(image: MemoryImage(_scanBytes!), startedAt: _scanStart ?? DateTime.now(), done: _scanDone),
              const SizedBox(height: 18),
              Text(
                'Usually under 5 seconds. You can correct anything after.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 24),
            ] else if (_guessed) ...[
              // Found it: the same reveal as onboarding, over the editable form.
              if (cover != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AspectRatio(aspectRatio: 4 / 3, child: Image.memory(cover, fit: BoxFit.cover, gaplessPlayback: true)),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  const TitiAvatar(TitiPose.thumbsUp, size: 44),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Found it. Clean ${_guess!.model}. Check the details below.',
                      style: TextStyle(fontSize: 14.5, height: 1.35, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              CarFoundTitle(make: make, model: model, year: _year.text.trim().isNotEmpty ? _year.text.trim() : (yearHint ?? '')),
              if (tiles.isNotEmpty) ...[
                const SizedBox(height: 18),
                CarSpecGrid(tiles: tiles),
              ],
              const SizedBox(height: 24),
            ] else if (_scanMissed && !_isEdit) ...[
              Row(
                children: [
                  const TitiAvatar(TitiPose.sad, size: 44),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'I couldn\'t tell what this is. Type it in below.',
                      style: TextStyle(fontSize: 14.5, height: 1.35, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
            Text('PHOTOS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _kept.length; i++)
                    _Thumb(image: CachedNetworkImageProvider(_kept[i]), onRemove: busy ? null : () => setState(() => _kept.removeAt(i))),
                  for (var i = 0; i < _new.length; i++)
                    _Thumb(image: MemoryImage(_new[i]), onRemove: busy ? null : () => setState(() => _new.removeAt(i))),
                  if (_kept.length + _new.length < 5)
                    GestureDetector(
                      onTap: busy ? null : _addPhoto,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Icon(AppIcons.cameraPlus, color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _recognizing ? 'Looking at your car…' : '${_kept.length + _new.length} of 5 · first photo is the cover',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _make,
              textCapitalization: TextCapitalization.words,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Make', hintText: 'e.g. Perodua', counterText: ''),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _model,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Model', hintText: 'e.g. Myvi 1.5 AV', counterText: ''),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _year,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              decoration: InputDecoration(labelText: 'Year (optional)', hintText: yearHint == null ? 'e.g. 2019' : 'Our guess: $yearHint'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            Text('COLOUR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(
              _guessed && _color != null
                  ? '${carColourNote(_color, fromPhoto: _guess?.color == _color)} · shows as your car on the map'
                  : 'Shows as your car on the map.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            CarColorPicker(value: _color, onChanged: (v) => setState(() => _color = v)),
            const SizedBox(height: 14),
            TextField(
              controller: _description,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Specs & mods',
                hintText: 'Turbo, coilovers, wheels, exhaust… or bone stock, that\'s fine too.',
                alignLabelWithHint: true,
                counterText: '',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.onRemove});
  final ImageProvider image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Image(image: image, width: 96, height: 96, fit: BoxFit.cover),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(AppIcons.x, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
