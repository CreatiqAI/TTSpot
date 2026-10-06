import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../application/badges_providers.dart';
import '../domain/badges.dart';
import 'honour_picker_sheet.dart';
import 'tier_badge_image.dart';

/// The profile's honour row: up to three badge medallions under the numbers.
/// Nothing at all until the member has a badge. On my page a tap picks which
/// three show; on someone else's it opens their badges.
class ProfileHonourRow extends ConsumerWidget {
  const ProfileHonourRow({super.key, required this.userId, required this.isMe});
  final String userId;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(honourBadgesProvider(userId)).value ?? const <HonourBadge>[];
    if (badges.isEmpty) return const SizedBox.shrink();
    return HonourRow(
      badges: badges,
      onTap: isMe ? () => showHonourPicker(context, userId: userId) : () => context.push(Routes.badges(userId)),
    );
  }
}

/// Up to three medallions in thirds, left to right.
class HonourRow extends StatelessWidget {
  const HonourRow({super.key, required this.badges, this.onTap});
  final List<HonourBadge> badges;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    final shown = badges.take(kHonourMax).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < kHonourMax; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: i < shown.length ? HonourMedallion(badge: shown[i], onTap: onTap) : const SizedBox.shrink()),
          ],
        ],
      ),
    );
  }
}

/// The tier art, the badge's name and the tier's name.
class HonourMedallion extends StatelessWidget {
  const HonourMedallion({super.key, required this.badge, this.onTap});
  final HonourBadge badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: onTap != null,
      label: '${badge.name} badge, ${badgeTierName(badge.tier)}',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surfaceRaised,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
            decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: AppColors.border)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TierBadgeImage(id: badge.id, tier: badge.tier, size: 44),
                const SizedBox(height: 6),
                Text(
                  badge.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.2),
                ),
                const SizedBox(height: 1),
                Text(
                  badgeTierName(badge.tier),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.2, color: badgeTierColor(badge.tier)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
