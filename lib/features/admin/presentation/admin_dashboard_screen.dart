import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../accounts/presentation/account_switcher.dart';
import '../../accounts/presentation/account_title.dart';
import '../application/admin_providers.dart';

/// The admin account's home: numbers, queues, reports, members, platform
/// settings. Only shown when the signed-in profile is an admin.
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
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: !embedded,
        titleSpacing: embedded ? 16 : null,
        leading: embedded ? null : IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: embedded
            ? DefaultTextStyle(style: const TextStyle(color: Colors.white), child: AccountTitle(text: 'TT Spot Admin', onTap: () => showAccountSwitcher(context, ref)))
            : const Text('TT Spot Admin'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(AppIcons.arrowsClockwise),
            onPressed: () {
              ref.invalidate(adminStatsProvider);
              ref.invalidate(adminReportsProvider);
              ref.invalidate(adminUsersProvider);
              ref.invalidate(platformSettingsProvider);
            },
          ),
        ],
      ),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        error: (e, _) => Center(child: Text(friendlyError(e), style: const TextStyle(color: Colors.white70))),
        data: (s) => ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            // ---- numbers
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

            // ---- queues
            const _Head('QUEUES'),
            _Queue(icon: AppIcons.sealCheck, title: 'Spot photo reviews', count: s['pending_verifications'], onTap: () => context.push(Routes.adminReview)),
            _Queue(icon: AppIcons.handshake, title: 'Partner & club applications', count: s['pending_partners'], onTap: () => context.push(Routes.adminPartners)),
            _Queue(icon: AppIcons.flag, title: 'Reports', count: s['open_reports'], onTap: () => _showReports(context, ref)),
            _Queue(icon: AppIcons.chartBar, title: 'Commission report', count: null, onTap: () => context.push(Routes.adminCommission)),

            // ---- open reports inline (first three)
            if (open.isNotEmpty) ...[
              const _Head('LATEST REPORTS'),
              for (final r in open.take(3)) _ReportTile(r: r),
            ],

            // ---- platform settings
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

            // ---- members
            const _Head('MEMBERS'),
            const _Members(),
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

  Future<void> _showReports(BuildContext context, WidgetRef ref) {
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
                        : ListView(children: [for (final r in list) _ReportTile(r: r, light: true)]),
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

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.sub, this.accent = false});
  final String label;
  final int value;
  final String? sub;
  final bool accent;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: accent ? AppColors.brand : const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$value', style: const TextStyle(fontFamily: AppFonts.display, color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700, height: 1)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
            if (sub != null) Text(sub!, style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
          ],
        ),
      );
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
        child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white54)),
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
        leading: Icon(icon, color: Colors.white),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        trailing: count == null
            ? const Icon(AppIcons.caretRight, size: 16, color: Colors.white38)
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: count! > 0 ? AppColors.brand : const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(999)),
                child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
        onTap: onTap,
      );
}

class _ReportTile extends ConsumerWidget {
  const _ReportTile({required this.r, this.light = false});
  final AdminReport r;
  final bool light;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fg = light ? AppColors.textPrimary : Colors.white;
    final fg2 = light ? AppColors.textSecondary : Colors.white60;
    final done = r.resolvedAt != null;
    return ListTile(
      leading: Icon(done ? AppIcons.checkCircle : AppIcons.flag, color: done ? AppColors.success : AppColors.brand),
      title: Text('${r.targetType}: ${r.targetLabel ?? r.targetId.substring(0, 8)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
      subtitle: Text('${r.reason}\nby @${r.reporterUsername} · ${timeAgo(r.createdAt)}', style: TextStyle(color: fg2, fontSize: 12, height: 1.3)),
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

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.title, required this.value, required this.onTap});
  final String title;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(value, style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
        trailing: const Icon(AppIcons.pencilSimple, size: 18, color: Colors.white38),
        onTap: onTap,
      );
}

class _Members extends ConsumerWidget {
  const _Members();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(adminUsersProvider);
    final me = ref.watch(currentUserIdProvider);
    return users.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e), style: const TextStyle(color: Colors.white70))),
      data: (list) => Column(
        children: [
          for (final u in list)
            ListTile(
              leading: UserAvatar(url: u.avatarUrl, name: u.displayName ?? u.username, size: 40),
              title: Row(
                children: [
                  Flexible(child: Text(u.displayName ?? '@${u.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                  if (u.isAdmin) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(AppIcons.shieldCheck, size: 14, color: AppColors.brand)),
                  if (u.clubOwner) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(AppIcons.crown, size: 14, color: AppColors.warnColor)),
                ],
              ),
              subtitle: Text(
                '@${u.username}${u.phone == null ? '' : ' · ${u.phone}'} · ${u.cars} car${u.cars == 1 ? '' : 's'} · joined ${u.createdAt.day}/${u.createdAt.month}/${u.createdAt.year % 100}${u.lastSeen == null ? '' : ' · seen ${timeAgo(u.lastSeen!)}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              trailing: u.id == me
                  ? null
                  : PopupMenuButton<String>(
                      iconColor: Colors.white54,
                      onSelected: (v) async {
                        final a = ref.read(adminActionsProvider);
                        try {
                          switch (v) {
                            case 'admin':
                              await a.setRole(u.id, admin: !u.isAdmin);
                            case 'club':
                              await a.setRole(u.id, clubOwner: !u.clubOwner);
                            case 'profile':
                              if (context.mounted) context.push(Routes.profile(u.id));
                          }
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'profile', child: Text('Open profile')),
                        PopupMenuItem(value: 'club', child: Text(u.clubOwner ? 'Remove club owner' : 'Make club owner')),
                        PopupMenuItem(value: 'admin', child: Text(u.isAdmin ? 'Remove admin' : 'Make admin')),
                      ],
                    ),
              onTap: () => context.push(Routes.profile(u.id)),
            ),
        ],
      ),
    );
  }
}
