import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/image_crop_screen.dart';
import '../../../../core/widgets/photo_picker_sheet.dart';
import '../../application/create_event_controller.dart';
import '../../application/plan_draft.dart';
import '../../domain/cover_presets.dart';
import 'wizard_parts.dart';

/// Step "Make it yours": the cover (a preset or your own photo, cropped to
/// the cover shape), the title (suggested from the place), and notes tucked
/// under More options.
class StyleStep extends StatefulWidget {
  const StyleStep({super.key, required this.draft});
  final PlanDraft draft;

  @override
  State<StyleStep> createState() => _StyleStepState();
}

class _StyleStepState extends State<StyleStep> {
  late bool _more = widget.draft.notesCtrl.text.trim().isNotEmpty;

  PlanDraft get d => widget.draft;

  Future<void> _upload() async {
    final source = await showPhotoSourceSheet(context);
    if (source == null || !mounted) return;
    try {
      final f = await pickCoverImage(source);
      if (f == null || !mounted) return;
      final cropped = await cropImage(context, f, aspect: 16 / 9, outputWidth: 1600, title: 'Frame your cover');
      if (cropped != null) d.setCoverFile(cropped);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final presets = coverPresetsFor(d.type);
        final selected = d.coverFile != null ? null : (d.presetId ?? d.type.db);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const StepHeading('Make it yours', subtitle: 'A cover and a name. Both are ready to go, change them if you like.'),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: d.coverFile != null ? Image.file(File(d.coverFile!.path), fit: BoxFit.cover) : Image.asset(d.coverAsset, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              // Thumbnail + one label line, grown with the text size.
              height: 66 + MediaQuery.textScalerOf(context).scale(11.5) * 1.6,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _CoverTile(
                    key: const Key('plan-cover-upload'),
                    label: d.coverFile == null ? 'Your photo' : 'Change photo',
                    selected: d.coverFile != null,
                    onTap: _upload,
                    child: d.coverFile != null
                        ? Image.file(File(d.coverFile!.path), fit: BoxFit.cover)
                        : ColoredBox(color: AppColors.surfaceGray, child: Center(child: Icon(AppIcons.cameraPlus, size: 24, color: AppColors.textPrimary))),
                  ),
                  for (final p in presets)
                    _CoverTile(
                      key: Key('plan-cover-${p.id}'),
                      label: p.label,
                      selected: selected == p.id,
                      onTap: () => d.pickPreset(p.id),
                      child: Image.asset(p.asset, fit: BoxFit.cover, cacheWidth: 240),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('plan-title'),
              controller: d.titleCtrl,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => d.titleTyped(),
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: d.session ? 'e.g. Friday teh tarik' : 'e.g. Sunway Night Meet',
                helperText: d.titleEdited ? null : 'Suggested from the place',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _more = !_more),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(child: Text('More options', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                    Icon(_more ? AppIcons.caretUp : AppIcons.caretDown, size: 18, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: !_more
                  ? const SizedBox(width: double.infinity)
                  : TextField(
                      textInputAction: TextInputAction.done,
                      keyboardType: TextInputType.text,
                      key: const Key('plan-notes'),
                      controller: d.notesCtrl,
                      maxLength: 2000,
                      minLines: 2,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        hintText: 'Parking, what to bring, who it\'s for…',
                        alignLabelWithHint: true,
                        counterText: '',
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({super.key, required this.label, required this.selected, required this.onTap, required this.child});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 104,
            margin: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 104,
                  height: 58,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? AppColors.brand : AppColors.border, width: selected ? 2.5 : 1),
                  ),
                  child: child,
                ),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? AppColors.textPrimary : AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
}
