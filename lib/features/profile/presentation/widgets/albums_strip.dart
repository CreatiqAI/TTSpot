import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/thumb_image.dart';
import '../../../social/domain/album.dart';

/// Moment albums as a slim row of circles at the top of the Posts tab.
/// Hidden when there is nothing to show, so the profile stays clean.
class AlbumsStrip extends StatelessWidget {
  const AlbumsStrip({super.key, required this.albums, required this.onAlbum, this.onAdd});
  final List<MomentAlbum> albums;
  final ValueChanged<MomentAlbum> onAlbum;
  /// Owner only.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        children: [
          if (onAdd != null) _Circle(onTap: onAdd!),
          for (final a in albums) _Circle(album: a, onTap: () => onAlbum(a)),
        ],
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({this.album, required this.onTap});
  final MomentAlbum? album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = album;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 62,
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: a == null ? AppColors.border : AppColors.textPrimary, width: 1.5)),
                child: ClipOval(
                  child: a == null
                      ? ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.plus, size: 20, color: AppColors.textSecondary))
                      : a.coverUrl == null
                          ? ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.images, size: 20, color: AppColors.textSecondary))
                          : ThumbImage(a.coverUrl!, error: ColoredBox(color: AppColors.surfaceGray)),
                ),
              ),
              const SizedBox(height: 4),
              Text(a == null ? 'New' : a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
