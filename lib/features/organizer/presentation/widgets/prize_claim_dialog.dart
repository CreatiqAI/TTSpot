import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../application/organizer_providers.dart';
import '../../domain/organizer_models.dart';

/// Crew scanned a winner's claim QR: mark it claimed on the server and say
/// what to hand over (or why not).
Future<void> showPrizeClaim(BuildContext context, WidgetRef ref, String code) async {
  PrizeClaimResult? result;
  String? error;
  try {
    result = await ref.read(organizerActionsProvider).claimPrize(code);
    HapticFeedback.mediumImpact();
  } catch (e) {
    error = friendlyError(e);
  }
  if (!context.mounted) return;
  final r = result;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (r == null) ...[
            const Titi(TitiPose.sad, height: 110),
            const SizedBox(height: 10),
            Text(error ?? 'Could not check that code.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ] else ...[
            Titi(r.ok ? TitiPose.celebrate : TitiPose.sad, height: 110),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(url: r.avatarUrl, name: r.displayName, seed: r.userId, size: 36),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.displayName ?? 'Member', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text([if (r.username != null) '@${r.username}', if (r.rank != null) '#${r.rank}'].join(' · '),
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (r.prize != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: r.ok ? AppColors.success : AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Row(
                  children: [
                    Icon(r.ok ? AppIcons.gift : AppIcons.info, color: r.ok ? Colors.white : AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(r.prize!, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: r.ok ? Colors.white : AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(r.message, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, height: 1.35)),
          ],
        ],
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(r?.ok ?? false ? 'Done' : 'OK'))],
    ),
  );
}
