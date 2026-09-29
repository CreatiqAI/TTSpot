import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/profile.dart';
import '../../../friends/domain/friend.dart';
import '../../../social/domain/post.dart';
import '../../domain/car.dart';

/// Identity block, about the person: avatar beside the numbers, name,
/// handle, bio, the actions, then a small strip of their cars. The full
/// garage (and picking today's car) lives on Home, Garage.
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
    required this.onAddCar,
    required this.onCar,
    required this.onManageGarage,
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
  final VoidCallback onAddCar;
  final ValueChanged<Car> onCar;
  final VoidCallback onManageGarage;
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
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
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    _Stat(value: stats?.went, label: 'Meets', onTap: onMeets),
                    _Stat(value: friendCount, label: 'Friends', onTap: onFriends),
                    _Stat(value: stats?.cars ?? cars.length, label: 'Cars'),
                    if (points != null) _Stat(value: points, label: 'Points', onTap: onPoints, accent: true),
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
        if (cars.isNotEmpty || isMe) _GarageStrip(cars: cars, isMe: isMe, onCar: onCar, onManage: onManageGarage, onAddCar: onAddCar),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// A row of small car thumbnails, the daily first. Labels sit under the
/// photos, never on them. For me: a Manage chip that opens the garage.
class _GarageStrip extends StatelessWidget {
  const _GarageStrip({required this.cars, required this.isMe, required this.onCar, required this.onManage, required this.onAddCar});
  final List<Car> cars;
  final bool isMe;
  final ValueChanged<Car> onCar;
  final VoidCallback onManage;
  final VoidCallback onAddCar;

  static const _w = 96.0;
  static const _h = 72.0;

  @override
  Widget build(BuildContext context) {
    final daily = cars.where((c) => c.isDefault).firstOrNull ?? cars.firstOrNull;
    final ordered = daily == null ? const <Car>[] : [daily, ...cars.where((c) => c.id != daily.id)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 12, 8),
          child: Row(
            children: [
              Expanded(child: Text('GARAGE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary))),
              if (isMe)
                Material(
                  color: AppColors.surfaceGray,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: InkWell(
                    onTap: onManage,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Manage', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          const SizedBox(width: 2),
                          Icon(AppIcons.caretRight, size: 13, color: AppColors.textPrimary),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: _h + 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: ordered.isEmpty ? 1 : ordered.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              if (ordered.isEmpty) return _addTile();
              final c = ordered[i];
              return GestureDetector(
                onTap: () => onCar(c),
                child: SizedBox(
                  width: _w,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: SizedBox(width: _w, height: _h, child: _thumb(c)),
                      ),
                      const SizedBox(height: 5),
                      Text(c.model, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2)),
                      if (i == 0)
                        const Text('Daily', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brand, height: 1.3)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _thumb(Car c) {
    final blank = ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(AppArt.car, size: 34)));
    final cover = c.cover;
    if (cover == null) return blank;
    return Image(image: CachedNetworkImageProvider(cover), fit: BoxFit.cover, errorBuilder: (_, _, _) => blank);
  }

  Widget _addTile() => GestureDetector(
        onTap: onAddCar,
        child: SizedBox(
          width: _w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: _w,
                height: _h,
                decoration: BoxDecoration(
                  color: AppColors.surfaceGray,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(AppIcons.plus, size: 20, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 5),
              const Text('Add a car', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2)),
            ],
          ),
        ),
      );
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
                  style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w700, height: 1, color: accent ? AppColors.brand : AppColors.textPrimary),
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
