import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../accounts/presentation/account_switcher.dart';
import '../../accounts/presentation/account_title.dart';
import '../application/admin_providers.dart';

/// Admin · Dashboard: the numbers, what needs a decision, platform settings.
/// Same light theme as the rest of the app. Members and Queues have their
/// own tabs.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);
    final settings = ref.watch(platformSettingsProvider).value ?? const {};
    final reports = ref.watch(adminReportsProvider).value ?? const <AdminReport>[];
    final open = reports.where((r) => r.resolvedAt == null).toList();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: !embedded,
        titleSpacing: embedded ? 16 : null,
        leading: embedded ? null : IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: embedded ? AccountTitle(text: 'TT Spot Admin', onTap: () => showAccountSwitcher(context, ref)) : const Text('TT Spot Admin'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(AppIcons.arrowsClockwise),
            onPressed: () {
              ref.invalidate(adminStatsProvider);
              ref.invalidate(adminReportsProvider);
              ref.invalidate(adminUsersProvider);
              ref.invalidate(platformSettingsProvider);
              ref.invalidate(adminSuggestionsProvider);
            },
          ),
        ],
      ),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (s) => ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.15,
                children: [
                  _Stat('Members', s['users'], sub: '+${s['users_7d']} this week'),
                  _Stat('On the map', s['on_map_now'], accent: true),
                  _Stat('Live meets', s['meets_live']),
                  _Stat('Upcoming', s['meets_upcoming']),
                  _Stat('Check-ins today', s['checkins_today']),
                  _Stat('Posts · 7d', s['posts_7d']),
                ],
              ),
            ),

            const _Head('NEEDS A DECISION'),
            _Queue(icon: AppIcons.sealCheck, title: 'Spot photo reviews', count: s['pending_verifications'], onTap: () => context.push(Routes.adminReview)),
            _Queue(icon: AppIcons.handshake, title: 'Partner & club applications', count: s['pending_partners'], onTap: () => context.push(Routes.adminPartners)),
            _Queue(icon: AppIcons.mapPinPlus, title: 'Spot suggestions', count: s['pending_suggestions'], onTap: () => showSuggestionsSheet(context)),
            _Queue(icon: AppIcons.flag, title: 'Open reports', count: s['open_reports'], onTap: () => showReportsSheet(context)),

            if (open.isNotEmpty) ...[
              const _Head('LATEST REPORTS'),
              for (final r in open.take(3)) _ReportTile(r: r),
            ],

            const _Head('PLATFORM'),
            _SettingTile(
              title: 'Commission rate',
              value: '${(((settings['commission_rate'] as num?) ?? 0.01) * 100).toStringAsFixed(1)} % of the bill',
              onTap: () => _editNumber(context, ref, 'commission_rate', 'Commission rate (%)', ((settings['commission_rate'] as num?) ?? 0.01) * 100, (v) => v / 100),
            ),
            _SettingTile(
              title: 'Check-in radius',
              value: '${(settings['checkin_radius_m'] as num?) ?? 300} m',
              onTap: () => _editNumber(context, ref, 'checkin_radius_m', 'Check-in radius (m)', ((settings['checkin_radius_m'] as num?) ?? 300).toDouble(), (v) => v.round()),
            ),
            _SettingTile(
              title: 'Partners · clubs',
              value: '${s['vendors']} active partners · ${s['clubs']} clubs',
              onTap: () => context.push(Routes.adminPartners),
            ),
            _SettingTile(title: 'Commission report', value: 'Per partner, per month', onTap: () => context.push(Routes.adminCommission)),
          ],
        ),
      ),
    );
  }

  Future<void> _editNumber(BuildContext context, WidgetRef ref, String key, String label, double current, Object Function(double) store) async {
    final ctrl = TextEditingController(text: current.toStringAsFixed(current % 1 == 0 ? 0 : 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final v = double.tryParse(ctrl.text.trim());
    if (v == null) return;
    try {
      await ref.read(adminActionsProvider).setSetting(key, store(v));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

/// Member suggestions waiting for approval, as a sheet (used from the
/// dashboard and the Queues tab).
Future<void> showSuggestionsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Consumer(
      builder: (ctx, ref, _) {
        final list = ref.watch(adminSuggestionsProvider).value ?? const <AdminSuggestion>[];
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.8,
            child: Column(
              children: [
                const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Spot suggestions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Text('Nothing waiting.', style: TextStyle(color: AppColors.textSecondary)))
                      : ListView(children: [for (final g in list) _SuggestionTile(g: g)]),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> showReportsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Consumer(
      builder: (ctx, ref, _) {
        final list = ref.watch(adminReportsProvider).value ?? const <AdminReport>[];
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.8,
            child: Column(
              children: [
                const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Reports', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Text('No reports. Nice.', style: TextStyle(color: AppColors.textSecondary)))
                      : ListView(children: [for (final r in list) _ReportTile(r: r)]),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.sub, this.accent = false});
  final String label;
  final int value;
  final String? sub;
  final bool accent;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: accent ? AppColors.brand : AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$value', style: TextStyle(fontFamily: AppFonts.display, color: accent ? Colors.white : AppColors.textPrimary, fontSize: 30, fontWeight: FontWeight.w700, height: 1)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: accent ? Colors.white70 : AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
            if (sub != null) Text(sub!, style: TextStyle(color: accent ? Colors.white60 : AppColors.textMuted, fontSize: 10.5)),
          ],
        ),
      );
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
        child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

class _Queue extends StatelessWidget {
  const _Queue({required this.icon, required this.title, required this.count, required this.onTap});
  final IconData icon;
  final String title;
  final int? count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppColors.textPrimary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        trailing: count == null
            ? const Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted)
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: count! > 0 ? AppColors.brand : AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
                child: Text('$count', style: TextStyle(color: count! > 0 ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
        onTap: onTap,
      );
}

class _ReportTile extends ConsumerWidget {
  const _ReportTile({required this.r});
  final AdminReport r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = r.resolvedAt != null;
    return ListTile(
      leading: Icon(done ? AppIcons.checkCircle : AppIcons.flag, color: done ? AppColors.success : AppColors.brand),
      title: Text('${r.targetType}: ${r.targetLabel ?? r.targetId.substring(0, 8)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${r.reason}\nby @${r.reporterUsername} · ${timeAgo(r.createdAt)}', style: const TextStyle(fontSize: 12, height: 1.3, color: AppColors.textSecondary)),
      isThreeLine: true,
      trailing: done
          ? null
          : TextButton(
              onPressed: () async {
                try {
                  await ref.read(adminActionsProvider).resolveReport(r.id);
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
                }
              },
              child: const Text('Resolve'),
            ),
      onTap: r.targetType == 'profile'
          ? () => context.push(Routes.profile(r.targetId))
          : r.targetType == 'event'
              ? () => context.push(Routes.event(r.targetId))
              : null,
    );
  }
}

class _SuggestionTile extends ConsumerWidget {
  const _SuggestionTile({required this.g});
  final AdminSuggestion g;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = g.status == 'pending';
    Future<void> review(bool ok) async {
      try {
        await ref.read(adminActionsProvider).reviewSuggestion(g.id, approve: ok);
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: g.photoUrl == null ? const ColoredBox(color: Color(0xFFE6E6E6), child: Icon(AppIcons.mapPin, color: AppColors.textSecondary)) : Image.network(g.photoUrl!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  if (g.address != null) Text(g.address!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text('${g.kind} · @${g.username} · ${timeAgo(g.createdAt)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  if (g.note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(g.note!, style: const TextStyle(fontSize: 12.5, height: 1.35))),
                  const SizedBox(height: 6),
                  if (pending)
                    Row(
                      children: [
                        FilledButton(style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () => review(true), child: const Text('Add to map')),
                        const SizedBox(width: 8),
                        TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () => review(false), child: const Text('Reject')),
                      ],
                    )
                  else
                    Text(g.status == 'approved' ? 'On the map' : 'Rejected', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: g.status == 'approved' ? AppColors.success : AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.title, required this.value, required this.onTap});
  final String title;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        subtitle: Text(value, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        trailing: const Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
        onTap: onTap,
      );
}
