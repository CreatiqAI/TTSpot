import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/tags_providers.dart';
import '../../domain/post.dart';

/// On my own post's page: "128 views · 12 saves · 3 shares". Nothing for
/// anyone else's post (the server only tells the author).
class MyPostStatsRow extends ConsumerWidget {
  const MyPostStatsRow({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentUserIdProvider) != post.authorId) return const SizedBox.shrink();
    final stats = ref.watch(myPostStatsProvider(post.id)).value;
    if (stats == null) return const SizedBox.shrink();
    return Semantics(
      label: 'Only you see this: ${stats.summary}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(AppIcons.chartBar, size: 14, color: AppColors.textSecondary)),
            const SizedBox(width: 6),
            Expanded(child: Text(stats.summary, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
          ],
        ),
      ),
    );
  }
}

/// On my own post's grid tile, in place of my name (my own grid is all me):
/// an eye and how many have seen it. Anyone else's tile shows [otherwise].
class MyViewCount extends ConsumerWidget {
  const MyViewCount({super.key, required this.post, required this.otherwise});
  final Post post;
  final Widget otherwise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentUserIdProvider) != post.authorId) return otherwise;
    final stats = ref.watch(myPostStatsProvider(post.id)).value;
    if (stats == null) return otherwise;
    final noun = stats.views == 1 ? 'view' : 'views';
    return Semantics(
      label: '${stats.views} $noun',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(AppIcons.eye, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 3),
          Flexible(
            child: Text('${stats.viewsShort} $noun', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
