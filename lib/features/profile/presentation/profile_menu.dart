import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/features.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../social/application/community_providers.dart';
import '../../vendors/application/vendors_providers.dart';

/// The "Me" menu. Opened from the profile's hamburger and by tapping the Me
/// tab a second time. Grouped so the long list reads as sections.
Future<void> showProfileMenu(BuildContext context, WidgetRef ref) async {
  // Make sure we know whether I'm a partner / club owner before the sheet renders.
  try {
    await ref.read(myVendorProvider.future);
    await ref.read(myClubsProvider.future);
  } catch (_) {}
  if (!context.mounted) return;

  final profile = ref.read(currentProfileProvider).value;
  final isAdmin = profile?.isAdmin ?? false;
  final canRunClubs = profile?.canRunClubs ?? false;
  final isVendor = ref.read(myVendorProvider).value != null;

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.82),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Group('ACCOUNT'),
              _Item(AppIcons.pencilSimple, 'Edit profile', 'edit'),
              _Item(AppIcons.car, 'Add a car', 'car'),
              _Item(AppIcons.users, 'Friends', 'friends'),
              _Item(AppIcons.qrCode, 'My QR', 'qr'),
              _Group('REWARDS'),
              _Item(AppIcons.star, 'Points', 'points'),
              _Item(AppIcons.gift, 'Rewards & vouchers', 'rewards'),
              _Item(AppIcons.trophy, 'Badges', 'badges'),
              if (kSocialFeed) _Item(AppIcons.bookmarkSimple, 'Saved posts', 'saved'),
              _Group('PARTNERS & CLUBS'),
              _Item(AppIcons.storefront, isVendor ? 'Partner dashboard' : 'Become a partner', 'partner'),
              _Item(AppIcons.usersThree, canRunClubs ? 'My car club' : 'Run a car club', 'club'),
              if (isAdmin) ...[
                _Group('ADMIN'),
                _Item(AppIcons.shieldCheck, 'Review queue', 'review'),
                _Item(AppIcons.handshake, 'Partner applications', 'partners'),
                _Item(AppIcons.chartBar, 'Commission report', 'commission'),
              ],
              const Divider(height: 16),
              _Item(AppIcons.signOut, 'Log out', 'logout', danger: true),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  final me = ref.read(currentUserIdProvider);
  switch (action) {
    case 'edit':
      context.push(Routes.editProfile);
    case 'friends':
      context.push(Routes.friends);
    case 'saved':
      context.push(Routes.saved);
    case 'badges':
      if (me != null) context.push(Routes.badges(me));
    case 'points':
      context.push(Routes.points);
    case 'review':
      context.push(Routes.adminReview);
    case 'rewards':
      context.push(Routes.rewards);
    case 'partner':
      context.push(isVendor ? Routes.vendor : Routes.partnerApply);
    case 'club':
      if (canRunClubs) {
        final owned = (ref.read(myClubsProvider).value ?? const []).where((c) => c.ownerId == me).firstOrNull;
        context.push(owned == null ? Routes.createClub : Routes.club(owned.id));
      } else {
        context.push(Routes.clubApply);
      }
    case 'partners':
      context.push(Routes.adminPartners);
    case 'commission':
      context.push(Routes.adminCommission);
    case 'qr':
      context.push(Routes.myQr);
    case 'car':
      context.push(Routes.newCar);
    case 'logout':
      await ref.read(authControllerProvider.notifier).signOut();
  }
}

class _Group extends StatelessWidget {
  const _Group(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

class _Item extends StatelessWidget {
  const _Item(this.icon, this.label, this.value, {this.danger = false});
  final IconData icon;
  final String label;
  final String value;
  final bool danger;
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        leading: Icon(icon, color: danger ? AppColors.danger : AppColors.textPrimary),
        title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: danger ? AppColors.danger : AppColors.textPrimary)),
        trailing: danger ? null : const Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
        onTap: () => Navigator.pop(context, value),
      );
}
