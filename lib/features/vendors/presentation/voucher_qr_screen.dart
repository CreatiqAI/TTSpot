import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// Show this at the counter. The vendor scans it, types the bill, done.
class VoucherQrScreen extends ConsumerWidget {
  const VoucherQrScreen({super.key, required this.claimId});
  final String claimId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payload = ref.watch(claimPayloadProvider(claimId));
    final claim = ref.watch(myWalletProvider).value?.where((c) => c.id == claimId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Your voucher'),
      ),
      body: payload.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.warnColor, borderRadius: BorderRadius.circular(AppRadius.lg)),
              child: Column(
                children: [
                  if (claim != null) ...[
                    Text(claim.headline, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1)),
                    const SizedBox(height: 4),
                    Text(claim.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(claim.vendorName, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: QrImageView(data: data, size: 224, padding: EdgeInsets.zero, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
                  ),
                  const SizedBox(height: 14),
                  const Text('Show this to the staff. They scan it in TT Spot and apply the discount to your bill.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.4)),
                  if (claim != null) ...[
                    const SizedBox(height: 8),
                    Text('Valid till ${formatDate(claim.expiresAt)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87)),
                  ],
                ],
              ),
            ),
            if (claim?.terms != null) ...[
              const SizedBox(height: 16),
              const Text('TERMS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(claim!.terms!, style: const TextStyle(fontSize: 13, height: 1.4)),
            ],
            if (claim != null && claim.minSpend > 0) ...[
              const SizedBox(height: 8),
              Text('Minimum spend ${rm(claim.minSpend)}.', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}
