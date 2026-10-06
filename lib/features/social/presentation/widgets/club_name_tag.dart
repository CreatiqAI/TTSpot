import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../application/club_tag_providers.dart';
import '../../domain/club_tag.dart';
import 'club_tier_widgets.dart' show clubRoleLabel;

/// Gold of the official tier (the map list's OFFICIAL chip, the club page).
Color officialGold() => AppColors.dark ? const Color(0xFFE6B422) : const Color(0xFFB8860B);
Color officialGoldTint() => const Color(0xFFD4A017).withValues(alpha: 0.14);

/// The official club tag beside a name: the club's crest and its name in a
/// small gold pill. Tap it for the club ("President of …", View club).
///
/// Only official clubs have one; the server decides who wears it (the
/// president always, members who opt in), so a null [tag] draws nothing.
/// [compact] = the crest alone, for tight spots like the club members strip.
///
/// Put it after a Flexible name in a Row: it keeps its own width (the club
/// name ellipsizes at [maxWidth]) and the person's name gives way.
class ClubNameTag extends StatelessWidget {
  const ClubNameTag({super.key, required this.tag, this.compact = false, this.maxWidth = 112});
  final ClubTag? tag;
  final bool compact;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = tag;
    if (t == null) return const SizedBox.shrink();
    final gold = officialGold();
    final crest = UserAvatar(url: t.avatarUrl, name: t.name, size: compact ? 16 : 14, fallbackAsset: crestAsset(t.clubId));
    return Semantics(
      button: true,
      label: '${t.name}, official club',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('club-tag-${t.clubId}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => showClubTagSheet(context, t),
        child: compact
            ? Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(shape: BoxShape.circle, color: gold),
                child: crest,
              )
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(2, 2, 7, 2),
                  decoration: BoxDecoration(color: officialGoldTint(), borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      crest,
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // Grows a little with large text, then stays a tag.
                          textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.2, color: gold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// [ClubNameTag] for someone whose profile row came without the tag (the
/// profile header): asks the server once per person. [known] skips the call.
class ClubNameTagFor extends ConsumerWidget {
  const ClubNameTagFor({super.key, required this.userId, this.known, this.compact = false});
  final String userId;
  final ClubTag? known;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tag = known ?? ref.watch(clubTagProvider(userId)).value;
    return ClubNameTag(tag: tag, compact: compact);
  }
}

/// What the tag means: the club, the person's role in it, View club.
Future<void> showClubTagSheet(BuildContext context, ClubTag tag) => showModalBottomSheet<void>(
  useRootNavigator: true, // above the shell tab bar
  context: context,
  showDragHandle: true,
  builder: (ctx) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UserAvatar(url: tag.avatarUrl, name: tag.name, size: 52, borderColor: officialGold(), fallbackAsset: crestAsset(tag.clubId)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(AppIcons.sealCheck, size: 14, color: officialGold()),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Official club · ${tag.isPresident ? 'President' : clubRoleLabel(tag.role)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: officialGold()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tag.isPresident ? 'Runs ${tag.name}, an official TT Spot club. Presidents of official clubs carry the club tag.' : 'A member of ${tag.name}, an official TT Spot club, wearing its tag.',
            style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          SecondaryButton(
            label: 'View club',
            icon: AppIcons.usersThree,
            onPressed: () {
              Navigator.pop(ctx);
              context.push(Routes.club(tag.clubId));
            },
          ),
        ],
      ),
    ),
  ),
);
