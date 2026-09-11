import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../safety/data/safety_repository.dart';
import '../../../safety/presentation/report_sheet.dart';
import '../../application/social_providers.dart';
import '../../domain/post.dart';
import 'poll_widget.dart';

/// Instagram feed card. [expanded] shows the full caption (post detail).
class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.feed, this.expanded = false, this.onOpen});
  final FeedPost feed;
  final bool expanded;
  final VoidCallback? onOpen;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  int _page = 0;
  bool _showFullCaption = false;
  bool _heartBurst = false;

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  Future<void> _doubleTapLike() async {
    setState(() => _heartBurst = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _heartBurst = false);
    });
    if (!widget.feed.likedByMe) await _guard(() => ref.read(socialActionsProvider).toggleLike(widget.feed));
  }

  Future<void> _menu() async {
    final f = widget.feed;
    final me = ref.read(currentUserIdProvider);
    final mine = f.post.authorId == me;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (f.post.kind == PostKind.spotted && !mine && f.post.claimedBy == null)
              ListTile(leading: const Icon(AppIcons.car), title: const Text('That\'s my car! Claim it'), onTap: () => Navigator.pop(ctx, 'claim')),
            ListTile(
              leading: Icon(f.savedByMe ? AppIcons.bookmarkSimpleFill : AppIcons.bookmarkSimple),
              title: Text(f.savedByMe ? 'Unsave' : 'Save'),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            if (mine)
              ListTile(
                leading: const Icon(AppIcons.trash, color: AppColors.danger),
                title: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              )
            else ...[
              ListTile(leading: const Icon(AppIcons.flag), title: const Text('Report'), onTap: () => Navigator.pop(ctx, 'report')),
              ListTile(
                leading: const Icon(AppIcons.prohibit, color: AppColors.danger),
                title: Text('Block @${f.post.author?.username ?? 'user'}', style: const TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(ctx, 'block'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final actions = ref.read(socialActionsProvider);
    switch (action) {
      case 'claim':
        await _guard(() => actions.claimSpotted(f));
      case 'save':
        await _guard(() => actions.toggleSave(f));
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete post?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
            ],
          ),
        );
        if (ok == true) await _guard(() => actions.deletePost(f));
      case 'report':
        await showReportSheet(context, target: ReportTarget.comment, targetId: f.post.id);
      case 'block':
        await confirmBlockUser(context, ref, userId: f.post.authorId, displayName: '@${f.post.author?.username ?? 'user'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.feed;
    final p = f.post;
    final author = p.author;
    final username = author?.username ?? 'user';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => context.push(Routes.profile(p.authorId)),
                child: UserAvatar(url: author?.avatarUrl, name: author?.displayName ?? username, size: 34),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.push(Routes.profile(p.authorId)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(username, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      _Subtitle(post: p),
                    ],
                  ),
                ),
              ),
              IconButton(icon: const Icon(AppIcons.dotsThree), onPressed: _menu),
            ],
          ),
        ),

        // ---- media / body
        if (p.photoUrls.isNotEmpty) _Media(post: p, page: _page, onPage: (i) => setState(() => _page = i), onDoubleTap: _doubleTapLike, burst: _heartBurst, onTap: widget.onOpen),
        if (p.kind == PostKind.poll) Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 4), child: PollWidget(feed: f)),
        if (p.kind == PostKind.guide) _GuideStrip(post: p, onTap: widget.onOpen),
        if (p.kind == PostKind.spotted) _SpottedStrip(feed: f, onClaim: () => _guard(() => ref.read(socialActionsProvider).claimSpotted(f))),

        // ---- actions
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: Row(
            children: [
              IconButton(
                icon: Icon(f.likedByMe ? AppIcons.heartFill : AppIcons.heart, color: f.likedByMe ? AppColors.danger : AppColors.textPrimary, size: 26),
                onPressed: () => _guard(() => ref.read(socialActionsProvider).toggleLike(f)),
              ),
              IconButton(
                icon: const Icon(AppIcons.chatCircle, size: 24),
                onPressed: widget.onOpen ?? () => context.push(Routes.post(p.id)),
              ),
              if (p.kind == PostKind.spotted && p.latLng != null)
                IconButton(
                  icon: const Icon(AppIcons.mapPin, size: 25),
                  onPressed: () => context.go(Routes.map),
                ),
              const Spacer(),
              if (p.photoUrls.length > 1)
                Row(
                  children: [
                    for (var i = 0; i < p.photoUrls.length; i++)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? AppColors.primary : AppColors.border),
                      ),
                  ],
                ),
              const Spacer(),
              IconButton(
                icon: Icon(f.savedByMe ? AppIcons.bookmarkSimpleFill : AppIcons.bookmarkSimple, size: 26),
                onPressed: () => _guard(() => ref.read(socialActionsProvider).toggleSave(f)),
              ),
            ],
          ),
        ),

        // ---- likes, caption, comments, time
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.likeCount > 0)
                GestureDetector(
                  onTap: () => _showLikers(context, p.id),
                  child: Text('${p.likeCount} ${p.likeCount == 1 ? 'like' : 'likes'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              if ((p.caption ?? '').trim().isNotEmpty || p.title != null) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => setState(() => _showFullCaption = true),
                  child: RichText(
                    maxLines: widget.expanded || _showFullCaption ? null : 3,
                    overflow: widget.expanded || _showFullCaption ? TextOverflow.visible : TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
                      children: [
                        TextSpan(text: '$username ', style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (p.kind == PostKind.guide && p.title != null) TextSpan(text: '${p.title}\n', style: const TextStyle(fontWeight: FontWeight.w600)),
                        TextSpan(text: p.caption ?? ''),
                      ],
                    ),
                  ),
                ),
              ],
              if (!widget.expanded && p.commentCount > 0) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: widget.onOpen ?? () => context.push(Routes.post(p.id)),
                  child: Text('View all ${p.commentCount} comments', style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                ),
              ],
              const SizedBox(height: 4),
              Text(timeAgo(p.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  void _showLikers(BuildContext context, String postId) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Consumer(
        builder: (ctx, ref, _) {
          final likers = ref.watch(postLikersProvider(postId));
          return SafeArea(
            child: likers.when(
              loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e))),
              data: (list) => ListView(
                shrinkWrap: true,
                children: [
                  const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Likes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  for (final p in list)
                    ListTile(
                      leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, size: 40),
                      title: Text(p.username ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(p.displayName ?? ''),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push(Routes.profile(p.id));
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    switch (post.kind) {
      case PostKind.spotted:
        parts.add('👀 Spotted');
      case PostKind.poll:
        parts.add('📊 Poll');
      case PostKind.guide:
        parts.add('🗺️ Guide');
      case PostKind.post:
        break;
    }
    if (post.car != null) parts.add('🚗 ${post.car!.title}');
    if (post.place != null) parts.add('📍 ${post.place!.name}');
    if (post.event != null) parts.add('🏁 ${post.event!.name}');
    if (post.club != null) parts.add('🛡️ ${post.club!.name}');
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary));
  }
}

class _Media extends StatelessWidget {
  const _Media({required this.post, required this.page, required this.onPage, required this.onDoubleTap, required this.burst, this.onTap});
  final Post post;
  final int page;
  final ValueChanged<int> onPage;
  final VoidCallback onDoubleTap;
  final bool burst;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final aspect = post.coverAspect.clamp(0.8, 1.91);
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              itemCount: post.photoUrls.length,
              onPageChanged: onPage,
              itemBuilder: (_, i) => Image.network(
                post.photoUrls[i],
                fit: BoxFit.cover,
                loadingBuilder: (_, child, prog) => prog == null ? child : const ColoredBox(color: AppColors.surfaceGray),
                errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.imageBroken, color: AppColors.textMuted)),
              ),
            ),
            if (post.photoUrls.length > 1)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                  child: Text('${page + 1}/${post.photoUrls.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: burst ? 1 : 0,
                child: const Center(child: Icon(AppIcons.heartFill, color: Colors.white, size: 96, shadows: [Shadow(color: Colors.black38, blurRadius: 16)])),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideStrip extends StatelessWidget {
  const _GuideStrip({required this.post, this.onTap});
  final Post post;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stops = post.guideStops ?? const [];
    return InkWell(
      onTap: onTap ?? () => context.push(Routes.post(post.id)),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.border)),
        child: Row(
          children: [
            const Icon(AppIcons.path, color: AppColors.textPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.title ?? 'Guide', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(stops.isEmpty ? 'Tap to read' : '${stops.length} stop${stops.length == 1 ? '' : 's'} · ${stops.map((s) => s.name).join(' → ')}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(AppIcons.caretRight, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _SpottedStrip extends ConsumerWidget {
  const _SpottedStrip({required this.feed, required this.onClaim});
  final FeedPost feed;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = feed.post;
    final me = ref.watch(currentUserIdProvider);
    final claimed = p.claimedBy != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          const Text('👀', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: claimed
                ? RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
                      children: [
                        const TextSpan(text: 'Claimed by '),
                        TextSpan(text: '@${p.claimer?.username ?? 'owner'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )
                : const Text('Spotted in the wild. Is this your car?', style: TextStyle(fontSize: 13.5)),
          ),
          if (!claimed && p.authorId != me)
            TextButton(onPressed: onClaim, style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)), child: const Text('That\'s mine')),
        ],
      ),
    );
  }
}
