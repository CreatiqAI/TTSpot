import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/friends/application/friends_providers.dart';
import '../../features/social/application/chat_providers.dart';
import '../../features/social/application/notification_providers.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    final shell = widget.navigationShell;
    final unread = (ref.watch(unreadMessagesProvider).value ?? 0) + (ref.watch(unreadNotificationsProvider).value ?? 0);
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: [
            const NavigationDestination(icon: Icon(AppIcons.house), selectedIcon: Icon(AppIcons.houseFill), label: 'Posts'),
            const NavigationDestination(icon: Icon(AppIcons.mapTrifold), selectedIcon: Icon(AppIcons.mapTrifoldFill), label: 'Map'),
            NavigationDestination(
              icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(AppIcons.chatCircle)),
              selectedIcon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(AppIcons.chatCircleFill)),
              label: 'Chats',
            ),
            const NavigationDestination(icon: Icon(AppIcons.user), selectedIcon: Icon(AppIcons.userFill), label: 'Me'),
          ],
        ),
      ),
    );
  }
}
