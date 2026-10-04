import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/open_external.dart' show confirmSheet;
import '../../../../core/widgets/user_avatar.dart';
import '../../../safety/data/safety_repository.dart';
import '../../../safety/presentation/report_sheet.dart';
import '../../application/comment_providers.dart';
import '../../domain/comment_thread.dart';
import '../widgets/rich_caption.dart';
import 'comments_controller.dart';

/// The comments under a post, Instagram style: each top-level comment with
/// its replies indented below it (folded behind "View N replies" past two),
/// a heart with a count on every comment, Reply under each one.
class CommentList extends ConsumerStatefulWidget {
  const CommentList({super.key, required this.postId, required this.controller});
  final String postId;
  final CommentsController controller;

  @override
  ConsumerState<CommentList> createState() => _CommentListState();
}

class _CommentListState extends ConsumerState<CommentList> {
  /// Hearts tapped on this visit, ahead of the server: comment id → liked.
  final _liked = <String, bool>{};
  final _highlightKey = GlobalKey();
  // The comment the page opened on keeps its key after the tint fades, so
  // the fade animates instead of the tile being rebuilt.
  late final String? _keyed = widget.controller.highlightId;
  bool _scrolledToHighlight = false;
  Timer? _fade;

  CommentsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _fade?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _snack(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }

  bool _isLiked(CommentItem c) => _liked[c.id] ?? c.likedByMe;

  /// The count with my tap applied (the server's count may or may not have it yet).
  int _likes(CommentItem c) {
    final mine = _liked[c.id];
    if (mine == null || mine == c.likedByMe) return c.likeCount;
    return mine ? c.likeCount + 1 : (c.likeCount - 1).clamp(0, 1 << 30);
  }

  Future<void> _toggleLike(CommentItem c) async {
    final next = !_isLiked(c);
    setState(() => _liked[c.id] = next);
    try {
      await ref.read(commentActionsProvider).setLiked(c.id, next);
    } catch (e) {
      if (mounted) setState(() => _liked[c.id] = !next);
      _snack(e);
    }
  }

  void _reply(CommentItem c) => _c.reply(c, me: ref.read(currentUserIdProvider));

  Future<void> _menu(CommentItem c, List<CommentItem> all) async {
    final mine = c.userId == ref.read(currentUserIdProvider);
    final action = await showModalBottomSheet<String>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(AppIcons.arrowBendUpLeft), title: const Text('Reply'), onTap: () => Navigator.pop(ctx, 'reply')),
            if (mine)
              ListTile(leading: const Icon(AppIcons.trash, color: AppColors.danger), title: const Text('Delete comment', style: TextStyle(color: AppColors.danger)), onTap: () => Navigator.pop(ctx, 'delete'))
            else ...[
              ListTile(leading: const Icon(AppIcons.flag), title: const Text('Report comment'), onTap: () => Navigator.pop(ctx, 'report')),
              ListTile(leading: const Icon(AppIcons.prohibit, color: AppColors.danger), title: Text('Block @${c.handle}', style: const TextStyle(color: AppColors.danger)), onTap: () => Navigator.pop(ctx, 'block')),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'reply':
        _reply(c);
      case 'delete':
        final replies = c.isReply ? 0 : repliesUnder(c.id, all);
        if (replies > 0) {
          final ok = await confirmSheet(context, title: 'Delete this comment?', body: replies == 1 ? 'Its reply goes too.' : 'Its $replies replies go too.', confirm: 'Delete');
          if (!ok || !mounted) return;
        }
        try {
          await ref.read(commentActionsProvider).delete(widget.postId, c.id);
        } catch (e) {
          _snack(e);
        }
      case 'report':
        await showReportSheet(context, target: ReportTarget.postComment, targetId: c.id);
      case 'block':
        await confirmBlockUser(context, ref, userId: c.userId, displayName: '@${c.handle}');
    }
  }

  /// Once the comments are in: scroll the one a notification pointed at into
  /// view, unfold its thread, and let the tint fade after a moment.
  void _goToHighlight(List<CommentThread> threads) {
    final target = _c.highlightId;
    if (target == null || _scrolledToHighlight) return;
    _scrolledToHighlight = true;
    String? found;
    for (final t in threads) {
      if (t.top.id == target) found = t.top.id;
      for (final r in t.replies) {
        if (r.id == target) found = t.top.id;
      }
    }
    if (found == null) return;
    final String threadId = found;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _c.open(threadId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _highlightKey.currentContext;
        if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
      });
      WidgetsBinding.instance.scheduleFrame();
      _fade = Timer(const Duration(milliseconds: 2600), _c.clearHighlight);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(postCommentItemsProvider(widget.postId));
    return async.when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => Text(friendlyError(e)),
      data: (all) {
        final threads = buildThreads(all);
        if (threads.isEmpty) return Text('No comments yet.', style: TextStyle(color: AppColors.textSecondary));
        _goToHighlight(threads);
        final highlight = _c.highlightId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final t in threads) ...[
              _tile(t.top, all, highlight),
              if (t.replies.isNotEmpty) ...[
                if (!t.folds || _c.isOpen(t.top.id)) for (final r in t.replies) _tile(r, all, highlight),
                if (t.folds) _FoldRow(open: _c.isOpen(t.top.id), count: t.replies.length, onTap: () => _c.toggle(t.top.id)),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _tile(CommentItem c, List<CommentItem> all, String? highlight) => CommentTile(
        key: c.id == _keyed ? _highlightKey : ValueKey(c.id),
        comment: c,
        liked: _isLiked(c),
        likes: _likes(c),
        highlighted: c.id == highlight,
        onLike: () => _toggleLike(c),
        onReply: () => _reply(c),
        onMenu: () => _menu(c, all),
      );
}

/// "View 3 replies" / "Hide replies" under a long thread.
class _FoldRow extends StatelessWidget {
  const _FoldRow({required this.open, required this.count, required this.onTap});
  final bool open;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 44),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 24, height: 1, color: AppColors.border),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    open ? 'Hide replies' : 'View $count replies',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One comment: avatar, name and text, when · Reply, and a heart with its
/// count on the right. Replies sit indented with a smaller avatar.
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.liked,
    required this.likes,
    required this.onLike,
    required this.onReply,
    required this.onMenu,
    this.highlighted = false,
  });

  final CommentItem comment;
  final bool liked;
  final int likes;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback onMenu;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = comment;
    final reply = c.isReply;
    final meta = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return InkWell(
      onLongPress: onMenu,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: highlighted ? AppColors.primary.withValues(alpha: 0.08) : AppColors.primary.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        padding: EdgeInsets.fromLTRB(reply ? 44 : 0, 8, 0, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => context.push(Routes.profile(c.userId)),
              child: UserAvatar(url: c.author?.avatarUrl, name: c.author?.displayName ?? c.handle, seed: c.author?.id ?? c.userId, size: reply ? 24 : 32),
            ),
            SizedBox(width: reply ? 10 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // #tags and @mentions in a comment are links, like in captions.
                  RichCaption(
                    text: c.body,
                    style: TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
                    leading: [TextSpan(text: '${c.handle}  ', style: const TextStyle(fontWeight: FontWeight.w600))],
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 14,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(timeAgo(c.createdAt), style: meta),
                      GestureDetector(
                        onTap: onReply,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('Reply', style: meta.copyWith(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            _Heart(liked: liked, count: likes, onTap: onLike),
          ],
        ),
      ),
    );
  }
}

class _Heart extends StatelessWidget {
  const _Heart({required this.liked, required this.count, required this.onTap});
  final bool liked;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: liked,
      label: liked ? 'Unlike comment' : 'Like comment',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 36,
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(liked ? AppIcons.heartFill : AppIcons.heart, size: 16, color: liked ? AppColors.brand : AppColors.textSecondary),
                if (count > 0) ...[
                  const SizedBox(height: 2),
                  Text('$count', maxLines: 1, overflow: TextOverflow.visible, softWrap: false, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
