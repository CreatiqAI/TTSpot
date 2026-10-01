import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/features.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/widgets/sheet_header.dart';
import '../../../core/widgets/swipe_sheet_body.dart';
import '../../map/presentation/widgets/tt_now_sheet.dart';
import '../../accounts/application/active_account.dart';
import '../domain/post.dart';

/// The "+" sheet. Only the things people make every day sit on top; the
/// rest waits behind "More" (it opens in place).
/// * Personal: TT NOW (the hero), Post, Moment, Plan a TT session.
/// * Club: Post as the club, Plan a club meet.
/// * Partner: Post as the shop, Plan an event.
Future<void> showCreateHub(BuildContext context, WidgetRef ref) {
  final account = ref.read(activeAccountProvider);
  return showModalBottomSheet<void>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true, // keep the handle clear of the status bar, where a swipe down opens the system shade
    builder: (ctx) => SafeArea(
      // Swipe down anywhere (content at the top) to close; the X stays for those who don't.
      child: SwipeSheetBody(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: CreateHubContent(
          account: account,
          onRoute: (route) {
            Navigator.of(ctx).pop();
            context.push(route);
          },
          onTtNow: () {
            Navigator.of(ctx).pop();
            showTtNowSheet(context);
          },
        ),
      ),
    ),
  );
}

/// What the Create sheet shows for [account]. [onRoute] opens a page,
/// [onTtNow] the TT now sheet.
class CreateHubContent extends StatefulWidget {
  const CreateHubContent({super.key, required this.account, required this.onRoute, required this.onTtNow});
  final ActiveAccount account;
  final ValueChanged<String> onRoute;
  final VoidCallback onTtNow;

  @override
  State<CreateHubContent> createState() => _CreateHubContentState();
}

class _CreateHubContentState extends State<CreateHubContent> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final club = account is ClubAccount ? account.club : null;
    final vendor = account is PartnerAccount ? account.vendor : null;
    final clubId = club?.id;
    final go = widget.onRoute;

    final List<Widget> top;
    final List<Widget> more;
    if (club != null) {
      top = [
        _BigPair(
          left: _Big(
            key: const Key('create-post'),
            icon: AppIcons.image,
            title: 'Post',
            subtitle: 'As ${club.name}',
            accent: const Color(0xFF3B6FE0),
            titi: TitiPose.camera,
            onTap: () => go(Routes.createPost(PostKind.post, clubId: clubId, asClub: true)),
          ),
          right: _Big(
            key: const Key('create-plan'),
            icon: AppIcons.flagCheckered,
            title: 'Club meet',
            subtitle: 'Meet, convoy, track day',
            accent: AppColors.brand,
            titi: TitiPose.calendar,
            onTap: () => go(Routes.createEventAs(clubId: clubId)),
          ),
        ),
      ];
      more = [
        _Row(icon: AppIcons.chartBar, title: 'Poll', subtitle: 'Ask your members', onTap: () => go(Routes.createPost(PostKind.poll, clubId: clubId, asClub: true))),
        _Row(icon: AppIcons.signpost, title: 'Guide', subtitle: 'Share your favourite route or a list of spots', onTap: () => go(Routes.createPost(PostKind.guide, clubId: clubId, asClub: true))),
        _Row(icon: AppIcons.binoculars, title: 'Spotted', subtitle: 'Saw a nice car? Let the owner claim it', onTap: () => go(Routes.createPost(PostKind.spotted, clubId: clubId, asClub: true))),
      ];
    } else if (vendor != null) {
      top = [
        _BigPair(
          left: _Big(
            key: const Key('create-post'),
            icon: AppIcons.image,
            title: 'Post',
            subtitle: 'New stock, a build, a promo',
            accent: const Color(0xFF3B6FE0),
            titi: TitiPose.camera,
            onTap: () => go(Routes.createPost(PostKind.post, vendorId: vendor.id)),
          ),
          right: _Big(
            key: const Key('create-plan'),
            icon: AppIcons.flagCheckered,
            title: 'Event',
            subtitle: 'Host a meet at your shop',
            accent: AppColors.brand,
            titi: TitiPose.calendar,
            onTap: () => go(Routes.createEventAs(vendorId: vendor.id)),
          ),
        ),
      ];
      more = [
        _Row(icon: AppIcons.chartBar, title: 'Poll', subtitle: 'Ask the community', onTap: () => go(Routes.createPost(PostKind.poll, vendorId: vendor.id))),
      ];
    } else {
      final post = _Big(
        key: const Key('create-post'),
        icon: AppIcons.image,
        title: 'Post',
        subtitle: 'Photos or a video of your ride',
        accent: const Color(0xFF3B6FE0),
        titi: TitiPose.camera,
        onTap: () => go(Routes.createPost(PostKind.post)),
      );
      final moment = _Big(
        key: const Key('create-moment'),
        icon: AppIcons.camera,
        title: 'Moment',
        subtitle: 'Gone in 24 h',
        accent: const Color(0xFF8B5CF6),
        titi: TitiPose.wave,
        onTap: () => go(Routes.createMoment()),
      );
      top = [
        _TtNowHero(key: const Key('create-tt-now'), onTap: widget.onTtNow),
        const SizedBox(height: 10),
        if (kSocialFeed) _BigPair(left: post, right: moment) else moment,
        const SizedBox(height: 10),
        _Wide(
          key: const Key('create-plan'),
          icon: AppIcons.calendarBlank,
          title: 'Plan a TT session',
          subtitle: 'Pick a place and a time for later',
          titi: TitiPose.calendar,
          onTap: () => go(Routes.createEventAs(session: true)),
        ),
      ];
      more = [
        if (kSocialFeed) ...[
          _Row(icon: AppIcons.signpost, title: 'Guide', subtitle: 'Share your favourite route or a list of spots', onTap: () => go(Routes.createPost(PostKind.guide))),
          _Row(icon: AppIcons.binoculars, title: 'Spotted', subtitle: 'Saw a nice car? Let the owner claim it', onTap: () => go(Routes.createPost(PostKind.spotted))),
          _Row(icon: AppIcons.chartBar, title: 'Poll', subtitle: 'Ask the community', onTap: () => go(Routes.createPost(PostKind.poll))),
        ],
        _Row(icon: AppIcons.chatCircleDots, title: 'Ask TiTi', subtitle: 'Meets, spots, app help, car tips', onTap: () => go(Routes.titi)),
        _Row(icon: AppIcons.mapPinPlus, title: 'Suggest a spot', subtitle: 'A good mamak, carpark or road. 30 points if it goes live', onTap: () => go(Routes.suggestSpot)),
        _Row(icon: AppIcons.car, title: 'Add a car', subtitle: 'Park it in your garage', onTap: () => go(Routes.newCar)),
        _Row(icon: AppIcons.images, title: 'Moment album', subtitle: 'Group moments on your profile', onTap: () => go(Routes.newAlbum)),
        if (kSocialFeed) _Row(icon: AppIcons.shield, title: 'Start a car club', subtitle: 'Clubs and partners host public events', onTap: () => go(Routes.clubApply)),
      ];
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(title: club != null ? 'Create as ${club.name}' : vendor != null ? 'Create as ${vendor.name}' : 'Create'),
        const SizedBox(height: 14),
        ...top,
        if (more.isNotEmpty) ...[
          const SizedBox(height: 8),
          _MoreToggle(
            open: _more,
            hint: _hint(more),
            onTap: () => setState(() => _more = !_more),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _more ? Column(key: const Key('create-more-list'), children: more) : const SizedBox(width: double.infinity),
          ),
        ],
      ],
    );
  }

  /// "Guide, Spotted, Poll and more": the first few names behind More.
  static String _hint(List<Widget> rows) {
    final names = rows.whereType<_Row>().map((r) => r.title).toList();
    if (names.length <= 3) return names.join(', ');
    return '${names.take(3).join(', ')} and more';
  }
}

/// The first thing on the sheet: start a TT right now. Full width, the
/// brand red at full strength (it is the app's signature action), TiTi
/// rolling in from the right.
class _TtNowHero extends StatelessWidget {
  const _TtNowHero({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            child: Stack(
              children: [
                Positioned(right: 6, top: -4, bottom: -4, child: Titi(TitiPose.rolling, height: 104)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 120, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TT NOW', style: TextStyle(fontFamily: AppFonts.display, fontSize: 30, height: 1, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text('Out right now? Tell friends where you are.', maxLines: 2, style: TextStyle(fontSize: 12.5, height: 1.3, color: Colors.white.withValues(alpha: 0.88))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Two big tiles side by side, always the same height.
class _BigPair extends StatelessWidget {
  const _BigPair({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: 10),
            Expanded(child: right),
          ],
        ),
      );
}

/// A big, friendly tile: a soft tint of [accent] (never a solid block), the
/// icon in an accent chip, TiTi in the top-right corner, the words along the bottom.
class _Big extends StatelessWidget {
  const _Big({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap, required this.accent, required this.titi});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color accent;
  final TitiPose titi;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = Color.alphaBlend(accent.withValues(alpha: dark ? 0.20 : 0.08), dark ? AppColors.surfaceGray : Colors.white);
    final border = accent.withValues(alpha: dark ? 0.35 : 0.18);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 128),
          child: Stack(
            children: [
              Positioned(right: 0, top: 4, child: Titi(titi, height: 72)),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, size: 19, color: Colors.white),
                    ),
                    const SizedBox(height: 30),
                    Text(title, style: TextStyle(fontFamily: AppFonts.display, fontSize: 24, height: 1, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.25, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width tile for planning ahead: the calendar chip, the words, TiTi
/// with his calendar on the right.
class _Wide extends StatelessWidget {
  const _Wide({super.key, required this.icon, required this.title, required this.subtitle, required this.titi, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final TitiPose titi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFFF59E0B);
    final bg = Color.alphaBlend(accent.withValues(alpha: dark ? 0.18 : 0.10), dark ? AppColors.surfaceGray : Colors.white);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: accent.withValues(alpha: dark ? 0.35 : 0.22))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, height: 1.05, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, height: 1.25, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Titi(titi, height: 52),
            ],
          ),
        ),
      ),
    );
  }
}

/// "More": the rest of the things you can make, opened in place.
class _MoreToggle extends StatelessWidget {
  const _MoreToggle({required this.open, required this.hint, required this.onTap});
  final bool open;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        key: const Key('create-more'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
                child: Icon(AppIcons.dotsThree, size: 22, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('More', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    if (!open) Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(AppIcons.caretDown, size: 18, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
        onTap: onTap,
      );
}
