import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/profile.dart';
import '../../../friends/domain/friend.dart';
import '../../../friends/presentation/nickname_sheet.dart' show ProfileNameLines;
import '../../../social/domain/post.dart';
import '../../domain/car.dart';
import '../user_garage_screen.dart' show garageTitle;
import 'profile_meets_sheet.dart';

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
    this.following,
    this.onFollow,
  });

  final Profile profile;
  final bool isMe;
  final List<Car> cars;
  final ProfileStats? stats;
  final int? friendCount;
  final int? points;
  final List<Story> moments;
  final FriendshipStatus friendship;
  /// All my meets (upcoming too), from the Meets sheet on my own page.
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

  /// Am I following them? Null while that loads (the button reads Follow).
  final bool? following;

  /// Follow / Following, beside Add friend or Requested for people who
  /// aren't my friends (friends' posts are in Following already). Hidden
  /// while they wait for me to accept (accepting is the thing to do). Null
  /// hides it too: my own page, someone I blocked.
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final name = p.displayName ?? '@${p.username}';
    final live = moments.any((m) => m.isLive);
    final showGarage = isMe || cars.isNotEmpty;
    final showFollow = !isMe && onFollow != null && (friendship == FriendshipStatus.none || friendship == FriendshipStatus.pendingOut);
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
                        // Tap: the meets the number counts (anyone's page).
                        _Stat(
                          value: stats?.went,
                          label: 'Meets',
                          onTap: () => showProfileMeetsSheet(context, userId: p.id, isMe: isMe, count: stats?.went, onSeeAll: onMeets),
                        ),
                        _Stat(value: friendCount, label: 'Friends', onTap: onFriends),
                        _Stat(value: stats?.cars ?? cars.length, label: 'Cars'),
                      ],
                    ),
                    // One row under the numbers: the garage on the left, my
                    // points on the right, the same height.
                    if (showGarage || points != null) ...[
                      const SizedBox(height: 8),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // A matched pair, equal widths, 8 px apart.
                            if (showGarage) Expanded(child: _GaragePill(label: isMe ? 'My garage' : garageTitle(p), fit: isMe, onTap: onGarage)),
                            if (showGarage && points != null) const SizedBox(width: 8),
                            if (points != null) Expanded(child: _PointsCard(points: points!, onTap: onPoints)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        // -------------------------------------------------------- identity ---
        // My nickname for them (备注) big, "Real name · @handle" under it.
        ProfileNameLines(profile: p, isMe: isMe),
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
                    // With Follow it's three across: text only (like
                    // Instagram), so the labels keep their size.
                    Expanded(
                      child: switch (friendship) {
                        FriendshipStatus.none => _Action(label: 'Add friend', icon: showFollow ? null : AppIcons.userPlus, onTap: onFriendAction, dark: true),
                        FriendshipStatus.pendingOut => _Action(label: 'Requested', icon: showFollow ? null : AppIcons.clock, onTap: onFriendAction),
                        FriendshipStatus.pendingIn => _Action(label: 'Accept request', icon: AppIcons.userCheck, onTap: onFriendAction, dark: true),
                        FriendshipStatus.friends => _Action(label: 'Friends', icon: AppIcons.checkCircle, onTap: onFriendAction),
                      },
                    ),
                    if (showFollow) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: following == true
                            ? _Action(label: 'Following', onTap: onFollow!)
                            : _Action(label: 'Follow', onTap: onFollow!, accent: true),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Expanded(child: _Action(label: 'Message', icon: showFollow ? null : AppIcons.chatCircle, onTap: onMessage)),
                    if (friendship == FriendshipStatus.friends && onCall != null) ...[
                      const SizedBox(width: 8),
                      Expanded(child: _Action(label: 'Call', icon: AppIcons.phoneCall, onTap: onCall!)),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// My points, the right half of the pair under the numbers. Tap for the
/// Points page (history and how to earn).
class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.points, required this.onTap});
  final int points;
  final VoidCallback onTap;

  static String _grouped(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) => _HeaderPill(
        color: AppColors.brand.withValues(alpha: 0.08),
        onTap: onTap,
        leading: const PointsCoin(size: 21),
        // A big balance shrinks to fit rather than wrapping.
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_grouped(points), style: const TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w700, height: 1, color: AppColors.brand)),
              const SizedBox(width: 4),
              Text('points', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
}

/// Into a garage: mine (add, switch and open cars) or someone else's to look
/// through. The twin of the points pill: the blue garage badge where the
/// coin is, the label in the same display face, tinted blue as points are red.
class _GaragePill extends StatelessWidget {
  const _GaragePill({required this.label, required this.onTap, this.fit = false});
  final String label;
  final VoidCallback onTap;
  final bool fit;

  static Color get _blue => AppColors.dark ? const Color(0xFF7FB2FF) : const Color(0xFF1D4ED8);

  @override
  Widget build(BuildContext context) => _HeaderPill(
        color: const Color(0xFF2563EB).withValues(alpha: AppColors.dark ? 0.18 : 0.09),
        onTap: onTap,
        leading: const GarageBadge(size: 21),
        // "My garage" shrinks a touch rather than lose letters; a long
        // "Muhammad Hafiz's garage" ends in "…" instead.
        label: fit
            ? FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: _style))
            : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _style),
      );

  TextStyle get _style => TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w700, height: 1, color: _blue);
}

/// The shared shape of the two pills under the numbers: tinted, rounded,
/// badge + label + arrow centred together, the same padding and height.
class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.color, required this.onTap, required this.leading, required this.label});
  final Color color;
  final VoidCallback onTap;
  final Widget leading;
  final Widget label;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                leading,
                const SizedBox(width: 5),
                Flexible(child: label),
                const SizedBox(width: 3),
                Icon(AppIcons.caretRight, size: 13, color: AppColors.textMuted),
              ],
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
  const _Action({this.label, this.icon, required this.onTap, this.dark = false, this.accent = false, this.tooltip});
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool dark;

  /// Brand red on a red tint (Follow), like the points pill.
  final bool accent;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? AppColors.onInk : accent ? AppColors.brand : AppColors.textPrimary;
    final child = Material(
      color: dark ? AppColors.textPrimary : accent ? AppColors.brand.withValues(alpha: AppColors.dark ? 0.2 : 0.1) : AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          height: 40,
          width: label == null ? 40 : null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) Icon(icon, size: 17, color: fg),
                if (icon != null && label != null) const SizedBox(width: 6),
                // A label too long for its share of the row (big text, a
                // narrow phone) shrinks to fit rather than overflow.
                if (label != null) Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label!, maxLines: 1, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)))),
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// Sticky tab strip: icon + label, a brand-red underline that slides to the
/// selected tab. The selected tab is bold and full strength, the others
/// dimmed, so it reads in light and dark.
class ProfileTabBar extends SliverPersistentHeaderDelegate {
  const ProfileTabBar({required this.tabs, required this.selected, required this.onSelect});
  final List<(IconData, String)> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  static const height = 48.0;
  static const indicatorHeight = 3.0;

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
          // expand: each tab fills the strip's full height, so the label sits
          // in the middle and the whole strip is tappable (0.3.50 had the
          // labels stuck to the top with a 20 px tap band).
          return Stack(
            fit: StackFit.expand,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: Semantics(
                        selected: i == selected,
                        button: true,
                        child: InkWell(
                          onTap: () => onSelect(i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(tabs[i].$1, size: 17, color: i == selected ? AppColors.textPrimary : AppColors.textMuted),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 180),
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: i == selected ? FontWeight.w800 : FontWeight.w500,
                                      color: i == selected ? AppColors.textPrimary : AppColors.textMuted,
                                    ),
                                    child: Text(tabs[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: w * selected + w * 0.18,
                bottom: 0,
                width: w * 0.64,
                height: indicatorHeight,
                child: const DecoratedBox(
                  key: ValueKey('profile-tab-indicator'),
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.vertical(top: Radius.circular(indicatorHeight))),
                ),
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
