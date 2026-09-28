import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/profile.dart';
import '../../../friends/domain/friend.dart';
import '../../../social/domain/post.dart';
import '../../domain/car.dart';

/// Identity block. The default car is the hero photo, the avatar sits on its
/// edge, then name, one row of numbers, the actions, the bio. Nothing else:
/// moments and cars have their own tabs.
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
    required this.onSwitchCar,
    required this.onAddCar,
    required this.onCar,
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
  final VoidCallback onSwitchCar;
  final VoidCallback onAddCar;
  final ValueChanged<Car> onCar;
  final VoidCallback onFriendAction;
  final VoidCallback onMessage;
  final VoidCallback? onCall;

  Car? get _car => cars.where((c) => c.isDefault).firstOrNull ?? cars.firstOrNull;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final name = p.displayName ?? '@${p.username}';
    final where = (p.homeState ?? '').isNotEmpty ? ' · ${p.homeState}' : '';
    final live = moments.any((m) => m.isLive);
    final car = _car;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ------------------------------------------------------------ hero ---
        _Hero(car: car, isMe: isMe, canSwitch: isMe && cars.length > 1, onSwitchCar: onSwitchCar, onAddCar: onAddCar, onTap: car == null ? null : () => onCar(car)),
        // -------------------------------------------------------- identity ---
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Transform.translate(
                offset: const Offset(0, -28),
                child: GestureDetector(
                  onTap: onAvatar,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: live ? AppColors.brand : AppColors.bg),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.bg),
                      child: UserAvatar(url: p.avatarUrl, name: name, size: 78),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.1)),
                      const SizedBox(height: 2),
                      Text('@${p.username}$where', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // ----------------------------------------------------------- stats ---
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          child: Row(
            children: [
              _Stat(value: stats?.went, label: 'Meets', onTap: onMeets),
              _Stat(value: friendCount, label: 'Friends', onTap: onFriends),
              _Stat(value: stats?.cars ?? cars.length, label: 'Cars'),
              if (points != null) _Stat(value: points, label: 'Points', onTap: onPoints, accent: true),
            ],
          ),
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
        // ------------------------------------------------------------- bio ---
        if ((p.bio ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(p.bio!.trim(), style: const TextStyle(fontSize: 13.5, height: 1.4)),
          ),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// The default car, full width. No car: a short quiet band with one prompt.
class _Hero extends StatelessWidget {
  const _Hero({required this.car, required this.isMe, required this.canSwitch, required this.onSwitchCar, required this.onAddCar, required this.onTap});
  final Car? car;
  final bool isMe;
  final bool canSwitch;
  final VoidCallback onSwitchCar;
  final VoidCallback onAddCar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = car;
    if (c == null) {
      return Container(
        height: 132,
        width: double.infinity,
        color: AppColors.surfaceGray,
        alignment: Alignment.center,
        child: isMe
            ? FilledButton.tonalIcon(
                onPressed: onAddCar,
                style: FilledButton.styleFrom(backgroundColor: AppColors.textPrimary, foregroundColor: AppColors.onInk),
                icon: const Icon(AppIcons.plus, size: 18),
                label: const Text('Add your ride'),
              )
            : Text('No car in the garage yet', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      );
    }
    final cover = c.cover;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 210,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover != null)
              Image(image: CachedNetworkImageProvider(cover), fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray))
            else
              ColoredBox(color: AppColors.surfaceGray, child: Center(child: Icon(AppIcons.car, size: 48, color: AppColors.textMuted))),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.18), Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
            // car name, bottom right, clear of the avatar on the left
            Positioned(
              right: 16,
              bottom: 12,
              left: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.make.toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: Colors.white70)),
                  Text(c.model, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                  if (c.year != null) Text('${c.year}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70)),
                ],
              ),
            ),
            if (canSwitch)
              Positioned(
                right: 12,
                top: 12,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    onTap: onSwitchCar,
                    borderRadius: BorderRadius.circular(999),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(12, 7, 10, 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Switch car', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.ink)),
                          SizedBox(width: 4),
                          Icon(AppIcons.caretDown, size: 13, color: AppColors.ink),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap, this.accent = false});
  final int? value;
  final String label;
  final VoidCallback? onTap;
  final bool accent;

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
                  style: TextStyle(fontFamily: AppFonts.display, fontSize: 24, fontWeight: FontWeight.w700, height: 1, color: accent ? AppColors.brand : AppColors.textPrimary),
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

/// Garage as a showroom: one wide card per car, photo with a dark fade, the
