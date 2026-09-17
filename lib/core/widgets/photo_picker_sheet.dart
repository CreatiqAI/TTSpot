import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// "Choose from library / Take photo" sheet. Returns the chosen source or null.
Future<ImageSource?> showPhotoSourceSheet(BuildContext context, {VoidCallback? onRemove}) {
  return showModalBottomSheet<ImageSource>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(AppIcons.images),
            title: const Text('Choose from library'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(AppIcons.camera),
            title: const Text('Take photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          if (onRemove != null)
            ListTile(
              leading: const Icon(AppIcons.trash, color: AppColors.danger),
              title: const Text('Remove photo', style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(ctx);
                onRemove();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Picks one photo (camera or gallery) or several from the gallery.
Future<List<XFile>> pickPhotos(BuildContext context, {int max = 10, bool multi = true}) async {
  final source = await showPhotoSourceSheet(context);
  if (source == null) return const [];
  final picker = ImagePicker();
  if (source == ImageSource.gallery && multi && max > 1) {
    final files = await picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85, limit: max);
    return files.take(max).toList();
  }
  final f = await picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
  return f == null ? const [] : [f];
}
