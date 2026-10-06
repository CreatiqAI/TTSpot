import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../badges/application/badges_providers.dart';
import '../../badges/domain/badges.dart';
import '../../badges/presentation/honour_picker_sheet.dart';
import '../../badges/presentation/tier_badge_image.dart';

/// Every badge with its tier (bronze, silver, platinum, gold), what it
/// counts, the way to the next tier and all four steps. On my own page,
/// "Choose for profile" picks the three in my honour row.
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMe = ref.watch(currentUserIdProvider) == userId;
    final progress = ref.watch(badgeProgressProvider(userId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Badges'),
      ),
      body: progress.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (badges) => RefreshIndicator(
          onRefresh: () => ref.refresh(badgeProgressProvider(userId).future),
          child: BadgesList(badges: badges, isMe: isMe, onChoose: () => showHonourPicker(context, userId: userId, showAllLink: false)),
        ),
      ),
    );
  }
}

/// The page body (split out for tests).
class BadgesList extends StatelessWidget {
  const BadgesList({super.key, required this.badges, required this.isMe, this.onChoose});
  final List<BadgeProgress> badges;
  final bool isMe;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final earned = badges.where((b) => b.earned).length;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          '$earned of ${badges.length} earned · bronze, silver, platinum, gold',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
        ),
        if (isMe) ...[
          const SizedBox(height: 10),
          SecondaryButton(label: 'Choose for profile', icon: AppIcons.pushPin, onPressed: earned == 0 ? null : onChoose),
          if (earned == 0) ...[
            const SizedBox(height: 6),
            Text('Earn a badge to show it on your profile.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ],
        const SizedBox(height: 12),
        for (final b in badges) ...[
          BadgeCard(badge: b, showOnProfile: isMe),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// One badge: art, name, tier, what it counts, the bar to the next tier and
/// the four steps.
class BadgeCard extends StatelessWidget {
  const BadgeCard({super.key, required this.badge, this.showOnProfile = false});
  final BadgeProgress badge;
  final bool showOnProfile;

  @override
  Widget build(BuildContext context) {
    final b = badge;
    final color = badgeTierColor(b.tier);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TierBadgeImage(id: b.id, tier: b.tier, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Pill(text: b.earned ? badgeTierName(b.tier) : 'Locked', color: b.earned ? color : AppColors.textSecondary),
                        if (showOnProfile && b.onProfile) _Pill(text: 'On profile', color: AppColors.textPrimary, icon: AppIcons.pushPin),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(b.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(b.progressLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: b.fraction,
              minHeight: 6,
              backgroundColor: AppColors.surfaceGray,
              valueColor: AlwaysStoppedAnimation(b.isTop ? badgeTierColor(kTopTier) : badgeTierColor(b.nextTier)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var t = 1; t <= kTopTier; t++) ...[
                if (t > 1) const SizedBox(width: 6),
                Expanded(child: _Step(tier: t, count: t - 1 < b.thresholds.length ? b.thresholds[t - 1] : null, reached: b.tier >= t)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
            Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      );
}

/// One of the four steps: the tier's art, its name and the count it needs.
class _Step extends StatelessWidget {
  const _Step({required this.tier, required this.count, required this.reached});
  final int tier;
  final int? count;
  final bool reached;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: reached ? badgeTierColor(tier).withValues(alpha: 0.10) : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: reached ? badgeTierColor(tier).withValues(alpha: 0.45) : AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              count == null ? '–' : '$count',
              maxLines: 1,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: reached ? AppColors.textPrimary : AppColors.textSecondary),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                badgeTierName(tier),
                maxLines: 1,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: reached ? badgeTierColor(tier) : AppColors.textMuted),
              ),
            ),
          ],
        ),
      );
}
