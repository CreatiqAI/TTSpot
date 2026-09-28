import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../application/profile_providers.dart';
import '../data/profile_repository.dart';
import '../domain/car.dart';
import '../domain/car_recognition.dart';
import 'widgets/car_color_picker.dart';

/// Add or edit a car. Pass [carId] to edit.
///
/// Adding: the first photo goes through the recogniser (make, model, year,
/// colour prefilled, plate blurred) when make and model are still empty.
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
  CarRecognition? _guess;
  bool _guessed = false;
  bool _plateBlurred = false;

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

    // Nothing typed yet → let the photo fill the form in.
    final blank = _make.text.trim().isEmpty && _model.text.trim().isEmpty;
    if (!blank) {
      setState(() => _new.add(bytes));
      return;
    }
    setState(() => _recognizing = true);
    final prepared = await prepareCarPhoto(ref.read(profileRepositoryProvider), bytes);
    if (!mounted) return;
    setState(() {
      _recognizing = false;
      _new.add(prepared.bytes);
      _plateBlurred = _plateBlurred || prepared.plateBlurred;
      final g = prepared.guess;
      if (g != null && g.confident) {
        _guess = g;
        _guessed = true;
        _make.text = g.make;
        _model.text = g.model;
        _year.text = g.year?.toString() ?? '';
        _color = g.color ?? _color;
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
                  if (_recognizing)
                    Container(
                      width: 96,
                      height: 96,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.border)),
                      child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                    ),
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
              _recognizing
                  ? 'Looking at your car…'
                  : '${_kept.length + _new.length} of 5 · first photo is the cover${_plateBlurred ? ' · plate blurred' : ''}',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (_guessed) ...[
              const SizedBox(height: 12),
              const CarGuessNote(),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _make,
              textCapitalization: TextCapitalization.words,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Make', hintText: 'e.g. Perodua', counterText: ''),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _model,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Model', hintText: 'e.g. Myvi 1.5 AV', counterText: ''),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _year,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              decoration: InputDecoration(labelText: 'Year (optional)', hintText: yearHint == null ? 'e.g. 2019' : 'Our guess: $yearHint'),
            ),
            const SizedBox(height: 18),
            Text('COLOUR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text('Shows as your car on the map.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
