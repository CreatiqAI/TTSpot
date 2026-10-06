import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/thumb_image.dart';
import '../../map/application/map_filters.dart' show MapMode;
import '../../map/application/map_providers.dart' show mapListViewProvider, mapModeProvider;
import '../../social/domain/post.dart' show PostKind;
import '../application/points_providers.dart';
import '../domain/points.dart';
import '../domain/points_week.dart';
import '../domain/verification.dart';
import 'widgets/referral_code_card.dart';

/// Points & rewards: the balance (and the way to spend it), how to earn with
/// each limit spelled out, and the ledger.
class PointsScreen extends ConsumerWidget {
  const PointsScreen({super.key});

  static String art(String reason) => switch (reason) {
        'meet_checkin' => AppArt.flag,
        'spot_checkin' || 'spot_verified' || 'spot_suggested' => AppArt.pin,
        'weekly_post' || 'first_post' => AppArt.camera,
        'referral_referrer' || 'referral_referee' => AppArt.hug,
        'car_of_week' => AppArt.trophy,
        'badge' => AppArt.medal,
        'club_president_bonus' => AppArt.megaphone,
        'redeem' => AppArt.coffee,
        'box' => AppArt.gift,
        _ => kCoinAsset,
      };

  /// The line under a How to earn title: the limit, and for the weekly ones
  /// when they reset (or that this week's post already paid).
  static String limitLine(PointRule r, PointsWeek week) {
    final base = r.limitNote ?? r.description;
    if (r.reason == 'weekly_post' && week.postDone) return 'Paid this week · next one after ${week.resetText}';
    if (r.weekly) return '$base · resets ${week.resetText}';
    return base;
  }

  /// Every How to earn row is a shortcut to where you earn it:
  /// * Share a post: the new post page (the + sheet's Post).
  /// * Check in at a meet: the Map tab on Events; at a spot or partner
  ///   shop: the Map tab on Spots ([openMapOn]).
  /// * Earn a badge: my badges. Bring a friend / Join with a code: my QR
  ///   and code.
  /// Null (a plain row) for anything else.
  static VoidCallback? earnTap(BuildContext context, WidgetRef ref, PointRule r, {required String? me}) {
    switch (r.reason) {
      case 'weekly_post':
        return () => context.push(Routes.createPost(PostKind.post));
      case 'meet_checkin':
        return () => openMapOn(context, ref, MapMode.events);
      case 'spot_checkin':
        return () => openMapOn(context, ref, MapMode.spots);
      case 'badge':
        if (me == null) return null;
        final String id = me;
        return () => context.push(Routes.badges(id));
    }
    if (r.reason.startsWith('referral')) return () => context.push(Routes.myQr);
    return null;
  }

  /// The Map tab on [mode] (Events or Spots), showing the map rather than
  /// its list; the map frames that layer as a tab switch would.
  static void openMapOn(BuildContext context, WidgetRef ref, MapMode mode) {
    ref.read(mapModeProvider.notifier).set(mode);
    ref.read(mapListViewProvider.notifier).set(false);
    context.go(Routes.map);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final balance = ref.watch(pointsBalanceProvider).value ?? 0;
    final rules = ref.watch(pointRulesProvider).value ?? const <PointRule>[];
    final week = ref.watch(pointsWeekProvider).value ?? PointsWeek.at(DateTime.now());
    final history = ref.watch(pointHistoryProvider);
    final verifications = (ref.watch(myVerificationsProvider).value ?? const <SpotVerification>[]).take(5).toList();
    final earn = rules.where((r) => r.earns).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Points & rewards'),
        actions: [IconButton(tooltip: 'My QR', icon: const Icon(AppIcons.qrCode), onPressed: () => context.push(Routes.myQr))],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(pointsActionsProvider).refreshBalance();
          ref.invalidate(pointRulesProvider);
          await ref.read(pointHistoryProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _Balance(points: balance),
            // Spend points, show vouchers, find partners.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(child: _HubTile(icon: AppIcons.gift, label: 'Rewards shop', onTap: () => context.push(Routes.rewards))),
                  const SizedBox(width: 8),
                  Expanded(child: _HubTile(icon: AppIcons.ticket, label: 'My vouchers', onTap: () => context.push(Routes.myVouchers))),
                  const SizedBox(width: 8),
                  Expanded(child: _HubTile(icon: AppIcons.storefront, label: 'Partners', onTap: () => context.push('${Routes.rewards}?tab=partners'))),
                ],
              ),
            ),
            const _Section('HOW TO EARN'),
            for (final r in earn) EarnRow(rule: r, limit: limitLine(r, week), onTap: earnTap(context, ref, r, me: me)),
            // The referral rows above pay out through this code.
            if (earn.any((r) => r.reason.startsWith('referral')))
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: ReferralCodeCard(),
              ),
            if (verifications.isNotEmpty) ...[
              const _Section('STICKER CHECK-INS'),
              for (final v in verifications)
                ListTile(
                  dense: true,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ThumbImage(v.photoUrl, width: 40, height: 40, error: const SizedBox(width: 40, height: 40)),
                  ),
                  title: Text(v.placeName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    v.status == VerificationStatus.approved ? timeAgo(v.createdAt) : (v.reason ?? v.status.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  trailing: Text(
                    v.status.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: switch (v.status) {
                        VerificationStatus.approved => AppColors.success,
                        VerificationStatus.rejected => AppColors.danger,
                        _ => AppColors.warnColor,
                      },
                    ),
                  ),
                  onTap: () => context.push(Routes.place(v.placeId)),
                ),
            ],
            const _Section('HISTORY'),
            history.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e))),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text('Nothing yet. Check in at a meet or a spot to start.', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : Column(children: [for (final e in list) HistoryRow(entry: e)]),
            ),
          ],
        ),
      ),
    );
  }
}

/// The balance, big, on the brand red.
class _Balance extends StatelessWidget {
  const _Balance({required this.points});
  final int points;

  static String _grouped(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.warnColor, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Row(
          children: [
            const PointsCoin(size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(_grouped(points), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                  ),
                  const SizedBox(height: 2),
                  const Text('points', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// One way to earn: the art, the title with its limit under it, the amount
/// on the right, and a chevron when it leads somewhere (then the row greys
/// while pressed).
class EarnRow extends StatelessWidget {
  const EarnRow({super.key, required this.rule, required this.limit, this.onTap});
  final PointRule rule;
  final String limit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        highlightColor: AppColors.surfaceGray,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, onTap == null ? 16 : 10, 10),
          child: Row(
            children: [
              ArtIcon(PointsScreen.art(rule.reason), size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rule.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.25)),
                    const SizedBox(height: 2),
                    Text(limit, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text('+${rule.points}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(AppIcons.caretRight, size: 16, color: AppColors.textSecondary),
              ],
            ],
          ),
        ),
      );
}

/// One ledger line: what, where or which badge, when, and the amount.
class HistoryRow extends StatelessWidget {
  const HistoryRow({super.key, required this.entry});
  final PointEntry entry;

  static const _noteReasons = {'badge', 'spot_checkin', 'spot_verified'};

  @override
  Widget build(BuildContext context) {
    final e = entry;
    // Notes the database writes for the member (the badge and tier, the
    // spot's name); other notes (admin gifts) stay off the page.
    final note = _noteReasons.contains(e.reason) ? (e.note ?? '').trim() : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ArtIcon(PointsScreen.art(e.reason), size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                Text(
                  note.isEmpty ? timeAgo(e.createdAt) : '$note · ${timeAgo(e.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${e.delta > 0 ? '+' : ''}${e.delta}',
            style: TextStyle(fontWeight: FontWeight.w800, color: e.delta > 0 ? AppColors.success : AppColors.danger),
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Column(
              children: [
                Icon(icon, size: 22, color: AppColors.textPrimary),
                const SizedBox(height: 6),
                Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2)),
              ],
            ),
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
