import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../application/badges_providers.dart';
import '../domain/badges.dart';
import 'tier_badge_image.dart';

/// Size of a badge in the profile's row: small, like an icon (0.3.56; the
/// 0.3.55 cards with names were "way too big").
const kHonourIconSize = 34.0;

/// The profile's badge row: up to three small badge icons (the member's
/// pick, else their latest three) and "View all" at the end of the same row.
/// Everything opens the badges page (choosing which three show lives there).
///
/// Someone else's profile: nothing until they have a badge. My own page with
/// none yet: a small "Badges · View all", so the page is easy to find.
class ProfileHonourRow extends ConsumerWidget {
  const ProfileHonourRow({super.key, required this.userId, required this.isMe});
  final String userId;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final honour = ref.watch(honourBadgesProvider(userId));
    final badges = honour.value ?? const <HonourBadge>[];
    void open() => context.push(Routes.badges(userId));
    if (badges.isEmpty) {
      // Mine: the link once we know there is nothing to show (a load error
      // too: the page itself says what's wrong). Theirs: no row at all.
      if (!isMe || (!honour.hasValue && !honour.hasError)) return const SizedBox.shrink();
      return HonourRow(badges: const [], onOpen: open);
    }
    return HonourRow(badges: badges, onOpen: open);
  }
}

/// Icons left to right, then "View all". With no [badges]: "Badges · View all".
class HonourRow extends StatelessWidget {
  const HonourRow({super.key, required this.badges, required this.onOpen});
  final List<HonourBadge> badges;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final shown = badges.take(kHonourMax).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          if (shown.isEmpty)
            Text('Badges', maxLines: 1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary))
          else
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              HonourIcon(badge: shown[i], onTap: onOpen),
            ],
          if (shown.isEmpty)
            Text('  ·  ', style: TextStyle(fontSize: 13, color: AppColors.textMuted))
          else
            const SizedBox(width: 10),
          Flexible(child: _ViewAll(onTap: onOpen)),
        ],
      ),
    );
  }
}

/// One badge: the tier art alone, no card, no name (long-press says which).
class HonourIcon extends StatelessWidget {
  const HonourIcon({super.key, required this.badge, this.onTap, this.size = kHonourIconSize});
  final HonourBadge badge;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = '${badge.name} · ${badgeTierName(badge.tier)}';
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: onTap != null,
        label: '${badge.name} badge, ${badgeTierName(badge.tier)}',
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('honour-${badge.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: TierBadgeImage(id: badge.id, tier: badge.tier, size: size),
        ),
      ),
    );
  }
}

/// The app's text link (brand red), with a small caret.
class _ViewAll extends StatelessWidget {
  const _ViewAll({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'View all badges',
        excludeSemantics: true,
        child: GestureDetector(
          key: const Key('honour-view-all'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(
                  child: Text('View all', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brand)),
                ),
                const SizedBox(width: 2),
                const Icon(AppIcons.caretRight, size: 12, color: AppColors.brand),
              ],
            ),
          ),
        ),
      );
}
