import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../social/application/notification_providers.dart';

/// All badges, earned ones lit up. TT streak on top.
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allBadgesProvider);
    final earned = ref.watch(earnedBadgesProvider(userId)).value ?? const [];
    final streak = ref.watch(ttStreakProvider(userId)).value ?? 0;
    final earnedById = {for (final e in earned) e.badge.id: e};

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Badges'),
      ),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (badges) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.border)),
              child: Row(
                children: [
                  ArtIcon(streak > 0 ? AppArt.fire : AppArt.coffee, size: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(streak > 0 ? '$streak-week TT streak' : 'No TT streak yet', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          streak > 0 ? 'A teh tarik session every week for $streak week${streak == 1 ? '' : 's'}. Keep it going.' : 'Join a TT session each week to start one.',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('${earned.length} of ${badges.length} earned', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.82),
              itemCount: badges.length,
              itemBuilder: (_, i) {
                final b = badges[i];
                final got = earnedById[b.id];
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: got != null ? AppColors.bg : AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: got != null ? AppColors.textPrimary : AppColors.border, width: got != null ? 1.2 : 1),
                  ),
                  child: Opacity(
                    opacity: got != null ? 1 : 0.45,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ArtIcon.emoji(b.emoji, size: 40),
                        const SizedBox(height: 6),
                        Text(b.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(got != null ? formatDate(got.awardedAt) : b.description, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary, height: 1.2)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
