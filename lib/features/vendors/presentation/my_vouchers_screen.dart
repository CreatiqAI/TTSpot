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
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// My wallet: claimed vouchers, ready ones first.
class MyVouchersScreen extends ConsumerWidget {
  const MyVouchersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(myWalletProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('My vouchers'),
        actions: [IconButton(tooltip: 'Rewards shop', icon: const Icon(AppIcons.gift), onPressed: () => context.push(Routes.rewards))],
      ),
      body: RefreshIndicator(
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
                      child: EmptyState(
                        art: AppArt.coffee,
                        title: 'No vouchers yet',
                        subtitle: 'Claim one in the Rewards shop and show its QR at the counter.',
                        actionLabel: 'Open Rewards',
                        onAction: () => context.push(Routes.rewards),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 32, top: 8),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _ClaimTile(c: list[i]),
                ),
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
                  Text(c.headline, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1)),
                  const SizedBox(height: 4),
                  Text(c.vendorName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      ready ? 'Valid till ${formatDate(c.expiresAt)}' : (c.status == ClaimStatus.redeemed && c.redeemedAt != null ? 'Used ${timeAgo(c.redeemedAt!)}' : c.status.label),
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              Icon(ready ? AppIcons.qrCode : AppIcons.checkCircle, size: 26, color: Colors.black87),
            ],
          ),
        ),
      ),
    );
  }
}
