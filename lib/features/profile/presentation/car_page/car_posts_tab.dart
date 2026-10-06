import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/thumbnails.dart';
import '../../../social/domain/post.dart';
import 'car_build_tab.dart' show CarEmptyCard;
import 'car_page_model.dart';

/// Posts that tag this car, three square tiles to a row.
class CarPostsTab extends StatelessWidget {
  const CarPostsTab({super.key, required this.posts, required this.mine, required this.onOpen, required this.onPost, required this.imageFor});
  final List<FeedPost>? posts;
  final bool mine;
  final ValueChanged<String> onOpen;
  final VoidCallback onPost;
  final CarImageResolver imageFor;

  @override
  Widget build(BuildContext context) {
    final list = posts;
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (list.isEmpty) {
      if (!mine) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: CarEmptyCard(title: 'SHOW IT OFF', body: 'Posts that tag this car show up here.', action: 'Post about it', onAction: onPost),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: GridView.builder(
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
        itemCount: list.length,
        itemBuilder: (_, i) => _PostSquare(post: list[i].post, onTap: () => onOpen(list[i].post.id), imageFor: imageFor),
      ),
    );
  }
}

class _PostSquare extends StatelessWidget {
  const _PostSquare({required this.post, required this.onTap, required this.imageFor});
  final Post post;
  final VoidCallback onTap;
  final CarImageResolver imageFor;

  @override
  Widget build(BuildContext context) {
    final p = post;
    final cover = p.cover;
    final text = (p.kind == PostKind.guide || p.kind == PostKind.poll ? (p.title ?? p.caption) : p.caption) ?? '';
    final kindIcon = switch (p.kind) {
      PostKind.spotted => AppIcons.binoculars,
      PostKind.guide => AppIcons.signpost,
      PostKind.poll => AppIcons.chartBar,
      PostKind.post => null,
    };
    return Semantics(
      button: true,
      label: text.trim().isEmpty ? 'Post' : text.trim(),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cover != null)
                Image(
                  image: imageFor(thumbUrl(cover)),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Image(image: imageFor(cover), fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray)),
                )
              else
                ColoredBox(
                  color: AppColors.surfaceGray,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      text.trim(),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ),
                ),
              if (kindIcon != null)
                Positioned(left: 6, top: 6, child: _Badge(icon: kindIcon)),
              if (p.isVideo)
                const Positioned(right: 6, top: 6, child: _Badge(icon: AppIcons.playFill))
              else if (p.photoUrls.length > 1)
                const Positioned(right: 6, top: 6, child: _Badge(icon: AppIcons.copy)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
        child: Icon(icon, size: 12, color: Colors.white),
      );
}
