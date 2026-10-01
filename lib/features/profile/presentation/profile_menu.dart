import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_tab_bar.dart';
import '../../accounts/application/active_account.dart';
import '../../accounts/presentation/account_switcher.dart';
import '../../auth/presentation/widgets/confirm_logout.dart';
import '../../auth/data/auth_repository.dart';
import '../../social/application/community_providers.dart';
import '../../vendors/application/vendors_providers.dart';

/// The "Me" menu. Opened from the profile's hamburger and by tapping the Me
/// tab a second time. Two layers: the everyday things on top, the rest one
/// tap away under More.
Future<void> showProfileMenu(BuildContext context, WidgetRef ref) async {
  // Make sure we know whether I'm a partner / club owner before the sheet renders.
  try {
    await Future.wait([
      ref.read(myVendorProvider.future),
      ref.read(myClubsProvider.future),
      ref.read(managedClubsProvider.future),
    ]);
  } catch (_) {}
  if (!context.mounted) return;

  final profile = ref.read(currentProfileProvider).value;
  final isAdmin = profile?.isAdmin ?? false;
  final canRunClubs = profile?.canRunClubs ?? false;
  final isVendor = ref.read(myVendorProvider).value != null;
  // Personal + every club I run + my shop + the admin desk.
  final accounts = 1 + (ref.read(managedClubsProvider).value?.length ?? 0) + (isVendor ? 1 : 0) + (isAdmin ? 1 : 0);

  final action = await showModalBottomSheet<String>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
      child: ProfileMenuSheet(
        isAdmin: isAdmin,
        isVendor: isVendor,
        canRunClubs: canRunClubs,
        canSwitch: accounts > 1,
        // Clear of the floating tab bar: the last row never sits where the
        // Me tab is, so a second tap on it cannot hit Log out.
        bottomPadding: GlassTabBar.height + GlassTabBar.margin.bottom + MediaQuery.paddingOf(ctx).bottom,
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  final me = ref.read(currentUserIdProvider);
  switch (action) {
    case 'switch':
      await showAccountSwitcher(context, ref);
    case 'settings':
      context.push(Routes.settings);
    case 'edit':
      context.push(Routes.editProfile);
    case 'friends':
      context.push(Routes.friends);
    case 'moments':
      context.push(Routes.myMoments);
    case 'saved':
      context.push(Routes.saved);
    case 'badges':
      if (me != null) context.push(Routes.badges(me));
    case 'points':
      context.push(Routes.points);
    case 'cards':
      context.push(Routes.cards);
    case 'partner':
      context.push(isVendor ? Routes.vendor : Routes.partnerApply);
    case 'club':
      if (canRunClubs) {
        final owned = (ref.read(myClubsProvider).value ?? const []).where((c) => c.ownerId == me).firstOrNull;
        context.push(owned == null ? Routes.createClub : Routes.club(owned.id));
      } else {
        context.push(Routes.clubApply);
      }
    case 'organizer':
      context.push(Routes.organizerApply);
    case 'admin':
      ref.read(activeAccountProvider.notifier).set(const AdminAccount());
    case 'invite':
      context.push(Routes.myQr);
    case 'logout':
      await confirmLogout(context, ref);
  }
}

/// The menu itself; pops with the picked action's id.
class ProfileMenuSheet extends StatefulWidget {
  const ProfileMenuSheet({super.key, required this.isAdmin, required this.isVendor, required this.canRunClubs, required this.canSwitch, this.bottomPadding = 0});
  final bool isAdmin;
  final bool isVendor;
  final bool canRunClubs;
  /// More than one account (a club I run, my shop, the admin desk).
  final bool canSwitch;
  final double bottomPadding;

  @override
  State<ProfileMenuSheet> createState() => _ProfileMenuSheetState();
}

class _ProfileMenuSheetState extends State<ProfileMenuSheet> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final page = _more ? _morePage() : _topPage();
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(position: Tween(begin: Offset(_more ? 0.06 : -0.06, 0), end: Offset.zero).animate(a), child: child),
          ),
          layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
          child: KeyedSubtree(key: ValueKey(_more), child: page),
        ),
      ),
    );
  }

  Widget _topPage() => Column(
        key: const Key('menu-top'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.canSwitch) const _Item(AppIcons.arrowsClockwise, 'Switch account', 'switch'),
          const _Item(AppIcons.gear, 'Settings', 'settings'),
          const _Item(AppIcons.pencilSimple, 'Edit profile', 'edit'),
          const _Item(AppIcons.users, 'Friends', 'friends'),
          const _Item(AppIcons.bookmarkSimple, 'Saved posts', 'saved'),
          const _Item(AppIcons.gift, 'Points & rewards', 'points'),
          const _Item(AppIcons.cards, 'Cards & blind boxes', 'cards'),
          ListTile(
            key: const Key('menu-more'),
            dense: true,
            visualDensity: const VisualDensity(vertical: -1),
            leading: Icon(AppIcons.dotsThree, color: AppColors.textPrimary),
            title: Text('More', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            subtitle: Text('Moments, invites, badges, clubs, partners', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            onTap: () => setState(() => _more = true),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          const SizedBox(height: 6),
          const _Item(AppIcons.signOut, 'Log out', 'logout', danger: true),
          const SizedBox(height: 8),
        ],
      );

  Widget _morePage() => Column(
        key: const Key('menu-more-page'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 20, 4),
            child: Row(
              children: [
                IconButton(key: const Key('menu-back'), tooltip: 'Back', icon: const Icon(AppIcons.arrowLeft), onPressed: () => setState(() => _more = false)),
                const SizedBox(width: 4),
                const Text('More', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const _Group('YOU'),
          const _Item(AppIcons.camera, 'My moments', 'moments'),
          const _Item(AppIcons.userPlus, 'Invite friends', 'invite'),
          const _Item(AppIcons.trophy, 'Badges', 'badges'),
          const _Group('CLUBS & PARTNERS'),
          _Item(AppIcons.usersThree, widget.canRunClubs ? 'My car club' : 'Run a car club', 'club'),
          _Item(AppIcons.storefront, widget.isVendor ? 'Partner dashboard' : 'Become a partner', 'partner'),
          const _Item(AppIcons.sealCheck, 'Apply to be an organizer', 'organizer'),
          if (widget.isAdmin) ...[
            const _Group('ADMIN'),
            const _Item(AppIcons.shieldCheck, 'Switch to TT Spot Admin', 'admin'),
          ],
          const SizedBox(height: 8),
        ],
      );
}

class _Group extends StatelessWidget {
  const _Group(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
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
        key: Key('menu-$value'),
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        leading: Icon(icon, color: danger ? AppColors.danger : AppColors.textPrimary),
        title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: danger ? AppColors.danger : AppColors.textPrimary)),
        trailing: danger ? null : Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
        onTap: () => Navigator.pop(context, value),
      );
}
