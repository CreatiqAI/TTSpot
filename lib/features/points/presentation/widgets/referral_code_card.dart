import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../application/points_providers.dart';

/// What a member sends when they share their code.
String referralShareText(String code) =>
    'Join me on TT Spot, Malaysia\'s car community. Use my referral code $code when you sign up and we both get points: https://ttspot.my/r/$code';

/// "YOUR REFERRAL CODE": the member's 6-character code, big, with Copy and
/// Share. Used under My QR and on the Points screen.
class ReferralCodeCard extends ConsumerWidget {
  const ReferralCodeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(myReferralCodeProvider);
    final value = code.value ?? '';
    final ready = value.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR REFERRAL CODE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          SizedBox(
            height: 44,
            child: code.when(
              loading: () => const Align(alignment: Alignment.centerLeft, child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              error: (e, _) => Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => ref.invalidate(myReferralCodeProvider),
                  child: Text('${friendlyError(e)} Tap to retry.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ),
              ),
              data: (c) => Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  c,
                  style: TextStyle(fontFamily: AppFonts.display, fontSize: 34, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: 6, color: AppColors.textPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: !ready
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: value));
                          HapticFeedback.lightImpact();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(const SnackBar(content: Text('Copied')));
                          }
                        },
                  child: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: !ready ? null : () => SharePlus.instance.share(ShareParams(text: referralShareText(value))),
                  icon: const Icon(AppIcons.shareNetwork, size: 16),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
