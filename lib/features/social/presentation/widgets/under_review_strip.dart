import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/thumb_image.dart';
import '../../application/moderation_providers.dart';
import '../../domain/post.dart';

/// On my own Posts tab, above the grid: the posts the photo check has hidden,
/// each with an "Under review" (or "Removed") label, so I know why nobody
/// else sees them. Empty when there are none.
class UnderReviewStrip extends StatelessWidget {
  const UnderReviewStrip({super.key, required this.posts, required this.states});
  final List<Post> posts;
  final Map<String, ModerationState> states;

  @override
  Widget build(BuildContext context) {
    final hidden = [for (final p in posts) if (states[p.id]?.hidden ?? false) p];
    if (hidden.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Column(
        children: [for (final p in hidden) _Row(post: p, state: states[p.id]!)],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.post, required this.state});
  final Post post;
  final ModerationState state;

  @override
  Widget build(BuildContext context) {
    final removed = state == ModerationState.removed;
    final cover = post.cover;
    final text = (post.title ?? post.caption ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => context.push(Routes.post(post.id)),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: cover == null ? ColoredBox(color: AppColors.border) : ThumbImage(cover, error: ColoredBox(color: AppColors.border)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        key: Key('under-review-${post.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: removed ? AppColors.danger : AppColors.textPrimary, borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(removed ? AppIcons.prohibit : AppIcons.hourglass, size: 12, color: removed ? Colors.white : AppColors.bg),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                removed ? 'Removed' : 'Under review',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: removed ? Colors.white : AppColors.bg),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        removed ? 'Our team removed this post. Only you can see it.' : 'Only you can see this until our team checks it.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, height: 1.3, color: AppColors.textSecondary),
                      ),
                      if (text.isNotEmpty)
                        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(AppIcons.caretRight, size: 14, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
