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
import '../../../core/widgets/primary_button.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// Partner tab: every voucher, live ones first, with the on/off switch.
class VendorVouchersScreen extends ConsumerWidget {
  const VendorVouchersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vouchers = ref.watch(vendorVouchersProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 16,
        title: const Text('Vouchers'),
        actions: [
          IconButton(tooltip: 'Scan a member\'s voucher', icon: const Icon(AppIcons.scan), onPressed: () => context.push(Routes.scan)),
          IconButton(tooltip: 'Statement', icon: const Icon(AppIcons.chartBar), onPressed: () => context.push(Routes.vendorReport)),
        ],
      ),
      body: vouchers.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (list) {
          final live = list.where((v) => v.active && !v.ended && !v.soldOut).toList();
          final off = list.where((v) => !(v.active && !v.ended && !v.soldOut)).toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(vendorVouchersProvider);
              await ref.read(vendorVouchersProvider.future);
            },
            child: list.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 80),
                    EmptyState(art: AppArt.ticket, title: 'No vouchers yet', subtitle: 'A voucher shows up in every member\'s Rewards shop. Members claim it, then show the QR at your counter.'),
                  ])
                : ListView(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
                    children: [
                      if (live.isNotEmpty) ...[
                        _Head('LIVE · ${live.length}'),
                        for (final v in live) VoucherRow(v: v),
                      ],
                      if (off.isNotEmpty) ...[
                        _Head('OFF · ${off.length}'),
                        for (final v in off) VoucherRow(v: v),
                      ],
                    ],
                  ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: PrimaryButton(label: 'New voucher', onPressed: () => context.push(Routes.voucherNew)),
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

/// One voucher: headline, what it applies to, claims, uses, end date, switch.
class VoucherRow extends ConsumerWidget {
  const VoucherRow({super.key, required this.v});
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
        decoration: BoxDecoration(color: live ? AppColors.brand.withValues(alpha: 0.1) : AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Icon(AppIcons.ticket, color: live ? AppColors.brand : AppColors.textSecondary),
      ),
      title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        [
          v.headline,
          v.productName == null ? 'whole shop' : 'for ${v.productName}',
          if (v.pointsCost > 0) '${v.pointsCost} pts',
          '${v.claimsCount} claimed${v.maxClaims == null ? '' : ' / ${v.maxClaims}'}',
          '${v.redemptions} used',
          if (v.ended) 'ended' else if (v.endsAt != null) 'ends ${formatDate(v.endsAt!)}',
        ].join(' · '),
        maxLines: 2,
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
