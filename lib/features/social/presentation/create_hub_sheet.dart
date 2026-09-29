import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/features.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/widgets/sheet_header.dart';
import '../../map/presentation/widgets/tt_now_sheet.dart';
import '../../accounts/application/active_account.dart';
import '../domain/post.dart';

/// The "+" sheet. Two big things first (a meet, a moment), then the rest as
/// one clean list. While a club account is active everything is made as the
/// club and the personal-only items hide.
Future<void> showCreateHub(BuildContext context, WidgetRef ref) {
  final account = ref.read(activeAccountProvider);
  final club = account is ClubAccount ? account.club : null;
  final vendor = account is PartnerAccount ? account.vendor : null;
  final clubId = club?.id;
  final asClub = clubId != null || vendor != null;
  final organiser = asClub; // clubs and partners host events; everyone else plans TT sessions
  return showModalBottomSheet<void>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader(title: club != null ? 'Create as ${club.name}' : vendor != null ? 'Create as ${vendor.name}' : 'Create'),
            const SizedBox(height: 14),
            if (!asClub) ...[
              _TtNowHero(onTap: () {
                Navigator.of(ctx).pop();
                showTtNowSheet(context);
              }),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: _Big(
                    icon: organiser ? AppIcons.flagCheckered : AppIcons.coffee,
                    title: organiser ? 'Event' : 'TT session',
                    subtitle: organiser ? 'Meet, convoy, track day' : 'Plan one for later',
                    accent: AppColors.brand,
                    titi: TitiPose.phone,
                    onTap: () => _go(ctx, context, Routes.createEventAs(clubId: clubId, vendorId: vendor?.id, session: !organiser)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Big(
                    icon: AppIcons.camera,
                    title: 'Moment',
                    subtitle: asClub ? 'Personal only' : 'Photo, gone in 24 h',
                    accent: const Color(0xFF3B6FE0),
                    titi: TitiPose.camera,
                    onTap: asClub ? null : () => _go(ctx, context, Routes.createMoment()),
                  ),
                ),
              ],
            ),
            if (kSocialFeed) ...[
              const SizedBox(height: 16),
              _Row(icon: AppIcons.image, title: 'Post', subtitle: vendor != null ? 'New stock, a build, a promo' : 'Photos of your ride or a meet', onTap: () => _go(ctx, context, Routes.createPost(PostKind.post, clubId: clubId, asClub: clubId != null, vendorId: vendor?.id))),
              if (vendor == null) _Row(icon: AppIcons.binoculars, title: 'Spotted', subtitle: 'Saw a nice car? Let the owner claim it', onTap: () => _go(ctx, context, Routes.createPost(PostKind.spotted, clubId: clubId, asClub: asClub))),
              _Row(icon: AppIcons.chartBar, title: 'Poll', subtitle: 'Ask the community', onTap: () => _go(ctx, context, Routes.createPost(PostKind.poll, clubId: clubId, asClub: clubId != null, vendorId: vendor?.id))),
              if (vendor == null) _Row(icon: AppIcons.signpost, title: 'Guide', subtitle: 'A route or a list of spots', onTap: () => _go(ctx, context, Routes.createPost(PostKind.guide, clubId: clubId, asClub: asClub))),
            ],
            if (!asClub) ...[
              const Divider(height: 20),
              _Row(icon: AppIcons.mapPinPlus, title: 'Suggest a spot', subtitle: 'A good mamak, carpark or road. 30 points if it goes live', onTap: () => _go(ctx, context, Routes.suggestSpot)),
              _Row(icon: AppIcons.car, title: 'Add a car', subtitle: 'Park it in your garage', onTap: () => _go(ctx, context, Routes.newCar)),
              _Row(icon: AppIcons.images, title: 'Moment album', subtitle: 'Group moments on your profile', onTap: () => _go(ctx, context, Routes.newAlbum)),
              if (kSocialFeed)
                _Row(icon: AppIcons.shield, title: 'Start a car club', subtitle: 'Clubs and partners host public events', onTap: () => _go(ctx, context, Routes.clubApply)),
            ],
          ],
        ),
      ),
    ),
  );
}

void _go(BuildContext sheet, BuildContext page, String route) {
  Navigator.of(sheet).pop();
  page.push(route);
}

/// The first thing on the sheet: start a TT right now. Full width, the
/// brand red at full strength (it is the app's signature action), TiTi
/// rolling in from the right.
class _TtNowHero extends StatelessWidget {
  const _TtNowHero({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 96,
            child: Stack(
              children: [
                Positioned(right: 6, top: -4, bottom: -4, child: Titi(TitiPose.rolling, height: 104)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 120, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
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

/// A big, friendly tile: a soft tint of [accent] (never a solid block), the
/// icon in an accent chip, TiTi in the top-right corner, the words along the bottom.
class _Big extends StatelessWidget {
  const _Big({required this.icon, required this.title, required this.subtitle, required this.onTap, required this.accent, required this.titi});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color accent;
  final TitiPose titi;

  @override
  Widget build(BuildContext context) {
    final off = onTap == null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = Color.alphaBlend(accent.withValues(alpha: dark ? 0.20 : 0.08), dark ? AppColors.surfaceGray : Colors.white);
    final border = accent.withValues(alpha: dark ? 0.35 : 0.18);
    return Opacity(
      opacity: off ? 0.45 : 1,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 150,
            child: Stack(
              children: [
                Positioned(right: 2, top: 4, child: Titi(titi, height: 86)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(12)),
                        child: Icon(icon, size: 19, color: Colors.white),
                      ),
                      const Spacer(),
                      Text(title, style: TextStyle(fontFamily: AppFonts.display, fontSize: 24, height: 1, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 3),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.25, color: AppColors.textSecondary)),
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
