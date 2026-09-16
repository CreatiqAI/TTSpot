import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/friends/application/friends_providers.dart';
import '../../features/profile/presentation/profile_menu.dart';
import '../../features/social/application/chat_providers.dart';
import '../../features/social/application/notification_providers.dart';
import '../theme/app_icons.dart';
import '../../features/accounts/application/active_account.dart';
import 'tab_slot.dart';
import '../widgets/glass_tab_bar.dart';
import '../../features/admin/application/admin_providers.dart';
import '../../features/vendors/application/vendors_providers.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/application/account_basics.dart';

/// Bottom tabs: Posts · Map · Chats · Me. Creating things happens from the
/// "+" on the Posts page and the action row on the map.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(locationPublisherProvider.notifier).start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Back from the background: an admin may have approved a partner or club since.
    ref.invalidate(myVendorProvider);
    ref.invalidate(managedClubsProvider);
    ref.invalidate(currentProfileProvider);
    ref.invalidate(accountBasicsProvider);
  }

  static const _personal = [
    TabSpec(0, AppIcons.house, AppIcons.houseFill, 'Posts'),
    TabSpec(1, AppIcons.mapTrifold, AppIcons.mapTrifoldFill, 'Map'),
    TabSpec(2, AppIcons.chatCircle, AppIcons.chatCircleFill, 'Chats'),
    TabSpec(3, AppIcons.user, AppIcons.userFill, 'Me'),
  ];
  static const _club = [
    TabSpec(0, AppIcons.shield, AppIcons.shieldFill, 'Club'),
    TabSpec(1, AppIcons.flagCheckered, AppIcons.flagCheckeredFill, 'Events'),
    TabSpec(2, AppIcons.chatCircle, AppIcons.chatCircleFill, 'Chats'),
    TabSpec(3, AppIcons.gear, AppIcons.gear, 'Account'),
  ];
  static const _partner = [
    TabSpec(0, AppIcons.storefront, AppIcons.storefront, 'Overview'),
    TabSpec(1, AppIcons.shoppingBag, AppIcons.shoppingBag, 'Products'),
    TabSpec(4, AppIcons.ticket, AppIcons.ticket, 'Vouchers'),
    TabSpec(2, AppIcons.chatCircle, AppIcons.chatCircleFill, 'Chats'),
    TabSpec(3, AppIcons.gear, AppIcons.gear, 'Account'),
  ];
  static const _admin = [
    TabSpec(0, AppIcons.gauge, AppIcons.gauge, 'Dashboard'),
    TabSpec(1, AppIcons.usersThree, AppIcons.usersThree, 'Members'),
    TabSpec(2, AppIcons.listChecks, AppIcons.listChecks, 'Queues'),
    TabSpec(3, AppIcons.gear, AppIcons.gear, 'Account'),
  ];

  List<TabSpec> _tabsFor(ActiveAccount a) => switch (a) {
        PersonalAccount() => _personal,
        ClubAccount() => _club,
        PartnerAccount() => _partner,
        AdminAccount() => _admin,
      };

  @override
  Widget build(BuildContext context) {
    final shell = widget.navigationShell;
    final account = ref.watch(activeAccountProvider);
    final tabs = _tabsFor(account);
    ref.listen(activeAccountProvider, (_, next) {
      // New hat: start on its first tab, with fresh numbers.
      if (next is AdminAccount) {
        ref.invalidate(adminStatsProvider);
        ref.invalidate(adminReportsProvider);
        ref.invalidate(adminUsersProvider);
        ref.invalidate(adminSuggestionsProvider);
        ref.invalidate(adminPartnerQueueProvider);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => shell.goBranch(_tabsFor(next).first.branch));
    });
    final unread = (ref.watch(unreadMessagesProvider).value ?? 0) + (account is PersonalAccount ? (ref.watch(unreadNotificationsProvider).value ?? 0) : 0);
    var selected = tabs.indexWhere((t) => t.branch == shell.currentIndex);
    if (selected < 0) selected = 0;
    return Scaffold(
      body: shell,
      extendBody: true,
      bottomNavigationBar: GlassTabBar(
        tabs: [
          for (final t in tabs) GlassTab(icon: t.icon, selectedIcon: t.selectedIcon, label: t.label, badge: t.branch == 2 ? unread : 0),
        ],
        selected: selected,
        onTap: (i) {
          final t = tabs[i];
          // Me tab tapped while already on it: open the menu, no hamburger needed.
          if (account is PersonalAccount && t.branch == 3 && shell.currentIndex == 3) {
            showProfileMenu(context, ref);
            return;
          }
          shell.goBranch(t.branch, initialLocation: t.branch == shell.currentIndex);
        },
      ),
    );
  }
}
