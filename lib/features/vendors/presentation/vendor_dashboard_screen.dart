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
import '../../accounts/presentation/account_switcher.dart';
import '../../accounts/presentation/account_title.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// The partner's home: headline numbers, scan-to-redeem, vouchers, recent
/// redemptions, and the monthly statement.
class VendorDashboardScreen extends ConsumerWidget {
  const VendorDashboardScreen({super.key, this.embedded = false});
  /// Shown as the Me tab (partner account active): no back arrow, the title
  /// opens the account switcher.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendor = ref.watch(myVendorProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: !embedded,
        titleSpacing: embedded ? 16 : null,
        leading: embedded ? null : IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: embedded
            ? AccountTitle(text: vendor.value?.name ?? 'Partner', onTap: () => showAccountSwitcher(context, ref))
            : const Text('Partner dashboard'),
        actions: [
          IconButton(tooltip: 'Statement', icon: const Icon(AppIcons.chartBar), onPressed: () => context.push(Routes.vendorReport)),
        ],
      ),
      body: vendor.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (v) => v == null
            ? EmptyState(art: AppArt.handshake, title: 'Not a partner yet', subtitle: 'Apply and an admin will review it.', actionLabel: 'Apply', onAction: () => context.pushReplacement(Routes.partnerApply))
            : _Body(vendor: v),
      ),
      floatingActionButton: vendor.value == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(Routes.scan),
              icon: const Icon(AppIcons.scan),
              label: const Text('Scan voucher'),
            ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.vendor});
  final Vendor vendor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vouchers = ref.watch(vendorVouchersProvider).value ?? const <Voucher>[];
    final products = ref.watch(vendorProductsProvider).value ?? const <Product>[];
    final redemptions = (ref.watch(vendorRedemptionsProvider).value ?? const <Redemption>[]).take(5).toList();
    final ratePct = (vendor.commissionRate * 100).toStringAsFixed(vendor.commissionRate * 100 % 1 == 0 ? 0 : 2);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myVendorProvider);
        ref.invalidate(vendorVouchersProvider);
        ref.invalidate(vendorRedemptionsProvider);
        ref.invalidate(vendorProductsProvider);
        await ref.read(myVendorProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: vendor.logoUrl == null
                      ? Container(width: 56, height: 56, color: AppColors.surfaceGray, child: const Icon(AppIcons.storefront, color: AppColors.textSecondary))
                      : Image.network(vendor.logoUrl!, width: 56, height: 56, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vendor.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text('${businessTypeLabel(vendor.type)}${vendor.address == null ? '' : ' · ${vendor.address}'}',
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                IconButton(tooltip: 'Edit shop', icon: const Icon(AppIcons.pencilSimple), onPressed: () => context.push(Routes.vendorEdit)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                _Stat(label: 'Redeemed · 30 d', value: '${vendor.redemptions30d}'),
                const SizedBox(width: 8),
                _Stat(label: 'Bills · 30 d', value: rm(vendor.bill30d)),
                const SizedBox(width: 8),
                _Stat(label: 'Commission $ratePct%', value: rm(vendor.commission30d), highlight: true),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                _Stat(label: 'Page views · 30 d', value: '${vendor.views30d}'),
                const SizedBox(width: 8),
                _Stat(label: 'Check-ins · 30 d', value: '${vendor.checkins30d}'),
                const SizedBox(width: 8),
                _Stat(label: 'Claimed · 30 d', value: '${vendor.claims30d}'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Commission is $ratePct% of each bill you enter at redemption. Your statement is settled monthly.',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
            child: Row(
              children: [
                Expanded(child: _SectionTitle('PRODUCTS · ${products.length}/5')),
                TextButton.icon(
                  onPressed: products.length >= 5 ? null : () => context.push(Routes.productNew),
                  icon: const Icon(AppIcons.plus, size: 16),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          if (products.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Show up to 5 things you sell. Members see them on your page and can message you about them.', style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            SizedBox(
              height: 150,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [for (final p in products) _ProductTile(p: p)],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
            child: Row(
              children: [
                const Expanded(child: _SectionTitle('VOUCHERS')),
                TextButton.icon(
                  onPressed: () => context.push(Routes.voucherNew),
                  icon: const Icon(AppIcons.plus, size: 16),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          if (vouchers.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('No vouchers yet. Create one and it shows up in every member\'s Rewards shop.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          for (final v in vouchers) _VoucherRow(v: v),
          const Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 6), child: _SectionTitle('RECENT REDEMPTIONS')),
          if (redemptions.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Nothing redeemed yet. Tap Scan voucher when a member shows their QR.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          for (final r in redemptions)
            ListTile(
              dense: true,
              leading: UserAvatar(url: r.avatarUrl, name: r.username, size: 36),
              title: Text('@${r.username ?? ''} · ${r.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${timeAgo(r.createdAt)}${r.note == null ? '' : ' · ${r.note}'}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(rm(r.billAmount), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('fee ${rm(r.commissionAmount)}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          if (redemptions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton(onPressed: () => context.push(Routes.vendorReport), child: const Text('See full statement')),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: highlight ? AppColors.warnColor : AppColors.surfaceGray,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: highlight ? Colors.white : AppColors.textPrimary))),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, color: highlight ? Colors.white70 : AppColors.textSecondary)),
            ],
          ),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary));
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.p});
  final Product p;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => context.push(Routes.productEdit(p.id)),
        child: Container(
          width: 120,
          margin: const EdgeInsets.only(right: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: SizedBox(
                      width: 120,
                      height: 96,
                      child: p.photoUrls.isEmpty
                          ? const ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.shoppingBag, color: AppColors.textSecondary))
                          : Opacity(opacity: p.active ? 1 : 0.45, child: Image.network(p.photoUrls.first, fit: BoxFit.cover)),
                    ),
                  ),
                  if (!p.active)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                        child: const Text('Hidden', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Text(p.priceLabel, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
}

class _VoucherRow extends ConsumerWidget {
  const _VoucherRow({required this.v});
  final Voucher v;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = v.active && !v.ended && !v.soldOut;
    return ListTile(
      onTap: () => context.push(Routes.voucherEdit(v.id)),
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: live ? AppColors.warnColor.withValues(alpha: 0.2) : AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Icon(AppIcons.ticket, color: live ? Colors.black : AppColors.textSecondary),
      ),
      title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          v.headline,
          if (v.productName != null) 'for ${v.productName}',
          if (v.pointsCost > 0) '${v.pointsCost} pts',
          '${v.claimsCount} claimed${v.maxClaims == null ? '' : ' / ${v.maxClaims}'}',
          '${v.redemptions} used',
          if (v.ended) 'ended' else if (v.endsAt != null) 'ends ${formatDate(v.endsAt!)}',
        ].join(' · '),
        maxLines: 2,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: Switch.adaptive(
        value: v.active,
        onChanged: (on) async {
          try {
            await ref.read(vendorActionsProvider).setActive(v.id, on);
          } catch (e) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
          }
        },
      ),
    );
  }
}
