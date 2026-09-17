import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/glass_tab_bar.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../accounts/presentation/account_switcher.dart';
import '../../accounts/presentation/account_title.dart';
import '../../vendors/domain/vendor.dart' show rm;
import '../application/admin_providers.dart';
import 'widgets/admin_widgets.dart';

/// Admin · Overview. Right now (on the map, live meets, check-ins today),
/// what needs a decision, the last 7 days as small trends, community and
/// money totals, top spots, newest members, platform settings.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);
    final settings = ref.watch(platformSettingsProvider).value ?? const {};
    final users = ref.watch(adminUsersProvider).value ?? const <AdminUser>[];
    final newest = users.where((u) => u.username.isNotEmpty).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    Future<void> refresh() async {
      ref.invalidate(adminStatsProvider);
      ref.invalidate(adminReportsProvider);
      ref.invalidate(adminUsersProvider);
      ref.invalidate(platformSettingsProvider);
      ref.invalidate(adminSuggestionsProvider);
      await ref.read(adminStatsProvider.future);
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: !embedded,
        titleSpacing: embedded ? 16 : null,
        leading: embedded ? null : IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: embedded ? AccountTitle(text: 'TT Spot Admin', onTap: () => showAccountSwitcher(context, ref)) : const Text('TT Spot Admin'),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(AppIcons.arrowsClockwise), onPressed: refresh)],
      ),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (s) {
          final pending = s['pending_verifications'] + s['pending_partners'] + s['pending_official'] + s['pending_suggestions'] + s['open_reports'];
          final topPlaces = s.rows('top_places');
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: EdgeInsets.only(bottom: GlassTabBar.height + 40),
              children: [
                // ---- right now
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Text(formatDate(DateTime.now()), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                ),
                const AdminHead('RIGHT NOW'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      AdminStat(label: 'On the map', value: '${s['on_map_now']}', accent: true, onTap: () => context.go(Routes.map)),
                      const SizedBox(width: 8),
                      AdminStat(label: 'Live meets', value: '${s['meets_live']}', delta: '${s['tt_today']} TT today'),
                      const SizedBox(width: 8),
                      AdminStat(label: 'Check-ins today', value: '${s['checkins_today']}'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      AdminStat(label: 'Members', value: '${s['users']}', delta: s['users_today'] > 0 ? '+${s['users_today']} today' : '+${s['users_7d']} this week', onTap: () => context.go(Routes.map)),
                      const SizedBox(width: 8),
                      AdminStat(label: 'Active · 24 h', value: '${s['active_24h']}', delta: s['users'] == 0 ? null : '${(100 * s['active_24h'] / s['users']).round()}% of members'),
                      const SizedBox(width: 8),
                      AdminStat(label: 'Upcoming meets', value: '${s['meets_upcoming']}', delta: '${s['meets_7d']} made this week'),
                    ],
                  ),
                ),

                // ---- decisions
                AdminHead(pending == 0 ? 'NEEDS A DECISION · ALL CLEAR' : 'NEEDS A DECISION · $pending', action: 'Queues', onAction: () => context.go(Routes.inbox)),
                AdminQueueTile(icon: AppIcons.handshake, title: 'Partner & club applications', hint: 'Approve a shop or a club owner', count: s['pending_partners'], onTap: () => context.push(Routes.adminPartners)),
                AdminQueueTile(icon: AppIcons.sealCheck, title: 'Official club requests', hint: 'RM 69.90 / month · approve after payment', count: s['pending_official'], onTap: () => context.push(Routes.adminPartners)),
                AdminQueueTile(icon: AppIcons.sealCheck, title: 'Spot photo reviews', hint: 'Sticker check-ins the AI was unsure about', count: s['pending_verifications'], onTap: () => context.push(Routes.adminReview)),
                AdminQueueTile(icon: AppIcons.mapPinPlus, title: 'Spot suggestions', hint: 'Places members want on the map', count: s['pending_suggestions'], onTap: () => showSuggestionsSheet(context)),
                AdminQueueTile(icon: AppIcons.flag, title: 'Open reports', hint: 'Profiles, posts and meets flagged by members', count: s['open_reports'], onTap: () => showReportsSheet(context)),

                // ---- 7 days
                const AdminHead('LAST 7 DAYS'),
                AdminTrend(label: 'New members', values: s.series('signups_by_day')),
                AdminTrend(label: 'Members active', values: s.series('active_by_day'), color: AppColors.textPrimary),
                AdminTrend(label: 'Check-ins', values: s.series('checkins_by_day'), color: AppColors.success),
                AdminTrend(label: 'Posts', values: s.series('posts_by_day'), color: const Color(0xFF2B7CFF)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Text('${s['messages_7d']} chat messages this week.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),

                // ---- community + money
                const AdminHead('COMMUNITY'),
                AdminCard(children: [
                  AdminFactRow('Clubs', '${s['clubs']} · ${s['clubs_official']} official · ${s['club_members']} memberships'),
                  AdminFactRow('Partners', '${s['vendors']} active', onTap: () => context.push(Routes.adminPartners)),
                  AdminFactRow('Spots on the map', '${s['places']}'),
                  AdminFactRow('Live vouchers', '${s['vouchers_live']}'),
                ]),
                const AdminHead('REWARDS · 30 DAYS'),
                AdminCard(children: [
                  AdminFactRow('Vouchers claimed', '${s['claims_30d']}'),
                  AdminFactRow('Redeemed at the counter', '${s['redemptions_30d']}'),
                  AdminFactRow('Bills entered', rm(s.amount('bills_30d'))),
                  AdminFactRow('Commission due', rm(s.amount('commission_30d')), onTap: () => context.push(Routes.adminCommission)),
                ]),

                // ---- top spots
                if (topPlaces.isNotEmpty) ...[
                  const AdminHead('TOP SPOTS THIS WEEK'),
                  AdminCard(children: [
                    for (var i = 0; i < topPlaces.length; i++)
                      AdminFactRow('${i + 1}. ${topPlaces[i]['name']}', '${topPlaces[i]['count']} check-in${topPlaces[i]['count'] == 1 ? '' : 's'}', onTap: () => context.push(Routes.place(topPlaces[i]['id'] as String))),
                  ]),
                ],

                // ---- newest members
                if (newest.isNotEmpty) ...[
                  AdminHead('NEWEST MEMBERS', action: 'All members', onAction: () => context.go(Routes.map)),
                  for (final u in newest.take(4))
                    ListTile(
                      dense: true,
                      leading: UserAvatar(url: u.avatarUrl, name: u.displayName ?? u.username, size: 36),
                      title: Text(u.displayName ?? u.username, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: Text('@${u.username} · joined ${timeAgo(u.createdAt)}${u.homeState == null ? '' : ' · ${u.homeState}'}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      trailing: u.lastSeen == null ? null : Text(timeAgo(u.lastSeen!), style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      onTap: () => context.push(Routes.profile(u.id)),
                    ),
                ],

                // ---- platform
                const AdminHead('PLATFORM'),
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
                _SettingTile(title: 'Commission report', value: 'Per partner, per month', onTap: () => context.push(Routes.adminCommission)),
              ],
            ),
          );
        },
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
    useRootNavigator: true, // above the shell tab bar
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
                      ? Center(child: Text('Nothing waiting.', style: TextStyle(color: AppColors.textSecondary)))
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
    useRootNavigator: true, // above the shell tab bar
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
                      ? Center(child: Text('No reports. Nice.', style: TextStyle(color: AppColors.textSecondary)))
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

class _ReportTile extends ConsumerWidget {
  const _ReportTile({required this.r});
  final AdminReport r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = r.resolvedAt != null;
    return ListTile(
      leading: Icon(done ? AppIcons.checkCircle : AppIcons.flag, color: done ? AppColors.success : AppColors.brand),
      title: Text('${r.targetType}: ${r.targetLabel ?? r.targetId.substring(0, 8)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${r.reason}\nby @${r.reporterUsername} · ${timeAgo(r.createdAt)}', style: TextStyle(fontSize: 12, height: 1.3, color: AppColors.textSecondary)),
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
                child: g.photoUrl == null ? ColoredBox(color: Color(0xFFE6E6E6), child: Icon(AppIcons.mapPin, color: AppColors.textSecondary)) : Image.network(g.photoUrl!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  if (g.address != null) Text(g.address!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text('${g.kind} · @${g.username} · ${timeAgo(g.createdAt)}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
        subtitle: Text(value, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
        onTap: onTap,
      );
}
