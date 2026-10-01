import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/image_crop_screen.dart';
import '../../../../core/widgets/photo_picker_sheet.dart';
import '../../application/community_providers.dart';
import '../../domain/club.dart';

/// Pick a photo and frame it as a round logo (a square crop). Null when cancelled.
Future<XFile?> pickClubLogo(BuildContext context) async {
  final files = await pickPhotos(context, max: 1, multi: false);
  if (files.isEmpty || !context.mounted) return null;
  return cropImage(context, files.first, aspect: 1, outputWidth: 600, round: true, title: 'Frame your logo');
}

/// Officers: pick, crop and save a new logo for [clubId]. True when saved.
Future<bool> changeClubLogo(BuildContext context, WidgetRef ref, String clubId) async {
  final logo = await pickClubLogo(context);
  if (logo == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(communityActionsProvider).setClubLogo(clubId, logo);
    messenger.showSnackBar(const SnackBar(content: Text('Logo saved.')));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    return false;
  }
}

/// The big round logo slot on the new-club form: required, so it says so.
class ClubLogoPicker extends StatelessWidget {
  const ClubLogoPicker({super.key, this.file, this.url, required this.onTap, this.missing = false});
  final XFile? file;
  /// Already uploaded (from the club application).
  final String? url;
  final VoidCallback? onTap;
  /// Highlight the slot (the member tried to go on without a logo).
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final ImageProvider? image = file != null ? FileImage(File(file!.path)) : ((url ?? '').isNotEmpty ? NetworkImage(url!) : null);
    return Column(
      children: [
        Semantics(
          button: true,
          label: image == null ? 'Add club logo' : 'Change club logo',
          child: GestureDetector(
            key: const Key('club-logo-picker'),
            onTap: onTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceGray,
                    border: Border.all(color: missing ? AppColors.danger : (image == null ? AppColors.border : AppColors.brand), width: image == null && !missing ? 1.5 : 2.5),
                    image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover),
                  ),
                  child: image == null ? Icon(AppIcons.cameraPlus, size: 34, color: missing ? AppColors.danger : AppColors.textSecondary) : null,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 3)),
                    child: Icon(image == null ? AppIcons.plus : AppIcons.pencilSimple, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(onPressed: onTap, child: Text(image == null ? 'Add club logo' : 'Change logo')),
        Text(
          kClubLogoHint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, height: 1.35, color: missing ? AppColors.danger : AppColors.textSecondary, fontWeight: missing ? FontWeight.w600 : FontWeight.w400),
        ),
      ],
    );
  }
}

/// On a club page with no logo yet, for its officers: the nudge to add one.
class ClubLogoBanner extends ConsumerStatefulWidget {
  const ClubLogoBanner({super.key, required this.club});
  final Club club;

  @override
  ConsumerState<ClubLogoBanner> createState() => _ClubLogoBannerState();
}

class _ClubLogoBannerState extends ConsumerState<ClubLogoBanner> {
  bool _busy = false;

  Future<void> _upload() async {
    setState(() => _busy = true);
    await changeClubLogo(context, ref, widget.club.id);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('club-logo-banner'),
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Color.alphaBlend(AppColors.brand.withValues(alpha: AppColors.dark ? 0.18 : 0.07), AppColors.surface),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.brand.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            ClipOval(child: Image.asset(crestAsset(widget.club.id), width: 44, height: 44, fit: BoxFit.contain)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add your club logo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('It shows on the map and on your events.', style: TextStyle(fontSize: 12.5, height: 1.3, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _upload,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
              child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Upload'),
            ),
          ],
        ),
      );
}
