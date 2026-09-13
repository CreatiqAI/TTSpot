import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../application/points_providers.dart';
import '../domain/points.dart';

/// Balance, how to earn, and the ledger. Rewards shop lands in a later phase.
class PointsScreen extends ConsumerWidget {
  const PointsScreen({super.key});

  static String _art(String reason) => switch (reason) {
        'meet_checkin' => AppArt.flag,
        'spot_checkin' || 'spot_verified' => AppArt.pin,
        'referral_referrer' || 'referral_referee' => AppArt.hug,
        'car_of_week' => AppArt.trophy,
        'badge' => AppArt.medal,
        _ => AppArt.star,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(pointsBalanceProvider).value ?? 0;
    final rules = ref.watch(pointRulesProvider).value ?? const <PointRule>[];
    final history = ref.watch(pointHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Points'),
        actions: [IconButton(tooltip: 'My QR', icon: const Icon(AppIcons.qrCode), onPressed: () => context.push(Routes.myQr))],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(pointsActionsProvider).refreshBalance();
          await ref.read(pointHistoryProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: AppColors.warnColor, borderRadius: BorderRadius.circular(AppRadius.lg)),
              child: Row(
                children: [
                  const ArtIcon(AppArt.star, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$balance', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.black, height: 1)),
                        const SizedBox(height: 2),
                        const Text('points', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87)),
                      ],
                    ),
                  ),
                  const Text('Rewards\ncoming soon', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                ],
              ),
            ),
            const _Section('HOW TO EARN'),
            for (final r in rules)
              ListTile(
                leading: ArtIcon(_art(r.reason), size: 32),
                title: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(r.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                trailing: Text('+${r.points}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                onTap: r.reason.startsWith('referral') ? () => context.push(Routes.myQr) : null,
              ),
            const _Section('HISTORY'),
            history.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e))),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text('Nothing yet. Check in at a meet or a spot to start.', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : Column(
                      children: [
                        for (final e in list)
                          ListTile(
                            dense: true,
                            leading: ArtIcon(_art(e.reason), size: 26),
                            title: Text(e.label),
                            subtitle: Text(timeAgo(e.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            trailing: Text(
                              '${e.delta > 0 ? '+' : ''}${e.delta}',
                              style: TextStyle(fontWeight: FontWeight.w800, color: e.delta > 0 ? AppColors.success : AppColors.danger),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
