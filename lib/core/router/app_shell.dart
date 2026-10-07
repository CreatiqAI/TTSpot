import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/events/application/live_activity.dart';
import '../../features/friends/application/friends_providers.dart';
import '../../features/profile/presentation/profile_menu.dart';
import '../../features/social/presentation/create_hub_sheet.dart';
import '../../features/social/application/chat_providers.dart';
import '../../features/social/application/notification_providers.dart';
import '../guide/guide.dart';
import '../theme/app_icons.dart';
import '../../features/accounts/application/active_account.dart';
import 'tab_reselect.dart';
import 'tab_slot.dart';
import '../widgets/glass_tab_bar.dart';
import '../../features/admin/application/admin_providers.dart';
import '../../features/vendors/application/vendors_providers.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/application/account_basics.dart';
import '../push/push_service.dart';
import '../supabase/supabase_client.dart';
import '../../features/map/presentation/widgets/car_marker.dart' show kToyImageWidth;
import '../../features/map/presentation/widgets/map_pins.dart' show MapPinFactory;
import '../../features/profile/application/profile_providers.dart' show userCarsProvider;
import '../../features/profile/domain/car.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationPublisherProvider.notifier).start();
      ref.read(pushServiceProvider).start();
      ref.read(liveActivityServiceProvider).sync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.read(pushServiceProvider).start(); // no-op once push is on
    // Back from the background: an admin may have approved a partner or club since.
    ref.invalidate(myVendorProvider);
    ref.invalidate(managedClubsProvider);
    ref.invalidate(currentProfileProvider);
    ref.invalidate(accountBasicsProvider);
    // Lock-screen meet countdown: end finished ones, start one that's due.
    ref.read(liveActivityServiceProvider).sync();
  }

  String? _warmToy;
  void _warmMyToy(List<Car>? cars) {
    final car = cars?.where((c) => c.isDefault).firstOrNull ?? cars?.firstOrNull;
    final url = car?.toyUrl;
    if (url == null || url == _warmToy || !mounted) return;
    _warmToy = url;
    final provider = MapPinFactory.networkProvider(url, targetWidth: kToyImageWidth, devicePixelRatio: MediaQuery.devicePixelRatioOf(context));
    precacheImage(provider, context, onError: (_, _) {}).ignore();
  }

  /// Not a branch: the centre + opens the Create sheet.
  static const _create = -1;

  static const _personal = [
    TabSpec(0, AppIcons.house, AppIcons.houseFill, 'Posts'),
    TabSpec(1, AppIcons.mapTrifold, AppIcons.mapTrifoldFill, 'Map'),
    TabSpec(_create, AppIcons.plus, AppIcons.plus, 'Create'),
    TabSpec(2, AppIcons.chatCircleDots, AppIcons.chatCircleDotsFill, 'Chats'),
    TabSpec(3, AppIcons.user, AppIcons.userFill, 'Me'),
  ];
  static const _club = [
    TabSpec(0, AppIcons.shield, AppIcons.shieldFill, 'Club'),
    TabSpec(1, AppIcons.flagCheckered, AppIcons.flagCheckeredFill, 'Events'),
    TabSpec(_create, AppIcons.plus, AppIcons.plus, 'Create'),
    TabSpec(2, AppIcons.chatCircleDots, AppIcons.chatCircleDotsFill, 'Chats'),
    TabSpec(3, AppIcons.gear, AppIcons.gear, 'Account'),
  ];
  static const _partner = [
    TabSpec(0, AppIcons.storefront, AppIcons.storefront, 'Overview'),
    TabSpec(1, AppIcons.shoppingBag, AppIcons.shoppingBag, 'Products'),
    TabSpec(4, AppIcons.ticket, AppIcons.ticket, 'Vouchers'),
    TabSpec(2, AppIcons.chatCircleDots, AppIcons.chatCircleDotsFill, 'Chats'),
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
    // My toy car, on the phone before the map is first opened, so my pin
    // goes straight to it (see MapScreen._mePin).
    final me = ref.watch(currentUserIdProvider);
    if (me != null) {
      ref.listen(userCarsProvider(me), (_, n) => _warmMyToy(n.value));
      final loaded = ref.read(userCarsProvider(me)).value;
      if (loaded != null) WidgetsBinding.instance.addPostFrameCallback((_) => _warmMyToy(loaded));
    }
    final unread =(ref.watch(unreadMessagesProvider).value ?? 0) + (account is PersonalAccount ? (ref.watch(unreadNotificationsProvider).value ?? 0) : 0);
    var selected = tabs.indexWhere((t) => t.branch == shell.currentIndex);
    if (selected < 0) selected = 0;
    final bar = GlassTabBar(
        tabs: [
          for (final t in tabs) GlassTab(icon: t.icon, selectedIcon: t.selectedIcon, label: t.label, badge: t.branch == 2 ? unread : 0, action: t.branch == _create),
        ],
        selected: selected,
        onTap: (i) {
          final t = tabs[i];
          if (t.branch == _create) {
            showCreateHub(context, ref);
            return;
          }
          // Me tab tapped while already on it: open the menu, no hamburger needed.
          if (account is PersonalAccount && t.branch == 3 && shell.currentIndex == 3) {
            showProfileMenu(context, ref);
            return;
          }
          // Home tab tapped while already on it: the feed goes back to the top and refreshes.
          if (account is PersonalAccount && t.branch == 0 && shell.currentIndex == 0) {
            ref.read(homeReselectProvider.notifier).fire();
          }
          shell.goBranch(t.branch, initialLocation: t.branch == shell.currentIndex);
        },
      );
    return Scaffold(
      body: shell,
      extendBody: true,
      bottomNavigationBar: account is PersonalAccount ? _withGuideKeys(bar, tabs) : bar,
    );
  }

  /// TiTi guides spotlight the tab buttons (GuideTabKeys). Invisible boxes
  /// laid over the bar exactly where each button's capsule sits; they
  /// ignore touches, so the bar looks and works as before.
  Widget _withGuideKeys(Widget bar, List<TabSpec> tabs) => Stack(
        children: [
          bar,
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Padding(
                  padding: GlassTabBar.margin.add(EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom)),
                  child: Row(
                    children: [
                      for (final t in tabs)
                        Expanded(
                          child: Center(
                            child: KeyedSubtree(
                              key: t.branch == _create ? GuideTabKeys.create : GuideTabKeys.forBranch(t.branch),
                              child: const SizedBox(width: 52, height: 44),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}
