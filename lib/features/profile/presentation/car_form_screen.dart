import 'dart:io';

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
import '../../map/presentation/widgets/car_marker.dart';
import '../domain/car.dart';

/// Add or edit a car. Pass [carId] to edit.
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
  final _new = <XFile>[];
  bool _loaded = false;

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
    try {
      final f = await pickCarPhoto(source);
      if (f != null) setState(() => _new.add(f));
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final id = await ref.read(carFormControllerProvider.notifier).save(
          carId: widget.carId,
          make: _make.text,
          model: _model.text,
          yearText: _year.text,
          description: _description.text,
          color: _color,
          keptPhotoUrls: _kept,
          newPhotos: _new,
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
    final busy = ref.watch(carFormControllerProvider).isLoading;

    if (_isEdit) {
      final car = ref.watch(carProvider(widget.carId!));
      if (car.value == null && !car.hasError) {
        return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
      }
      if (car.value != null) _prefill(car.value!);
    }

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
            const Text('PHOTOS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _kept.length; i++)
                    _Thumb(image: NetworkImage(_kept[i]), onRemove: busy ? null : () => setState(() => _kept.removeAt(i))),
                  for (var i = 0; i < _new.length; i++)
                    _Thumb(image: FileImage(File(_new[i].path)), onRemove: busy ? null : () => setState(() => _new.removeAt(i))),
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
                        child: const Icon(AppIcons.cameraPlus, color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_kept.length + _new.length} of 5 · first photo is the cover',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
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
              decoration: const InputDecoration(labelText: 'Year (optional)', hintText: 'e.g. 2019'),
            ),
            const SizedBox(height: 18),
            const Text('COLOUR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            const Text('Shows as your car on the map.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in kCarColors.entries)
                  GestureDetector(
                    onTap: () => setState(() => _color = e.key),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: Border.all(color: _color == e.key ? AppColors.ink : AppColors.border, width: _color == e.key ? 3 : 1),
                          ),
                          child: _color == e.key ? Icon(AppIcons.check, size: 18, color: e.value.computeLuminance() > 0.5 ? AppColors.ink : Colors.white) : null,
                        ),
                        const SizedBox(height: 4),
                        Text(kCarColorLabels[e.key]!, style: TextStyle(fontSize: 10.5, fontWeight: _color == e.key ? FontWeight.w800 : FontWeight.w500)),
                      ],
                    ),
                  ),
              ],
            ),
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
