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
import '../../points/application/points_providers.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// The Rewards shop: partner vouchers, free or for points.
class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(shopVouchersProvider);
    final balance = ref.watch(pointsBalanceProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Rewards'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push(Routes.myVouchers),
            icon: const Icon(AppIcons.ticket, size: 18),
            label: const Text('My vouchers'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(shopVouchersProvider);
          ref.read(pointsActionsProvider).refreshBalance();
          await ref.read(shopVouchersProvider.future);
        },
        child: shop.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (list) => ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: AppColors.warnColor, borderRadius: BorderRadius.circular(AppRadius.lg)),
                child: Row(
                  children: [
                    const ArtIcon(AppArt.star, size: 32),
                    const SizedBox(width: 10),
                    Expanded(child: Text('$balance points to spend', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white))),
                    TextButton(onPressed: () => context.push(Routes.points), child: const Text('Earn more', style: TextStyle(color: Colors.white))),
                  ],
                ),
              ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: EmptyState(art: AppArt.coffee, title: 'No rewards yet', subtitle: 'Partner shops are joining. Check back soon.'),
                ),
              for (final v in list) _VoucherCard(v: v, balance: balance),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoucherCard extends ConsumerStatefulWidget {
  const _VoucherCard({required this.v, required this.balance});
  final Voucher v;
  final int balance;

  @override
  ConsumerState<_VoucherCard> createState() => _VoucherCardState();
}

class _VoucherCardState extends ConsumerState<_VoucherCard> {
  bool _busy = false;

  Future<void> _claim() async {
    final v = widget.v;
    if (v.pointsCost > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Spend ${v.pointsCost} points?'),
          content: Text('${v.title} at ${v.vendorName}. The voucher goes to My vouchers and you show its QR at the counter.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Claim')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(vendorActionsProvider).claim(v.id);
      if (mounted) context.push(Routes.voucherQr(r.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final held = v.myActiveClaim != null;
    final maxed = v.myClaims >= v.perUserLimit;
    final canAfford = widget.balance >= v.pointsCost;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: v.vendorLogo == null
                      ? Container(width: 36, height: 36, color: AppColors.surfaceGray, child: const Icon(AppIcons.storefront, size: 18, color: AppColors.textSecondary))
                      : Image.network(v.vendorLogo!, width: 36, height: 36, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.vendorName ?? 'Partner', style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (v.vendorAddress != null) Text(v.vendorAddress!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: v.pointsCost == 0 ? AppColors.success : AppColors.warnColor, borderRadius: BorderRadius.circular(999)),
                  child: Text(v.pointsCost == 0 ? 'FREE' : '${v.pointsCost} pts', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 92,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: FittedBox(child: Text(v.headline, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      if (v.description != null) Text(v.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (v.minSpend > 0) 'min ${rm(v.minSpend)}',
                          if (v.left != null) '${v.left} left',
                          if (v.endsAt != null) 'till ${formatDate(v.endsAt!)}',
                          if (v.terms != null) v.terms!,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: SizedBox(
              width: double.infinity,
              child: held
                  ? OutlinedButton.icon(
                      onPressed: () => context.push(Routes.voucherQr(v.myActiveClaim!)),
                      icon: const Icon(AppIcons.qrCode, size: 18),
                      label: const Text('Show my voucher'),
                    )
                  : FilledButton(
                      onPressed: _busy || maxed || !canAfford ? null : _claim,
                      child: Text(maxed
                          ? 'Already claimed'
                          : !canAfford
                              ? 'Need ${v.pointsCost - widget.balance} more points'
                              : v.pointsCost == 0
                                  ? 'Claim for free'
                                  : 'Claim for ${v.pointsCost} points'),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
