import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/points_providers.dart';
import '../domain/verification.dart';

/// Admins only: sticker check-ins the AI couldn't decide (or never got to).
class AdminReviewScreen extends ConsumerWidget {
  const AdminReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(adminReviewQueueProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Review queue'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminReviewQueueProvider);
          await ref.read(adminReviewQueueProvider.future);
        },
        child: queue.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (list) => list.isEmpty
              ? LayoutBuilder(
                  builder: (_, c) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(height: c.maxHeight, child: const EmptyState(art: AppArt.check, title: 'Queue is empty', subtitle: 'Everything has been decided.')),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 24),
                  itemBuilder: (_, i) => _Card(v: list[i]),
                ),
        ),
      ),
    );
  }
}

class _Card extends ConsumerStatefulWidget {
  const _Card({required this.v});
  final SpotVerification v;

  @override
  ConsumerState<_Card> createState() => _CardState();
}

class _CardState extends ConsumerState<_Card> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    try {
      await ref.read(pointsActionsProvider).review(widget.v.id, approve: approve);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final ai = [
      if (v.aiCarPresent != null) v.aiCarPresent! ? 'car ✓' : 'no car',
      if (v.aiLooksReal != null) v.aiLooksReal! ? 'real photo ✓' : 'looks fake',
      if (v.aiConfidence != null) '${(v.aiConfidence! * 100).round()}% sure',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: UserAvatar(url: v.avatarUrl, name: v.username, size: 40),
          title: Text('@${v.username ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${v.placeName} · ${timeAgo(v.createdAt)}'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(6)),
            child: Text(v.status.label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
          onTap: v.userId == null ? null : () => context.push(Routes.profile(v.userId!)),
        ),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Image(image: CachedNetworkImageProvider(v.photoUrl), fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  if (v.distanceM != null) '${v.distanceM} m from the spot' else 'no GPS',
                  if (ai.isNotEmpty) ai,
                ].join(' · '),
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              if ((v.aiNote ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('AI: ${v.aiNote}', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
              ],
              if ((v.reason ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Held because: ${v.reason}', style: const TextStyle(fontSize: 13)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _decide(true),
                      icon: const Icon(AppIcons.check, size: 18),
                      label: const Text('Approve'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _decide(false),
                      icon: const Icon(AppIcons.x, size: 18),
                      label: const Text('Reject'),
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
