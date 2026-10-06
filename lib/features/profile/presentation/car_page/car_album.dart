import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/thumbnails.dart';
import 'car_build_tab.dart' show DashedButton;
import 'car_page_model.dart';

/// A section's title row: "Album 3" on the left, an action link on the right.
class CarSectionHeader extends StatelessWidget {
  const CarSectionHeader({super.key, required this.title, this.count, this.action, this.onAction, this.top = 30});
  final String title;
  final int? count;
  final String? action;
  final VoidCallback? onAction;

  /// Space above (the gap between sections).
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top, 6, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: title),
                  if (count != null && count! > 0)
                    TextSpan(text: '  $count', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2, color: AppColors.textPrimary),
            ),
          ),
          if (action != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(48, 40),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              child: Text(action!, maxLines: 1),
            )
          else
            const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// The member's own photos of the car as a tidy grid (one wide, two or four
/// in pairs, otherwise three to a row); a tap opens the photo viewer. The
/// first is the cover the toy is made from. Plate-hidden photos are already
/// their blurred copies. The owner with no photos gets a way to add some.
class CarAlbum extends StatelessWidget {
  const CarAlbum({super.key, required this.photos, required this.mine, required this.imageFor, required this.onOpen, this.onAdd});

  final List<String> photos;
  final bool mine;
  final CarImageResolver imageFor;
  final void Function(int index) onOpen;

  /// The owner's "Add photos" (to Edit car), or null.
  final VoidCallback? onAdd;

  static const gap = 4.0;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      if (onAdd == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DashedButton(label: '+ Add photos of your car', onTap: onAdd!, minHeight: 64),
      );
    }
    final layout = albumLayout(photos.length);
    final rows = <Widget>[];
    for (var start = 0; start < photos.length; start += layout.columns) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: start == 0 ? 0 : gap),
          child: Row(
            children: [
              for (var c = 0; c < layout.columns; c++) ...[
                if (c > 0) const SizedBox(width: gap),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: layout.aspect,
                    child: start + c < photos.length
                        ? _AlbumTile(
                            url: photos[start + c],
                            index: start + c,
                            total: photos.length,
                            cover: mine && start + c == 0 && photos.length > 1,
                            imageFor: imageFor,
                            onTap: () => onOpen(start + c),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.url, required this.index, required this.total, required this.cover, required this.imageFor, required this.onTap});
  final String url;
  final int index;
  final int total;
  final bool cover;
  final CarImageResolver imageFor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final thumb = thumbUrl(url);
    Widget full() => Image(
          image: ResizeImage(imageFor(url), width: (400 * dpr).round().clamp(200, 1200), policy: ResizeImagePolicy.fit),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.imageBroken, color: AppColors.textMuted)),
        );
    return Semantics(
      button: true,
      label: total == 1 ? 'Photo of the car' : 'Photo ${index + 1} of $total',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: AppColors.surfaceGray),
              if (thumb == url)
                full()
              else
                Image(image: imageFor(thumb), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => full()),
              if (cover)
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text(
                      'COVER',
                      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
