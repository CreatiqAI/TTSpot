import 'package:flutter/material.dart';

import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/profile.dart';
import '../../../friends/domain/friend.dart';
import '../../../../core/utils/dates.dart';
import '../../../social/domain/post.dart';
import '../../domain/car.dart';

/// Identity block: centered avatar (red ring only while a moment is live),
/// name, one row of tappable numbers, two actions, bio, then the moments as
/// a row of circles. Clean: no badges, no cars up here, the garage has a tab.
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
    required this.onMoment,
    required this.onAddMoment,
    required this.onFriendAction,
    required this.onMessage,
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
  final ValueChanged<Story> onMoment;
  final VoidCallback onAddMoment;
  final VoidCallback onFriendAction;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final name = p.displayName ?? '@${p.username}';
    final where = (p.homeState ?? '').isNotEmpty ? ' · ${p.homeState}' : '';
    final live = moments.any((m) => m.isLive);
    return Column(
      children: [
        const SizedBox(height: 6),
        // ---------------------------------------------------------- avatar ---
        GestureDetector(
          onTap: onAvatar,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, color: live ? AppColors.brand : AppColors.border),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              child: UserAvatar(url: p.avatarUrl, name: name, size: 84),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.1)),
        const SizedBox(height: 3),
        Text('@${p.username}$where', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        // ----------------------------------------------------------- stats ---
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
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
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
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
                  ],
                ),
        ),
        // ------------------------------------------------------------- bio ---
        if ((p.bio ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
            child: Text(p.bio!.trim(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, height: 1.4)),
          ),
        // --------------------------------------------------------- moments ---
        if (moments.isNotEmpty || isMe)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (isMe) _MomentCircle(onTap: onAddMoment),
                  for (final m in moments) _MomentCircle(moment: m, onTap: () => onMoment(m)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// A moment as a story-style circle. No moment = the "new" tile on my own profile.
class _MomentCircle extends StatelessWidget {
  const _MomentCircle({this.moment, required this.onTap});
  final Story? moment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = moment;
    final label = m == null ? 'New' : (m.whereLabel ?? relativeShort(m.createdAt));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: m == null ? AppColors.border : (m.isLive ? AppColors.brand : AppColors.ink), width: 1.5),
                ),
                child: ClipOval(
                  child: m == null
                      ? const ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.plus, size: 22, color: AppColors.textSecondary))
                      : Image.network(m.photoUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surfaceGray)),
                ),
              ),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
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
                Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
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
    final fg = dark ? Colors.white : AppColors.textPrimary;
    final child = Material(
      color: dark ? AppColors.ink : AppColors.surfaceGray,
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
      decoration: const BoxDecoration(color: AppColors.bg, border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
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
/// model set large in the display face, a number-plate chip for the year.
class ShowroomCard extends StatelessWidget {
  const ShowroomCard({super.key, required this.car, required this.onTap});
  final Car car;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (car.cover != null)
                  Image.network(car.cover!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.ink))
                else
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2B2E36), Color(0xFF101010)]),
                    ),
                    child: Center(child: ArtIcon(AppArt.car, size: 96)),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.35, 1], colors: [Colors.transparent, Color(0xCC000000)]),
                  ),
                ),
                // checkered sliver, top-left, a nod to the logo
                Positioned(left: 0, top: 0, child: CustomPaint(size: const Size(48, 12), painter: _CheckerPainter())),
                if (car.photoUrls.length > 1)
                  Positioned(
                    top: 10,
                    right: 12,
                    child: Row(
                      children: [
                        const Icon(AppIcons.images, size: 14, color: Colors.white),
                        const SizedBox(width: 3),
                        Text('${car.photoUrls.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(car.make.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
                            Text(car.model, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppFonts.display, color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700, height: 1)),
                          ],
                        ),
                      ),
                      if (car.year != null) ...[
                        const SizedBox(width: 10),
                        _Plate(text: car.year.toString()),
                      ],
                    ],
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

/// The "park another car" card under the showroom.
class AddCarCard extends StatelessWidget {
  const AddCarCard({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Material(
          color: AppColors.surfaceGray,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: const SizedBox(
              height: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(AppIcons.plus, size: 18),
                  SizedBox(width: 8),
                  Text('Park another car', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Plate extends StatelessWidget {
  const _Plate({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(9, 3, 9, 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.ink, width: 1.5),
        ),
        child: Text(text, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.ink, height: 1.1)),
      );
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final dark = Paint()..color = AppColors.ink;
    final light = Paint()..color = Colors.white;
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), (x + y).isEven ? dark : light);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => false;
}
