import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../social/application/community_providers.dart';
import '../../social/domain/club.dart';
import '../../social/presentation/widgets/club_tier_widgets.dart';
import '../../vendors/application/vendors_providers.dart';
import '../application/active_account.dart';

/// Tap the @handle on the Me tab: pick which account you're using. Personal,
/// each club you run, your partner business. One list, one tap.
Future<void> showAccountSwitcher(BuildContext context, WidgetRef ref) async {
  // Always fresh: a partner or club approval should show up the moment you open this.
  ref.invalidate(myVendorProvider);
  ref.invalidate(managedClubsProvider);
  ref.invalidate(currentProfileProvider);
  try {
    await Future.wait([
      ref.read(managedClubsProvider.future),
      ref.read(myVendorProvider.future),
    ]);
  } catch (_) {}
  if (!context.mounted) return;

  final me = ref.read(currentUserIdProvider);
  final profile = ref.read(currentProfileProvider).value;
  final clubs = ref.read(managedClubsProvider).value ?? const <Club>[];
  final roles = ref.read(myClubRolesProvider).value ?? const <String, String>{};
  final vendor = ref.read(myVendorProvider).value;
  final active = ref.read(activeAccountProvider);
  final canRunClubs = profile?.canRunClubs ?? false;
  final ownsAClub = clubs.any((c) => c.ownerId == me);

  final picked = await showModalBottomSheet<ActiveAccount?>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Switch account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          _Row(
            avatar: UserAvatar(url: profile?.avatarUrl, name: profile?.displayName ?? profile?.username, size: 44),
            title: profile?.displayName ?? '@${profile?.username ?? ''}',
            subtitle: 'Personal',
            selected: active is PersonalAccount,
            onTap: () => Navigator.pop(ctx, const PersonalAccount()),
          ),
          for (final c in clubs)
            _Row(
              avatar: UserAvatar(url: c.avatarUrl, name: c.name, size: 44),
              title: c.name,
              subtitle: 'Car club · ${clubRoleLabel(c.ownerId == me ? 'owner' : (roles[c.id] ?? 'member'))}',
              selected: active is ClubAccount && active.club.id == c.id,
              onTap: () => Navigator.pop(ctx, ClubAccount(c)),
            ),
          if (profile?.isAdmin ?? false)
            _Row(
              avatar: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                child: const Icon(AppIcons.shieldCheck, color: AppColors.brand, size: 22),
              ),
              title: 'TT Spot Admin',
              subtitle: 'Queues, reports, members',
              selected: active is AdminAccount,
              onTap: () => Navigator.pop(ctx, const AdminAccount()),
            ),
          if (vendor != null)
            _Row(
              avatar: UserAvatar(url: vendor.logoUrl, name: vendor.name, size: 44),
              title: vendor.name,
              subtitle: 'Partner',
              selected: active is PartnerAccount,
              onTap: () => Navigator.pop(ctx, PartnerAccount(vendor)),
            ),
          const Divider(height: 16),
          if (!ownsAClub)
            ListTile(
              leading: const Icon(AppIcons.plusCircle),
              title: Text(canRunClubs ? 'Create your car club' : 'Start a car club', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(canRunClubs ? 'You\'re approved. Set it up now.' : 'Apply to run one. Admins approve it.', style: const TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                context.push(canRunClubs ? Routes.createClub : Routes.clubApply);
              },
            ),
          if (vendor == null)
            ListTile(
              leading: const Icon(AppIcons.storefront),
              title: const Text('Become a partner', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Workshops, accessories, detailing. Offer vouchers.', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                context.push(Routes.partnerApply);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (picked != null) ref.read(activeAccountProvider.notifier).set(picked);
}

class _Row extends StatelessWidget {
  const _Row({required this.avatar, required this.title, required this.subtitle, required this.selected, required this.onTap});
  final Widget avatar;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: avatar,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: selected ? const Icon(AppIcons.checkCircleFill, color: AppColors.brand) : null,
        onTap: onTap,
      );
}
