import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../social/application/community_providers.dart';

/// Add an entry to a car's build timeline.
class CarModFormScreen extends ConsumerStatefulWidget {
  const CarModFormScreen({super.key, required this.carId});
  final String carId;

  @override
  ConsumerState<CarModFormScreen> createState() => _CarModFormScreenState();
}

class _CarModFormScreenState extends ConsumerState<CarModFormScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _cost = TextEditingController();
  DateTime _date = DateTime.now();
  final _photos = <XFile>[];
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref.read(communityActionsProvider).addMod(
            carId: widget.carId,
            title: _title.text,
            description: _description.text.trim().isEmpty ? null : _description.text,
            cost: _cost.text.trim().isEmpty ? null : double.tryParse(_cost.text.trim()),
            doneOn: _date,
            photos: _photos,
          );
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _busy ? null : () => context.pop()),
        title: const Text('Add to build log'),
        actions: [
          _busy
              ? const Padding(padding: EdgeInsets.only(right: 20), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
              : TextButton(onPressed: _save, child: const Text('Add')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(controller: _title, maxLength: 80, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'What did you do?', hintText: 'e.g. BC Racing coilovers', counterText: '')),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: const InputDecoration(labelText: 'Cost (optional)', prefixText: 'RM '),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(1990), lastDate: DateTime.now());
                    if (d != null) setState(() => _date = d);
                  },
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.border)),
                    child: Row(children: [Icon(AppIcons.calendarBlank, size: 18, color: AppColors.textSecondary), const SizedBox(width: 8), Text(formatDate(_date), style: const TextStyle(fontSize: 15))]),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(controller: _description, maxLength: 500, minLines: 2, maxLines: 5, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'Brand, spec, who did the work, how it feels', alignLabelWithHint: true, counterText: '')),
          const SizedBox(height: 16),
          Text('PHOTOS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          SizedBox(
            height: 84,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_photos[i].path), width: 84, height: 84, fit: BoxFit.cover)),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setState(() => _photos.removeAt(i)),
                            child: Container(width: 20, height: 20, decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(AppIcons.x, size: 13, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_photos.length < 5)
                  GestureDetector(
                    onTap: () async {
                      final files = await pickPhotos(context, max: 5 - _photos.length);
                      if (files.isNotEmpty) setState(() => _photos.addAll(files));
                    },
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                      child: Icon(AppIcons.cameraPlus, color: AppColors.textSecondary),
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
