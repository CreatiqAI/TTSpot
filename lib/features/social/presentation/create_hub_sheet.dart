import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/features.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
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
            Text(club != null ? 'Create as ${club.name}' : vendor != null ? 'Create as ${vendor.name}' : 'Create', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Big(
                    icon: organiser ? AppIcons.flagCheckered : AppIcons.coffee,
                    title: organiser ? 'Event' : 'TT session',
                    subtitle: organiser ? 'Meet, convoy, track day' : 'Plan one for later',
                    dark: true,
                    onTap: () => _go(ctx, context, Routes.createEventAs(clubId: clubId, vendorId: vendor?.id, session: !organiser)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Big(
                    icon: AppIcons.camera,
                    title: 'Moment',
                    subtitle: asClub ? 'Personal only' : 'Photo, gone in 24 h',
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

class _Big extends StatelessWidget {
  const _Big({required this.icon, required this.title, required this.subtitle, required this.onTap, this.dark = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final off = onTap == null;
    final fg = dark ? Colors.white : AppColors.textPrimary;
    return Material(
      color: dark ? AppColors.ink : AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Opacity(
          opacity: off ? 0.45 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: dark ? AppColors.brand : Colors.white, shape: BoxShape.circle),
                  child: Icon(icon, size: 20, color: dark ? Colors.white : AppColors.brand),
                ),
                const SizedBox(height: 14),
                Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: fg)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: dark ? Colors.white70 : AppColors.textSecondary)),
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
          decoration: const BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: const Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
        onTap: onTap,
      );
}
