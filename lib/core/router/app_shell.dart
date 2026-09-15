import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/friends/application/friends_providers.dart';
import '../../features/profile/presentation/profile_menu.dart';
import '../../features/social/application/chat_providers.dart';
import '../../features/social/application/notification_providers.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../../features/accounts/application/active_account.dart';
import 'tab_slot.dart';

/// Bottom tabs: Posts · Map · Chats · Me. Creating things happens from the
/// "+" on the Posts page and the action row on the map.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(locationPublisherProvider.notifier).start());
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
    TabSpec(0, AppIcons.storefront, AppIcons.storefront, 'Dashboard'),
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
      // New hat: start on its first tab.
      WidgetsBinding.instance.addPostFrameCallback((_) => shell.goBranch(_tabsFor(next).first.branch));
    });
    final unread = (ref.watch(unreadMessagesProvider).value ?? 0) + (account is PersonalAccount ? (ref.watch(unreadNotificationsProvider).value ?? 0) : 0);
    var selected = tabs.indexWhere((t) => t.branch == shell.currentIndex);
    if (selected < 0) selected = 0;
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (i) {
            final t = tabs[i];
            // Me tab tapped while already on it: open the menu, no hamburger needed.
            if (account is PersonalAccount && t.branch == 3 && shell.currentIndex == 3) {
              showProfileMenu(context, ref);
              return;
            }
            shell.goBranch(t.branch, initialLocation: t.branch == shell.currentIndex);
          },
          destinations: [
            for (final t in tabs)
              NavigationDestination(
                icon: t.branch == 2 ? Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: Icon(t.icon)) : Icon(t.icon),
                selectedIcon: t.branch == 2 ? Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: Icon(t.selectedIcon)) : Icon(t.selectedIcon),
                label: t.label,
              ),
          ],
        ),
      ),
    );
  }
}
