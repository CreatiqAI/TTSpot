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

/// Rewards: the partner shop and the vouchers I hold, as two tabs.
class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final walletCount = (ref.watch(myWalletProvider).value ?? const <VoucherClaim>[]).where((c) => c.status == ClaimStatus.active).length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Rewards'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.textPrimary,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorWeight: 1.5,
          dividerColor: AppColors.border,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: [
            const Tab(text: 'Shop'),
            Tab(text: walletCount == 0 ? 'My vouchers' : 'My vouchers · $walletCount'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_ShopTab(), _WalletTab()],
      ),
    );
  }
}

class _ShopTab extends ConsumerWidget {
  const _ShopTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(shopVouchersProvider);
    final balance = ref.watch(pointsBalanceProvider).value ?? 0;
    return RefreshIndicator(
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
      );
  }
}

class _WalletTab extends ConsumerWidget {
  const _WalletTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(myWalletProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myWalletProvider);
        await ref.read(myWalletProvider.future);
      },
      child: wallet.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (list) => list.isEmpty
            ? LayoutBuilder(
                builder: (_, c) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: c.maxHeight,
                    child: const EmptyState(art: AppArt.coffee, title: 'No vouchers yet', subtitle: 'Claim one in the Shop tab and show its QR at the counter.'),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 32, top: 8),
                itemCount: list.length,
                itemBuilder: (_, i) => _ClaimTile(c: list[i]),
              ),
      ),
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({required this.c});
  final VoucherClaim c;

  @override
  Widget build(BuildContext context) {
    final ready = c.status == ClaimStatus.active;
    return Opacity(
      opacity: ready ? 1 : 0.55,
      child: InkWell(
        onTap: ready ? () => context.push(Routes.voucherQr(c.id)) : null,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ready ? AppColors.warnColor : AppColors.surfaceGray,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.headline, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1, color: ready ? Colors.white : AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(c.vendorName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ready ? Colors.white70 : AppColors.textSecondary)),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: ready ? Colors.white : AppColors.textPrimary)),
                    Text(
                      ready ? 'Valid till ${formatDate(c.expiresAt)}' : (c.status == ClaimStatus.redeemed && c.redeemedAt != null ? 'Used ${timeAgo(c.redeemedAt!)}' : c.status.label),
                      style: TextStyle(fontSize: 12, color: ready ? Colors.white70 : AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(ready ? AppIcons.qrCode : AppIcons.checkCircle, size: 26, color: ready ? Colors.white : AppColors.textSecondary),
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
