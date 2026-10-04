import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../map/presentation/widgets/static_pin_map.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/pinch_zoom.dart';
import '../application/comment_providers.dart';
import '../application/social_providers.dart';
import '../domain/post.dart';
import 'comments/comment_composer.dart';
import 'comments/comment_list.dart';
import 'comments/comments_controller.dart';
import 'widgets/masonry_grid.dart';
import 'widgets/post_card.dart';
import 'widgets/seen_tracker.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId, this.highlightCommentId});
  final String postId;

  /// From a notification about a comment (/post/:id?comment=…): scroll to it
  /// and light it up.
  final String? highlightCommentId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  late final _comments = CommentsController(highlightId: widget.highlightCommentId);

  // How long the post stays open feeds the ranking (sent on leaving).
  final _openedAt = DateTime.now();
  late final FeedSignals _signals;

  @override
  void initState() {
    super.initState();
    _signals = ref.read(feedSignalsProvider);
  }

  @override
  void dispose() {
    _signals.opened(widget.postId, DateTime.now().difference(_openedAt));
    _comments.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = ref.watch(postProvider(widget.postId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(post.value?.post.kind.label ?? 'Post'),
      ),
      body: post.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (f) {
          if (f == null) return const Center(child: Text('This post is gone.'));
          return Column(
            children: [
              Expanded(
                child: SeenScope(
                  onSeen: _signals.seen,
                  child: RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(postProvider(widget.postId));
                      ref.invalidate(postCommentItemsProvider(widget.postId));
                      ref.invalidate(relatedPostsProvider(widget.postId));
                      await ref.read(postProvider(widget.postId).future);
                    },
                    child: ListView(
                      padding: EdgeInsets.zero,
                      physics: const PinchLockScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      children: [
                        PostCard(feed: f, expanded: true, onComment: _comments.startComment),
                        if (f.post.kind == PostKind.guide && (f.post.guideStops ?? const []).isNotEmpty) _GuideMap(post: f.post),
                        if (f.post.kind == PostKind.spotted && f.post.latLng != null) _SpottedMap(post: f.post),
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: CommentList(postId: widget.postId, controller: _comments),
                        ),
                        _MoreLikeThis(postId: widget.postId),
                      ],
                    ),
                  ),
                ),
              ),
              CommentComposer(postId: widget.postId, controller: _comments),
            ],
          );
        },
      ),
    );
  }
}

/// RedNote-style "More like this" under the comments: same car, make,
/// spot, meet or driver first (related_posts in migration 0094).
class _MoreLikeThis extends ConsumerWidget {
  const _MoreLikeThis({required this.postId});
  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final related = ref.watch(relatedPostsProvider(postId)).value ?? const <FeedPost>[];
    if (related.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Text('More like this', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ),
        MasonryGrid(items: related),
      ],
    );
  }
}

class _GuideMap extends StatelessWidget {
  const _GuideMap({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final stops = post.guideStops!;
    final points = stops.map((s) => s.latLng).toList();
    var south = points.first.latitude, north = points.first.latitude, west = points.first.longitude, east = points.first.longitude;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              height: 220,
              child: StaticPinMap(points: points, labels: [for (var i = 0; i < stops.length; i++) '${i + 1}. ${stops[i].name}'], zoom: 10.5, route: true),
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < stops.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(radius: 11, backgroundColor: AppColors.textPrimary, child: Text('${i + 1}', style: TextStyle(color: AppColors.onInk, fontSize: 11, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(stops[i].name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SpottedMap extends StatelessWidget {
  const _SpottedMap({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          height: 160,
          child: StaticPinMap(points: [post.latLng!], zoom: 14),
        ),
      ),
    );
  }
}
