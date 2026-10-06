import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/photo_viewer.dart';
import '../../../../core/widgets/pinch_zoom.dart';
import '../../../../core/widgets/pop_icon.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/video_viewer.dart';
import '../../../../core/directions/directions.dart';
import '../../../safety/data/safety_repository.dart';
import '../../../safety/presentation/report_sheet.dart';
import '../../application/social_providers.dart';
import '../../domain/post.dart';
import '../share_sheet.dart';
import 'club_name_tag.dart';
import 'my_post_stats.dart';
import 'poll_widget.dart';
import 'rich_caption.dart';
import 'video_badge.dart';
import '../../../../core/utils/share_links.dart';

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
            ListTile(leading: const Icon(AppIcons.shareFat), title: const Text('Share link'), onTap: () => Navigator.pop(ctx, 'share')),
            if (mine)
              ListTile(
                leading: const Icon(AppIcons.trash, color: AppColors.danger),
                title: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              )
            else ...[
              ListTile(
                leading: const Icon(AppIcons.eyeSlash),
                title: const Text('Not interested'),
                subtitle: const Text('Show me fewer posts like this'),
                onTap: () => Navigator.pop(ctx, 'not_interested'),
              ),
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
      case 'share':
        await shareThing(type: 'post', id: f.post.id, text: 'Post by @${f.post.author?.username ?? 'someone'} on TT Spot');
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
      case 'not_interested':
        await _guard(() async {
          await actions.notInterested(f);
          if (mounted) _snack("Got it. You'll see fewer posts like this.");
        });
      case 'report':
        await showReportSheet(context, target: ReportTarget.post, targetId: f.post.id);
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
                    : UserAvatar(url: author?.avatarUrl, name: author?.displayName ?? username, seed: author?.id, size: 34),
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
                          ] else if (author?.clubTag != null) ...[
                            // Official club tag: the president's, or a member's who wears it.
                            const SizedBox(width: 6),
                            ClubNameTag(tag: author!.clubTag),
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
        if (p.isVideo)
          _Media(
            post: p,
            page: 0,
            onPage: (_) {},
            onDoubleTap: _doubleTapLike,
            burst: _heartBurst,
            whole: widget.expanded,
            // A video plays full screen, from the feed and from the post page.
            onTap: () => showVideoViewer(context, url: p.videoUrl!, posterUrl: p.videoPoster, aspectRatio: p.coverAspect),
          )
        else if (p.photoUrls.isNotEmpty)
          _Media(
            post: p,
            page: _page,
            onPage: (i) => setState(() => _page = i),
            onDoubleTap: _doubleTapLike,
            burst: _heartBurst,
            whole: widget.expanded,
            // On the post page a tap opens the photos full screen.
            onTap: widget.expanded ? () => showPhotoViewer(context, p.photoUrls, initial: _page) : widget.onOpen,
          ),
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
              if (p.photoUrls.length > 1 && !p.isVideo)
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
                // #tags and @mentions are links; "… more" opens the rest in place.
                RichCaption(
                  text: p.caption ?? '',
                  maxLines: widget.expanded ? null : 3,
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
                  leading: [
                    TextSpan(text: '$username ', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (p.kind == PostKind.guide && p.title != null) TextSpan(text: '${p.title}\n', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
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
              // My own post's page: views, saves, shares (only I see them).
              if (widget.expanded) MyPostStatsRow(post: p),
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
                      leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, seed: p.id, size: 40),
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
    final parts = <(String, VoidCallback?)>[];
    void link(String label, String route) => parts.add((label, () => context.push(route)));
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
    if (post.car != null) link('🚗 ${post.car!.title}', Routes.car(post.car!.id));
    if (post.place != null) {
      link('📍 ${post.place!.name}', Routes.place(post.place!.id));
    } else if ((post.placeName ?? '').isNotEmpty) {
      // A place from the address search opens directions; "Near <area>" is
      // only an area, so it is not a link.
      final at = post.latLng;
      final named = at != null && (post.placeAddress ?? '').isNotEmpty;
      parts.add(('📍 ${post.placeName}', named ? () => openDirections(context, lat: at.latitude, lng: at.longitude, label: post.placeName) : null));
    }
    if (post.event != null) link('🏁 ${post.event!.name}', Routes.event(post.event!.id));
    if (post.club != null && !post.asClub) link('🛡️ ${post.club!.name}', Routes.club(post.club!.id));
    if (parts.isEmpty) return SizedBox.shrink();
    final style = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) Text(' · ', style: style),
          GestureDetector(
            onTap: parts[i].$2,
            child: Text(parts[i].$1, style: parts[i].$2 == null ? style : style.copyWith(fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: AppColors.border)),
          ),
        ],
      ],
    );
  }
}

/// The photos. The feed crops them to fill a 0.8 to 1.91 box; [whole] (the
/// post page) allows a taller box and shows every photo uncropped on a grey
/// backdrop, so phone screenshots keep their top and bottom.
class _Media extends StatelessWidget {
  const _Media({required this.post, required this.page, required this.onPage, required this.onDoubleTap, required this.burst, this.whole = false, this.onTap});
  final Post post;
  final int page;
  final ValueChanged<int> onPage;
  final VoidCallback onDoubleTap;
  final bool burst;
  final bool whole;
  final VoidCallback? onTap;

  /// Post page chrome around the photo: the author row above it, and below
  /// it the whole rest of the post (like/comment row, likes, a few caption
  /// lines, the time) plus the comment bar.
  static const _authorRow = 66.0;
  static const _belowPhoto = 250.0;

  /// Post page: the tallest the photo box can be while the whole post still
  /// fits on one screen, and never more than about half the screen (a tap
  /// opens the full-screen viewer for detail). Read from the view, not the
  /// page's MediaQuery, so the keyboard coming up for a comment does not
  /// shrink the photo.
  static double _fitHeight(BuildContext context) {
    final screen = MediaQueryData.fromView(View.of(context));
    final fit = screen.size.height - screen.viewPadding.vertical - kToolbarHeight - _authorRow - _belowPhoto;
    return math.max(math.min(fit, screen.size.height * 0.52), 220);
  }

  @override
  Widget build(BuildContext context) {
    final aspect = whole ? post.coverAspect.clamp(0.56, 1.91) : post.coverAspect.clamp(0.8, 1.91);
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      onTap: onTap,
      child: whole
          // A phone screenshot on the post page would run off screen at its
          // own aspect, so its box stops at the screen and the photo sits
          // whole inside it. Wide photos keep their aspect.
          ? LayoutBuilder(builder: (context, c) => SizedBox(height: math.min(c.maxWidth / aspect, _fitHeight(context)), child: _stack()))
          : AspectRatio(aspectRatio: aspect, child: _stack()),
    );
  }

  Widget _stack() => Stack(
        fit: StackFit.expand,
        children: [
          if (post.isVideo)
            ..._video()
          else ...[
            if (whole) ColoredBox(color: AppColors.surfaceGray),
            ..._photos(),
          ],
          IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: burst ? 1 : 0,
              child: const Center(child: Icon(AppIcons.heartFill, color: Colors.white, size: 96, shadows: [Shadow(color: Colors.black38, blurRadius: 16)])),
            ),
          ),
        ],
      );

  /// A video post: its still with a play button and the length; a tap plays
  /// it full screen.
  List<Widget> _video() {
    final poster = post.videoPoster;
    return [
      const ColoredBox(color: Colors.black),
      if (poster != null)
        Image(
          image: CachedNetworkImageProvider(poster),
          fit: whole ? BoxFit.contain : BoxFit.cover,
          loadingBuilder: (_, child, prog) => prog == null ? child : const SizedBox.shrink(),
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      Center(
        child: Semantics(
          button: true,
          label: 'Play video',
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            child: const Icon(AppIcons.playFill, color: Colors.white, size: 30),
          ),
        ),
      ),
      Positioned(right: 10, bottom: 10, child: VideoBadge(ms: post.videoMs)),
    ];
  }

  List<Widget> _photos() => [
          PageView.builder(
            itemCount: post.photoUrls.length,
            onPageChanged: onPage,
            // Holds still while a photo is pinched (see PinchZoom).
            pageSnapping: false,
            physics: const PinchLockScrollPhysics(parent: PageScrollPhysics()),
            itemBuilder: (_, i) => PinchZoom(
              child: Image(image: CachedNetworkImageProvider(post.photoUrls[i]),
                fit: whole ? BoxFit.contain : BoxFit.cover,
                loadingBuilder: (_, child, prog) => prog == null ? child : ColoredBox(color: AppColors.surfaceGray),
                errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.imageBroken, color: AppColors.textMuted)),
              ),
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
        ];
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
