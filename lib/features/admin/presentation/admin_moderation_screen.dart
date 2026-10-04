import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart' show confirmSheet;
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/thumb_image.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/admin_moderation.dart';

/// Admins only: posts and moments the automatic photo check flagged. They
/// are hidden from everyone but the author until Approve (shown again) or
/// Remove (stays hidden). Photos start blurred; tap to look.
class AdminModerationScreen extends ConsumerWidget {
  const AdminModerationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(adminFlaggedProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Flagged posts'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminFlaggedProvider);
          await ref.read(adminFlaggedProvider.future);
        },
        child: queue.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (list) => list.isEmpty
              ? LayoutBuilder(
                  builder: (_, c) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: c.maxHeight,
                      child: EmptyState(art: AppArt.check, title: 'Nothing flagged', subtitle: 'Posts and moments the photo check hides show up here.'),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.only(top: 4, bottom: 32 + MediaQuery.paddingOf(context).bottom),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 24),
                  itemBuilder: (_, i) => FlaggedCard(key: ValueKey(list[i].id), item: list[i]),
                ),
        ),
      ),
    );
  }
}

class FlaggedCard extends ConsumerStatefulWidget {
  const FlaggedCard({super.key, required this.item});
  final FlaggedItem item;

  @override
  ConsumerState<FlaggedCard> createState() => _FlaggedCardState();
}

class _FlaggedCardState extends ConsumerState<FlaggedCard> {
  bool _busy = false;
  bool _shown = false;

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _decide(bool approve) async {
    final item = widget.item;
    final what = item.isPost ? 'post' : 'moment';
    if (!approve) {
      final ok = await confirmSheet(
        context,
        title: 'Remove this $what?',
        body: 'It stays hidden from everyone. @${item.username} sees it marked as removed.',
        confirm: 'Remove',
        icon: AppIcons.trash,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final v = await ref.read(adminModerationActionsProvider).decide(item, approve: approve);
      if (mounted) _snack(v == null ? 'It was deleted already.' : (approve ? 'Approved. Everyone can see it again.' : 'Removed.'));
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final text = [if ((item.title ?? '').trim().isNotEmpty) item.title!.trim(), if ((item.caption ?? '').trim().isNotEmpty) item.caption!.trim()].join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: UserAvatar(url: item.avatarUrl, name: item.username, seed: item.authorId, size: 40),
          title: Text('@${item.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${item.isPost ? (item.isVideo ? 'Video post' : 'Post') : (item.isVideo ? 'Video moment' : 'Moment')} · ${timeAgo(item.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: item.hits.isEmpty
              ? null
              : Container(
                  constraints: const BoxConstraints(maxWidth: 130),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
                  child: Text(item.hits.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
          onTap: () => context.push(Routes.profile(item.authorId)),
        ),
        if (item.photoUrls.isNotEmpty)
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: item.photoUrls.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                key: Key('flagged-photo-${item.id}-$i'),
                onTap: () => setState(() => _shown = !_shown),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    width: item.photoUrls.length == 1 ? MediaQuery.sizeOf(context).width - 32 : 150,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          enabled: !_shown,
                          imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: ThumbImage(item.photoUrls[i], error: ColoredBox(color: AppColors.surfaceGray)),
                        ),
                        if (!_shown)
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(AppIcons.eye, size: 14, color: Colors.white),
                                  SizedBox(width: 5),
                                  Flexible(child: Text('Tap to show', maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (text.isNotEmpty) ...[
                Text(text, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.35, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
              ],
              if ((item.reason ?? '').isNotEmpty)
                Text(item.reason!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.isPost)
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: _busy ? null : () => context.push(Routes.post(item.id)),
                      child: const Text('Open'),
                    ),
                  // Wraps onto two lines on a small phone with big text.
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          key: Key('flagged-remove-${item.id}'),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.danger),
                          onPressed: _busy ? null : () => _decide(false),
                          child: const Text('Remove'),
                        ),
                        FilledButton(
                          key: Key('flagged-approve-${item.id}'),
                          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 16)),
                          onPressed: _busy ? null : () => _decide(true),
                          child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Approve'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
