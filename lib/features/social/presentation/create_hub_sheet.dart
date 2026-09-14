import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/features.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../accounts/application/active_account.dart';
import '../domain/post.dart';

/// The "+" sheet: what do you want to create? While a club account is active
/// everything here is made as the club.
Future<void> showCreateHub(BuildContext context, WidgetRef ref) {
  final account = ref.read(activeAccountProvider);
  final club = account is ClubAccount ? account.club : null;
  final clubId = club?.id;
  final asClub = clubId != null;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(club == null ? 'Create' : 'Create as ${club.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children: [
                _Tile(art: AppArt.flag, label: 'Meet', onTap: () => _go(ctx, context, Routes.createEventAs(clubId: clubId))),
                if (!asClub) _Tile(art: AppArt.camera, label: 'Moment', onTap: () => _go(ctx, context, Routes.createMoment())),
                if (!asClub) _Tile(art: AppArt.car, label: 'Car', onTap: () => _go(ctx, context, Routes.newCar)),
                if (kSocialFeed) ...[
                  _Tile(art: AppArt.picture, label: 'Post', onTap: () => _go(ctx, context, Routes.createPost(PostKind.post, clubId: clubId, asClub: asClub))),
                  _Tile(art: AppArt.eyes, label: 'Spotted', onTap: () => _go(ctx, context, Routes.createPost(PostKind.spotted, clubId: clubId, asClub: asClub))),
                  _Tile(art: AppArt.chart, label: 'Poll', onTap: () => _go(ctx, context, Routes.createPost(PostKind.poll, clubId: clubId, asClub: asClub))),
                  _Tile(art: AppArt.map, label: 'Guide', onTap: () => _go(ctx, context, Routes.createPost(PostKind.guide, clubId: clubId, asClub: asClub))),
                ],
              ],
            ),
            if (kSocialFeed && !asClub) ...[
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(backgroundColor: AppColors.surfaceGray, child: Icon(AppIcons.shield, color: AppColors.textPrimary)),
                title: const Text('Start a car club', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Apply to run one. Approved owners invite members and share the map.'),
                trailing: const Icon(AppIcons.caretRight, color: AppColors.textMuted),
                onTap: () => _go(ctx, context, Routes.clubApply),
              ),
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

class _Tile extends StatelessWidget {
  const _Tile({required this.art, required this.label, required this.onTap});
  final String art;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.border)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ArtIcon(art, size: 40),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
