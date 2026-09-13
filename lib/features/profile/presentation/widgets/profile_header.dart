import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/profile.dart';
import '../../../friends/domain/friend.dart';
import '../../../social/domain/notification.dart';
import '../../domain/car.dart';

/// The garage card. A dark hero built from the member's own car photo (blurred
/// and dimmed), the name set in the display face, and the numbers that matter
/// on TT Spot: meets, friends, points. Nothing borrowed from a photo feed.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.profile,
    required this.isMe,
    required this.cars,
    required this.stats,
    required this.friendCount,
    required this.points,
    required this.streak,
    required this.badges,
    required this.friendship,
    required this.onMeets,
    required this.onFriends,
    required this.onPoints,
    required this.onBadges,
    required this.onEdit,
    required this.onAddCar,
    required this.onFriendAction,
    required this.onMessage,
  });

  final Profile profile;
  final bool isMe;
  final List<Car> cars;
  final ProfileStats? stats;
  final int? friendCount;
  final int? points;
  final int streak;
  final List<EarnedBadge> badges;
  final FriendshipStatus friendship;
  final VoidCallback onMeets;
  final VoidCallback? onFriends;
  final VoidCallback onPoints;
  final VoidCallback onBadges;
  final VoidCallback onEdit;
  final VoidCallback onAddCar;
  final VoidCallback onFriendAction;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final cover = cars.map((c) => c.cover).whereType<String>().firstOrNull;
    final name = p.displayName ?? '@${p.username}';
    final subtitle = [
      if ((p.homeState ?? '').isNotEmpty) p.homeState!,
      if (stats != null) '${stats!.cars} car${stats!.cars == 1 ? '' : 's'}',
      if (stats != null && stats!.organised > 0) '${stats!.organised} organised',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ----------------------------------------------------------- hero ---
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              child: SizedBox(
                height: 196,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: AppColors.mapBg),
                    if (cover != null)
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x66000000), Color(0xCC0F1115)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 66,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: AppFonts.display, fontSize: 40, fontWeight: FontWeight.w700, color: Colors.white, height: 1),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '@${p.username}${subtitle.isEmpty ? '' : '  ·  $subtitle'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    if (streak > 0)
                      Positioned(
                        top: 14,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const ArtIcon(AppArt.fire, size: 18),
                              const SizedBox(width: 4),
                              Text('$streak-wk streak', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // avatar overlapping the hero's bottom edge
            Positioned(
              left: 20,
              bottom: -30,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: UserAvatar(url: p.avatarUrl, name: name, size: 74),
              ),
            ),
            // the three numbers, sitting on the hero edge
            Positioned(
              right: 16,
              bottom: -26,
              child: Row(
                children: [
                  _Stat(value: stats?.went, label: 'meets', onTap: onMeets),
                  const SizedBox(width: 8),
                  _Stat(value: friendCount, label: 'friends', onTap: onFriends),
                  if (points != null) ...[
                    const SizedBox(width: 8),
                    _Stat(value: points, label: 'points', onTap: onPoints, highlight: true),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        // ------------------------------------------------------------ bio ---
        if ((p.bio ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(p.bio!.trim(), style: const TextStyle(fontSize: 14, height: 1.4)),
          ),
        // --------------------------------------------------------- badges ---
        if (badges.isNotEmpty)
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final b in badges)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: onBadges,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(6, 4, 11, 4),
                        decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          children: [
                            ArtIcon(AppArt.forEmoji(b.badge.emoji), size: 18),
                            const SizedBox(width: 5),
                            Text(b.badge.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // -------------------------------------------------------- actions ---
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: isMe
              ? Row(
                  children: [
                    Expanded(child: _Action(label: 'Edit profile', icon: AppIcons.pencilSimple, onTap: onEdit, dark: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _Action(label: 'Friends', icon: AppIcons.users, onTap: onFriends ?? () {})),
                    const SizedBox(width: 8),
                    _Action(icon: AppIcons.plus, onTap: onAddCar, tooltip: 'Add car'),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: switch (friendship) {
                        FriendshipStatus.none => _Action(label: 'Add friend', icon: AppIcons.userPlus, onTap: onFriendAction, dark: true),
                        FriendshipStatus.pendingOut => _Action(label: 'Requested', icon: AppIcons.clock, onTap: onFriendAction),
                        FriendshipStatus.pendingIn => _Action(label: 'Accept request', icon: AppIcons.userCheck, onTap: onFriendAction, dark: true),
                        FriendshipStatus.friends => _Action(label: 'Friends', icon: AppIcons.checkCircle, onTap: onFriendAction),
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _Action(label: 'Message', icon: AppIcons.chatCircle, onTap: onMessage)),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap, this.highlight = false});
  final int? value;
  final String label;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 66,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: highlight ? AppColors.warnColor : Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: Column(
            children: [
              Text(value?.toString() ?? '–', style: const TextStyle(fontFamily: AppFonts.display, fontSize: 24, fontWeight: FontWeight.w700, height: 1)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary, letterSpacing: 0.3)),
            ],
          ),
        ),
      );
}

class _Action extends StatelessWidget {
  const _Action({this.label, required this.icon, required this.onTap, this.dark = false, this.tooltip});
  final String? label;
  final IconData icon;
  final VoidCallback onTap;
  final bool dark;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : AppColors.textPrimary;
    final child = Material(
      color: dark ? AppColors.textPrimary : AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 42,
          width: label == null ? 42 : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              if (label != null) ...[const SizedBox(width: 7), Text(label!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg))],
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// Segmented switch for Garage / Moments / Posts.
class ProfileTabs extends StatelessWidget {
  const ProfileTabs({super.key, required this.tabs, required this.selected, required this.onSelect});
  final List<(IconData, String)> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onSelect(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 34,
                      decoration: BoxDecoration(
                        color: i == selected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: i == selected ? const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))] : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(tabs[i].$1, size: 16, color: i == selected ? AppColors.textPrimary : AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(tabs[i].$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: i == selected ? AppColors.textPrimary : AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}
