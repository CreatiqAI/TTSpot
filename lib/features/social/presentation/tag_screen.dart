import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/social_providers.dart';
import '../application/tags_providers.dart';
import '../domain/post.dart';
import '../domain/tags.dart';
import 'widgets/masonry_grid.dart';
import 'widgets/seen_tracker.dart';

/// "#myvi · 128 posts": every post with the tag, best first (engagement x
/// freshness, tag_posts), more as you scroll.
class TagScreen extends ConsumerStatefulWidget {
  const TagScreen({super.key, required this.tag});

  /// As it came in the link: "myvi", "#Myvi".
  final String tag;

  @override
  ConsumerState<TagScreen> createState() => _TagScreenState();
}

class _TagScreenState extends ConsumerState<TagScreen> {
  final _seen = GlobalKey<SeenScopeState>();

  String get _tag => normaliseTag(widget.tag) ?? widget.tag.replaceFirst(RegExp(r'^#+'), '').toLowerCase();
  PostQuery get _query => (kind: PostQueryKind.tag, text: _tag);

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 900) ref.read(pagedPostsProvider(_query).notifier).loadMore();
    return false;
  }

  Future<void> _reload() async {
    _seen.currentState?.reset();
    ref.invalidate(pagedPostsProvider(_query));
    await ref.read(pagedPostsProvider(_query).future);
  }

  @override
  Widget build(BuildContext context) {
    final tag = _tag;
    final feed = ref.watch(pagedPostsProvider(_query));
    final total = feed.value?.total;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        titleSpacing: 0,
        title: Row(
          children: [
            Flexible(child: Text('#$tag', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
            if (total != null)
              Text(' · ${postCountLabel(total)}', maxLines: 1, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
          ],
        ),
      ),
      body: SeenScope(
        key: _seen,
        onSeen: ref.read(feedSignalsProvider).seen,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: RefreshIndicator(
            onRefresh: _reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                feed.when(
                  loading: () => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                  error: (e, _) => SliverFillRemaining(hasScrollBody: false, child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e), textAlign: TextAlign.center)))),
                  data: (s) => s.items.isEmpty
                      ? SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                            titi: TitiPose.binoculars,
                            title: 'No #$tag posts yet',
                            subtitle: 'Put #$tag in a caption and your post shows up here.',
                            actionLabel: 'Create a post',
                            onAction: () => context.push(Routes.createPost(PostKind.post)),
                          ),
                        )
                      : SliverMainAxisGroup(
                          slivers: [
                            SliverToBoxAdapter(child: MasonryGrid(items: s.items)),
                            SliverToBoxAdapter(
                              child: s.done
                                  ? const SizedBox(height: 16)
                                  : const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                            ),
                          ],
                        ),
                ),
                SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
