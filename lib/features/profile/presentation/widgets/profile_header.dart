import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/profile.dart';
import '../../../friends/domain/friend.dart';
import '../../../social/domain/post.dart';
import '../../domain/car.dart';
import '../user_garage_screen.dart' show garageTitle;

/// Identity block, about the person: avatar beside the numbers (my points
/// get their own card under them), name, handle, bio, the actions. Under
/// them one garage row: My garage on my page, "Keith's garage" on someone
/// else's (hidden when they have no cars).
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.profile,
    required this.isMe,
    required this.cars,
    required this.stats,
    required this.friendCount,
    required this.points,
    required this.moments,
    required this.friendship,
    required this.onMeets,
    required this.onFriends,
    required this.onPoints,
    required this.onEdit,
    required this.onRewards,
    required this.onQr,
    required this.onAvatar,
    required this.onGarage,
    required this.onFriendAction,
    required this.onMessage,
    this.onCall,
  });

  final Profile profile;
  final bool isMe;
  final List<Car> cars;
  final ProfileStats? stats;
  final int? friendCount;
  final int? points;
  final List<Story> moments;
  final FriendshipStatus friendship;
  final VoidCallback onMeets;
  final VoidCallback? onFriends;
  final VoidCallback onPoints;
  final VoidCallback onEdit;
  final VoidCallback onRewards;
  final VoidCallback onQr;
  final VoidCallback onAvatar;
  /// My garage on my page, their read-only garage on someone else's.
  final VoidCallback onGarage;
  final VoidCallback onFriendAction;
  final VoidCallback onMessage;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final name = p.displayName ?? '@${p.username}';
    final where = (p.homeState ?? '').isNotEmpty ? ' · ${p.homeState}' : '';
    final live = moments.any((m) => m.isLive);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ------------------------------------------------- avatar + stats ---
        // Same 16 px gutter both sides; the numbers and the points card share
        // one column, so their edges line up.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              // 88 across in all: a brand ring when a moment is live.
              GestureDetector(
                onTap: onAvatar,
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: live ? AppColors.brand : Colors.transparent),
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.bg),
                    child: UserAvatar(url: p.avatarUrl, name: name, seed: p.id, size: 78),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _Stat(value: stats?.went, label: 'Meets', onTap: onMeets),
                        _Stat(value: friendCount, label: 'Friends', onTap: onFriends),
                        _Stat(value: stats?.cars ?? cars.length, label: 'Cars'),
                      ],
                    ),
                    if (points != null) ...[
                      const SizedBox(height: 8),
                      Center(child: _PointsCard(points: points!, onTap: onPoints)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        // -------------------------------------------------------- identity ---
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 1, 16, 0),
          child: Text('@${p.username}$where', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        ),
        // ------------------------------------------------------------- bio ---
        if ((p.bio ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(p.bio!.trim(), style: const TextStyle(fontSize: 13.5, height: 1.4)),
          ),
        // --------------------------------------------------------- actions ---
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: isMe
              ? Row(
                  children: [
                    Expanded(child: _Action(label: 'Edit profile', onTap: onEdit, dark: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _Action(label: 'Rewards', icon: AppIcons.gift, onTap: onRewards)),
                    const SizedBox(width: 8),
                    _Action(icon: AppIcons.qrCode, onTap: onQr, tooltip: 'My QR'),
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
                    if (friendship == FriendshipStatus.friends && onCall != null) ...[
                      const SizedBox(width: 8),
                      Expanded(child: _Action(label: 'Call', icon: AppIcons.phoneCall, onTap: onCall!)),
                    ],
                  ],
                ),
        ),
        // ---------------------------------------------------------- garage ---
        if (isMe || cars.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _GarageButton(
              label: isMe ? 'My garage' : garageTitle(p),
              count: isMe ? stats?.cars ?? cars.length : cars.length,
              onTap: onGarage,
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// My points: a pill as wide as what it says, centred under the numbers.
/// Coin, balance, "points" and the arrow sit close together with the same
/// gap on either side. Tap for the Points page (history and how to earn).
class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.points, required this.onTap});
  final int points;
  final VoidCallback onTap;

  static String _grouped(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PointsCoin(size: 22),
                const SizedBox(width: 7),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(_grouped(points), style: const TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w700, height: 1, color: AppColors.brand)),
                        const SizedBox(width: 5),
                        Text('points', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(AppIcons.caretRight, size: 14, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      );
}

/// One full-width button into a garage: mine, where cars are added,
/// switched and opened, or someone else's to look through.
class _GarageButton extends StatelessWidget {
  const _GarageButton({required this.label, required this.count, required this.onTap});
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(AppIcons.garage, size: 18, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                  const SizedBox(width: 8),
                  Text(count == 0 ? 'Add your first car' : '$count ${count == 1 ? 'car' : 'cars'}', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  const SizedBox(width: 4),
                  Icon(AppIcons.caretRight, size: 14, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});
  final int? value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Text(
                  value?.toString() ?? '–',
                  style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w700, height: 1, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      );
}

class _Action extends StatelessWidget {
  const _Action({this.label, this.icon, required this.onTap, this.dark = false, this.tooltip});
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool dark;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? AppColors.onInk : AppColors.textPrimary;
    final child = Material(
      color: dark ? AppColors.textPrimary : AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          height: 40,
          width: label == null ? 40 : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) Icon(icon, size: 17, color: fg),
              if (icon != null && label != null) const SizedBox(width: 6),
              if (label != null) Text(label!, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// Sticky tab strip: icon + label, thin underline that slides between tabs.
class ProfileTabBar extends SliverPersistentHeaderDelegate {
  const ProfileTabBar({required this.tabs, required this.selected, required this.onSelect});
  final List<(IconData, String)> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  static const height = 46.0;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: AppColors.bg, border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
      child: LayoutBuilder(
        builder: (_, c) {
          final w = c.maxWidth / tabs.length;
          return Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: InkWell(
                        onTap: () => onSelect(i),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(tabs[i].$1, size: 17, color: i == selected ? AppColors.textPrimary : AppColors.textMuted),
                              const SizedBox(width: 6),
                              Text(tabs[i].$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: i == selected ? AppColors.textPrimary : AppColors.textMuted)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: w * selected + w * 0.22,
                bottom: 0,
                width: w * 0.56,
                height: 2,
                child: const DecoratedBox(decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.vertical(top: Radius.circular(2)))),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(ProfileTabBar old) => old.selected != selected || old.tabs.length != tabs.length;
}
