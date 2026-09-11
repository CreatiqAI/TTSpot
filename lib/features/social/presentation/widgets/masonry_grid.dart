import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/post.dart';

/// RedNote-style two-column waterfall. Items go to whichever column is shorter.
class MasonryGrid extends StatelessWidget {
  const MasonryGrid({super.key, required this.items, this.padding = const EdgeInsets.fromLTRB(8, 8, 8, 24)});
  final List<FeedPost> items;
  final EdgeInsets padding;

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final left = <FeedPost>[];
    final right = <FeedPost>[];
    var hl = 0.0, hr = 0.0;
    for (final f in items) {
      final h = _estimatedHeight(f.post);
      if (hl <= hr) {
        left.add(f);
        hl += h;
      } else {
        right.add(f);
        hr += h;
      }
    }
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: [for (final f in left) PostTile(feed: f)])),
          const SizedBox(width: _gap),
          Expanded(child: Column(children: [for (final f in right) PostTile(feed: f)])),
        ],
      ),
    );
  }

  static double _estimatedHeight(Post p) {
    final aspect = p.photoUrls.isEmpty ? 1.2 : p.coverAspect.clamp(0.6, 1.6);
    return 1 / aspect + 0.45; // image + text block, in "column widths"
  }
}

class PostTile extends StatelessWidget {
  const PostTile({super.key, required this.feed});
  final FeedPost feed;

  @override
  Widget build(BuildContext context) {
    final p = feed.post;
    final aspect = p.photoUrls.isEmpty ? 1.2 : p.coverAspect.clamp(0.6, 1.6);
    final text = p.kind == PostKind.guide || p.kind == PostKind.poll ? (p.title ?? p.caption ?? '') : (p.caption ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: MasonryGrid._gap),
      child: GestureDetector(
        onTap: () => context.push(Routes.post(p.id)),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: aspect,
                child: p.cover == null
                    ? ColoredBox(
                        color: AppColors.surfaceRaised,
                        child: Center(
                          child: Text(
                            switch (p.kind) { PostKind.poll => '📊', PostKind.guide => '🗺️', PostKind.spotted => '👀', PostKind.post => '📝' },
                            style: const TextStyle(fontSize: 40),
                          ),
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            p.cover!,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, prog) => prog == null ? child : const ColoredBox(color: AppColors.surfaceGray),
                            errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surfaceGray),
                          ),
                          if (p.kind != PostKind.post)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                                child: Text(
                                  switch (p.kind) { PostKind.spotted => '👀 Spotted', PostKind.guide => '🗺️ Guide', PostKind.poll => '📊 Poll', PostKind.post => '' },
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (text.trim().isNotEmpty) ...[
                      Text(text.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.3)),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        UserAvatar(url: p.author?.avatarUrl, name: p.author?.displayName ?? p.author?.username, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(p.author?.username ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ),
                        Icon(feed.likedByMe ? AppIcons.heartFill : AppIcons.heart, size: 14, color: feed.likedByMe ? AppColors.danger : AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Text('${p.likeCount}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
