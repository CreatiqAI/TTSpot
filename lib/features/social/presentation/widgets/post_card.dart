import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/pop_icon.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../safety/data/safety_repository.dart';
import '../../../safety/presentation/report_sheet.dart';
import '../../application/social_providers.dart';
import '../../domain/post.dart';
import '../share_sheet.dart';
import 'poll_widget.dart';

/// Instagram feed card. [expanded] shows the full caption (post detail).
class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.feed, this.expanded = false, this.onOpen, this.onComment});
  final FeedPost feed;
  final bool expanded;
  final VoidCallback? onOpen;
  /// On the post page: focus the comment box instead of reopening the post.
  final VoidCallback? onComment;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  int _page = 0;
  bool _showFullCaption = false;
  bool _heartBurst = false;
  // Optimistic like / save so the icon pops the instant you tap, not after the round trip.
  bool? _liked;
  bool? _saved;

  bool get _isLiked => _liked ?? widget.feed.likedByMe;
  bool get _isSaved => _saved ?? widget.feed.savedByMe;
  int get _likeCount => widget.feed.post.likeCount + (_isLiked == widget.feed.likedByMe ? 0 : (_isLiked ? 1 : -1));

  @override
  void didUpdateWidget(covariant PostCard old) {
    super.didUpdateWidget(old);
    if (old.feed.likedByMe != widget.feed.likedByMe) _liked = null;
    if (old.feed.savedByMe != widget.feed.savedByMe) _saved = null;
  }

  Future<void> _toggleLike() async {
    final was = _isLiked;
    setState(() => _liked = !was);
    try {
      await ref.read(socialActionsProvider).toggleLike(widget.feed);
    } catch (e) {
      if (mounted) {
        setState(() => _liked = null);
        _snack(friendlyError(e));
      }
    }
  }

  Future<void> _toggleSave() async {
    final was = _isSaved;
    setState(() => _saved = !was);
    try {
      await ref.read(socialActionsProvider).toggleSave(widget.feed);
    } catch (e) {
      if (mounted) {
        setState(() => _saved = null);
        _snack(friendlyError(e));
      }
    }
  }

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
    if (!_isLiked) await _toggleLike();
  }

  Future<void> _menu() async {
    final f = widget.feed;
    final me = ref.read(currentUserIdProvider);
    final mine = f.post.authorId == me;
    final action = await showModalBottomSheet<String>(
      useRootNavigator: true, // above the shell tab bar
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
    // Posted as a club or a partner: that is the face of the post, the person is a byline.
    final club = p.asClub ? p.club : (p.asVendor ? p.vendor : null);
    final headRoute = p.asVendor && p.vendor != null ? Routes.partner(p.vendor!.id) : club != null ? Routes.club(club.id) : Routes.profile(p.authorId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => context.push(headRoute),
                child: club != null
                    ? UserAvatar(url: club.avatarUrl, name: club.name, size: 34, borderColor: AppColors.brand)
                    : UserAvatar(url: author?.avatarUrl, name: author?.displayName ?? username, size: 34),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.push(headRoute),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(club?.name ?? username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                          if (club != null) ...[
                            const SizedBox(width: 4),
                            const Icon(AppIcons.sealCheck, size: 14, color: AppColors.brand),
                          ],
                        ],
                      ),
                      club != null
                          ? Text('by @$username', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
                          : _Subtitle(post: p),
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
                icon: PopIcon(active: _isLiked, child: Icon(_isLiked ? AppIcons.heartFill : AppIcons.heart, color: _isLiked ? AppColors.danger : AppColors.textPrimary, size: 26)),
                onPressed: _toggleLike,
              ),
              IconButton(
                icon: const Icon(AppIcons.chatCircle, size: 24),
                onPressed: widget.onComment ?? widget.onOpen ?? () => context.push(Routes.post(p.id)),
              ),
              IconButton(
                tooltip: 'Send to a friend',
                icon: const Icon(AppIcons.paperPlaneTilt, size: 24),
                onPressed: () => showShareSheet(context, postId: p.id),
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
                icon: PopIcon(active: _isSaved, child: Icon(_isSaved ? AppIcons.bookmarkSimpleFill : AppIcons.bookmarkSimple, size: 26)),
                onPressed: _toggleSave,
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
              if (_likeCount > 0)
                GestureDetector(
                  onTap: () => _showLikers(context, p.id),
                  child: Text('$_likeCount ${_likeCount == 1 ? 'like' : 'likes'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              if ((p.caption ?? '').trim().isNotEmpty || p.title != null) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => setState(() => _showFullCaption = true),
                  child: RichText(
                    maxLines: widget.expanded || _showFullCaption ? null : 3,
                    overflow: widget.expanded || _showFullCaption ? TextOverflow.visible : TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
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
                  child: Text('View all ${p.commentCount} comments', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                ),
              ],
              const SizedBox(height: 4),
              Text(timeAgo(p.createdAt), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  void _showLikers(BuildContext context, String postId) {
    showModalBottomSheet<void>(
      useRootNavigator: true, // above the shell tab bar
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
    // Each tagged thing is a link: the car, the spot, the meet, the club.
    final parts = <(String, String?)>[];
    switch (post.kind) {
      case PostKind.spotted:
        parts.add(('👀 Spotted', null));
      case PostKind.poll:
        parts.add(('📊 Poll', null));
      case PostKind.guide:
        parts.add(('🗺️ Guide', null));
      case PostKind.post:
        break;
    }
    if (post.car != null) parts.add(('🚗 ${post.car!.title}', Routes.car(post.car!.id)));
    if (post.place != null) parts.add(('📍 ${post.place!.name}', Routes.place(post.place!.id)));
    if (post.event != null) parts.add(('🏁 ${post.event!.name}', Routes.event(post.event!.id)));
    if (post.club != null && !post.asClub) parts.add(('🛡️ ${post.club!.name}', Routes.club(post.club!.id)));
    if (parts.isEmpty) return SizedBox.shrink();
    final style = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) Text(' · ', style: style),
          GestureDetector(
            onTap: parts[i].$2 == null ? null : () => context.push(parts[i].$2!),
            child: Text(parts[i].$1, style: parts[i].$2 == null ? style : style.copyWith(fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: AppColors.border)),
          ),
        ],
      ],
    );
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
                loadingBuilder: (_, child, prog) => prog == null ? child : ColoredBox(color: AppColors.surfaceGray),
                errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.imageBroken, color: AppColors.textMuted)),
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
            Icon(AppIcons.path, color: AppColors.textPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.title ?? 'Guide', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(stops.isEmpty ? 'Tap to read' : '${stops.length} stop${stops.length == 1 ? '' : 's'} · ${stops.map((s) => s.name).join(' → ')}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(AppIcons.caretRight, color: AppColors.textMuted),
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
                      style: TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
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
