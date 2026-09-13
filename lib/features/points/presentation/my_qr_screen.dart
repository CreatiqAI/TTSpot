import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../application/points_providers.dart';

/// My QR: friends scan it to add me instantly; new members who scan it are
/// counted as my referral. Username is the typed fallback.
class MyQrScreen extends ConsumerWidget {
  const MyQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).value;
    final payload = ref.watch(myQrPayloadProvider);
    final referrals = ref.watch(myReferralsProvider).value;
    final rules = ref.watch(pointRulesProvider).value ?? const [];
    final referrerPts = rules.where((r) => r.reason == 'referral_referrer').firstOrNull?.points ?? 100;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('My QR'),
        actions: [
          IconButton(
            tooltip: 'New code',
            icon: const Icon(AppIcons.arrowsClockwise),
            onPressed: () async {
              try {
                await ref.read(pointsActionsProvider).rotateQr();
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New code. Old screenshots no longer work.')));
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                UserAvatar(url: profile?.avatarUrl, name: profile?.displayName ?? profile?.username, size: 64),
                const SizedBox(height: 8),
                Text(profile?.displayName ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text('@${profile?.username ?? ''}', style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                payload.when(
                  loading: () => const SizedBox(height: 240, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                  error: (e, _) => SizedBox(height: 240, child: Center(child: Text(friendlyError(e)))),
                  data: (data) => data.isEmpty
                      ? const SizedBox(height: 240)
                      : Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md)),
                          child: QrImageView(data: data, size: 216, padding: EdgeInsets.zero, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
                        ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Friends scan this to add you on the spot. It changes when you tap the refresh icon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Scan a code', onPressed: () => context.pushReplacement(Routes.scan)),
          const SizedBox(height: 24),
          const Text('BRING A FRIEND', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            'Your username is your referral code. When someone signs up with it and does their first check-in, you get $referrerPts points.',
            style: const TextStyle(fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Text(profile?.username ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: SecondaryButton(
                  label: 'Copy',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: profile?.username ?? ''));
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied.')));
                  },
                ),
              ),
            ],
          ),
          if (referrals != null && referrals.total > 0) ...[
            const SizedBox(height: 10),
            Text(
              '${referrals.total} joined with your code · ${referrals.rewarded} rewarded',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
