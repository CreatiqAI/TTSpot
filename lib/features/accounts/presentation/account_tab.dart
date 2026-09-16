import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/application/auth_controller.dart';
import '../../social/domain/post.dart';
import '../application/active_account.dart';
import 'account_switcher.dart';

/// The last tab for a club, partner or admin account: who you are acting as,
/// the account's own tools, then the shared bits (settings, switch, log out).
class AccountTab extends ConsumerWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    final (String title, String subtitle, String? avatar, Widget avatarFallback, List<_Row> rows) = switch (account) {
      ClubAccount(:final club) => (
          club.name,
          'Car club · @${club.handle}',
          club.avatarUrl,
          const Icon(AppIcons.shield, color: AppColors.brand),
          [
            _Row(AppIcons.flagCheckered, 'New event', 'Meet, convoy or track day as ${club.name}', () => context.push(Routes.createEventAs(clubId: club.id))),
            _Row(AppIcons.image, 'Post as club', 'Photos and updates for members', () => context.push(Routes.createPost(PostKind.post, clubId: club.id, asClub: true))),
            _Row(AppIcons.usersThree, 'Members & admins', 'Invite, promote, remove', () => context.push(Routes.club(club.id))),
          ],
        ),
      PartnerAccount(:final vendor) => (
          vendor.name,
          'Partner business',
          vendor.logoUrl,
          const Icon(AppIcons.storefront, color: AppColors.brand),
          [
            _Row(AppIcons.scan, 'Redeem a voucher', 'Scan a member\'s voucher QR', () => context.push(Routes.scan)),
            _Row(AppIcons.shoppingBag, 'Products', 'Up to 5, with variants', () => context.go(Routes.map)),
            _Row(AppIcons.ticket, 'Vouchers', 'What you offer members', () => context.go(Routes.shopVouchers)),
            _Row(AppIcons.chartBar, 'Statement', 'Redemptions and commission', () => context.push(Routes.vendorReport)),
            _Row(AppIcons.storefront, 'My partner page', 'What members see', () => context.push(Routes.partner(vendor.id))),
            _Row(AppIcons.image, 'Post as ${vendor.name}', 'New stock, a build, a promo', () => context.push(Routes.createPost(PostKind.post, vendorId: vendor.id))),
            _Row(AppIcons.pencilSimple, 'Edit partner profile', 'Logo, photos, address, hours', () => context.push(Routes.vendorEdit)),
            _Row(AppIcons.flagCheckered, 'New event', 'Host a gathering at your place', () => context.push(Routes.createEventAs(vendorId: vendor.id))),
          ],
        ),
      AdminAccount() => (
          'TT Spot Admin',
          'Staff account',
          null,
          const Icon(AppIcons.shieldCheck, color: AppColors.brand),
          [
            _Row(AppIcons.sealCheck, 'Spot photo reviews', 'Sticker check-ins waiting', () => context.push(Routes.adminReview)),
            _Row(AppIcons.handshake, 'Partner & club applications', 'Approve or reject', () => context.push(Routes.adminPartners)),
            _Row(AppIcons.chartBar, 'Commission report', 'Per partner, per month', () => context.push(Routes.adminCommission)),
          ],
        ),
      PersonalAccount() => ('You', '', null, const Icon(AppIcons.user), const <_Row>[]),
    };

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Material(
              color: AppColors.surfaceGray,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () => showAccountSwitcher(context, ref),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      avatar != null
                          ? UserAvatar(url: avatar, name: title, size: 52)
                          : Container(width: 52, height: 52, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: avatarFallback),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            Text(subtitle, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      Icon(AppIcons.arrowsClockwise, size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text('Switch', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const _Head('THIS ACCOUNT'),
          for (final r in rows)
            ListTile(
              leading: Icon(r.icon, color: AppColors.textPrimary),
              title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: Text(r.subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
              onTap: r.onTap,
            ),
          const _Head('GENERAL'),
          ListTile(
            leading: Icon(AppIcons.user, color: AppColors.textPrimary),
            title: const Text('Back to my profile', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            onTap: () => ref.read(activeAccountProvider.notifier).set(const PersonalAccount()),
          ),
          ListTile(
            leading: Icon(AppIcons.gear, color: AppColors.textPrimary),
            title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            onTap: () => context.push(Routes.settings),
          ),
          ListTile(
            leading: const Icon(AppIcons.signOut, color: AppColors.danger),
            title: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: AppColors.danger)),
            onTap: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class _Row {
  const _Row(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
