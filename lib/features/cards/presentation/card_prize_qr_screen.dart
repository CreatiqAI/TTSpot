import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../application/cards_providers.dart';
import '../domain/cards.dart';

/// A claimed prize. Show it to the partner or TT Spot staff; they scan it.
class CardPrizeQrScreen extends ConsumerWidget {
  const CardPrizeQrScreen({super.key, required this.claimId});
  final String claimId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payload = ref.watch(cardClaimPayloadProvider(claimId));
    final claim = ref.watch(myCardClaimsProvider).value?.where((c) => c.id == claimId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Your prize'),
      ),
      body: payload.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(AppRadius.lg)),
              child: Column(
                children: [
                  if (claim != null) ...[
                    Text(claim.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text('${claim.byName} · ${claim.cardsUsed} card${claim.cardsUsed == 1 ? '' : 's'} spent', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: QrImageView(data: data, size: 224, padding: EdgeInsets.zero, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    claim?.byName == 'TT Spot' || claim == null
                        ? 'Show this to TT Spot staff at a meet. They scan it and hand over your prize.'
                        : 'Show this at ${claim.byName}. They scan it in TT Spot and hand over your prize.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
                  ),
                  if (claim != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      claim.status == ClaimState.active ? 'Valid till ${formatDate(claim.expiresAt)}' : claim.status.label,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('If the claim runs out before it is handed over, your cards come back to your collection.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
