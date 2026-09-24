import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart' show confirmSheet;
import '../application/admin_providers.dart';
import 'admin_dashboard_screen.dart' show showSuggestionsSheet;

/// Admin · Queues: everything waiting for a decision, then reports with a
/// filter and a resolve-with-note action.
class AdminQueuesScreen extends ConsumerStatefulWidget {
  const AdminQueuesScreen({super.key});

  @override
  ConsumerState<AdminQueuesScreen> createState() => _AdminQueuesScreenState();
}

class _AdminQueuesScreenState extends ConsumerState<AdminQueuesScreen> {
  String _filter = 'open';

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(adminStatsProvider).value;
    final reports = ref.watch(adminReportsProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Queues'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(AppIcons.arrowsClockwise),
            onPressed: () {
              ref.invalidate(adminStatsProvider);
              ref.invalidate(adminReportsProvider);
              ref.invalidate(adminSuggestionsProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _Head('WAITING FOR YOU'),
          _Queue(icon: AppIcons.sealCheck, title: 'Spot photo reviews', subtitle: 'Sticker check-ins the AI was unsure about', count: stats?['pending_verifications'], onTap: () => context.push(Routes.adminReview)),
          _Queue(icon: AppIcons.handshake, title: 'Partner & club applications', subtitle: 'Approve to unlock hosting and vouchers', count: stats?['pending_partners'], onTap: () => context.push(Routes.adminPartners)),
          _Queue(icon: AppIcons.mapPinPlus, title: 'Spot suggestions', subtitle: 'Members proposing places for the map', count: stats?['pending_suggestions'], onTap: () => showSuggestionsSheet(context)),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
            child: Row(
              children: [
                Text('REPORTS', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
                const Spacer(),
                for (final f in const [('open', 'Open'), ('resolved', 'Resolved'), ('all', 'All')])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: _filter == f.$1,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _filter = f.$1),
                    ),
                  ),
              ],
            ),
          ),
          reports.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e))),
            data: (all) {
              final list = all.where((r) => switch (_filter) { 'open' => r.resolvedAt == null, 'resolved' => r.resolvedAt != null, _ => true }).toList();
              if (list.isEmpty) {
                return Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 12), child: Text('Nothing here. Nice.', style: TextStyle(color: AppColors.textSecondary)));
              }
              return Column(children: [for (final r in list) _ReportCard(r: r)]);
            },
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({required this.r});
  final AdminReport r;

  Future<void> _resolve(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve report'),
        content: TextField(controller: ctrl, maxLines: 3, autofocus: true, decoration: const InputDecoration(hintText: 'What did you do? (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Resolve')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(adminActionsProvider).resolveReport(r.id, note: ctrl.text.trim().isEmpty ? null : ctrl.text.trim());
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    try {
      await action();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await confirmSheet(context, title: 'Remove this ${_what(r.targetType)}?', body: 'It is deleted for everyone and the report is resolved.', confirm: 'Remove', icon: AppIcons.trash);
    if (!ok || !context.mounted) return;
    await _run(context, () => ref.read(adminActionsProvider).removeReported(r.id), 'Removed.');
  }

  Future<void> _suspend(BuildContext context, WidgetRef ref) async {
    final suspend = !r.ownerSuspended;
    final ok = await confirmSheet(
      context,
      title: suspend ? 'Suspend @${r.ownerUsername}?' : 'Restore @${r.ownerUsername}?',
      body: suspend ? "They are signed out and can't log in again until you restore them." : 'They can log in again.',
      confirm: suspend ? 'Suspend' : 'Restore',
      icon: AppIcons.prohibit,
    );
    if (!ok || !context.mounted) return;
    await _run(context, () => ref.read(adminActionsProvider).setSuspended(r.ownerId!, suspended: suspend), suspend ? 'Suspended.' : 'Restored.');
  }

  static String _what(String type) => switch (type) {
        'event' => 'meet',
        'comment' || 'post_comment' => 'comment',
        'story' => 'moment',
        _ => type,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = r.resolvedAt != null;
    final removed = r.targetLabel == '(removed)';
    final parent = r.parentId;
    final open = removed
        ? null
        : switch (r.targetType) {
            'profile' => () => context.push(Routes.profile(r.targetId)),
            'event' => () => context.push(Routes.event(r.targetId)),
            'post' => () => context.push(Routes.post(r.targetId)),
            'post_comment' when parent != null => () => context.push(Routes.post(parent)),
            'comment' when parent != null => () => context.push(Routes.event(parent)),
            'club' => () => context.push(Routes.club(r.targetId)),
            _ => null,
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(done ? AppIcons.checkCircle : AppIcons.flag, size: 18, color: done ? AppColors.success : AppColors.brand),
                const SizedBox(width: 8),
                Expanded(child: Text('${_what(r.targetType)}: ${r.targetLabel ?? r.targetId.substring(0, 8)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(timeAgo(r.createdAt), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 6),
            Text(r.reason, style: const TextStyle(fontSize: 13.5, height: 1.35)),
            const SizedBox(height: 4),
            Text(
              [
                if (r.ownerUsername != null) 'Posted by @${r.ownerUsername}${r.ownerSuspended ? ' (suspended)' : ''}',
                'Reported by @${r.reporterUsername}',
                if (r.note != null) 'Note: ${r.note}',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (open != null) TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: open, child: const Text('Open')),
                if (!removed && r.targetType != 'profile')
                  TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.danger), onPressed: () => _remove(context, ref), child: const Text('Remove')),
                if (r.ownerId != null)
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: r.ownerSuspended ? null : AppColors.danger),
                    onPressed: () => _suspend(context, ref),
                    child: Text(r.ownerSuspended ? 'Restore' : 'Suspend'),
                  ),
                const Spacer(),
                if (!done) FilledButton(style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () => _resolve(context, ref), child: const Text('Resolve')),
                if (done) Text('Resolved ${timeAgo(r.resolvedAt!)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Queue extends StatelessWidget {
  const _Queue({required this.icon, required this.title, required this.subtitle, required this.count, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final int? count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppColors.textPrimary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: (count ?? 0) > 0 ? AppColors.brand : AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
          child: Text('${count ?? '…'}', style: TextStyle(color: (count ?? 0) > 0 ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ),
        onTap: onTap,
      );
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
