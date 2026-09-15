import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/accounts/application/active_account.dart';
import '../../features/accounts/presentation/account_tab.dart';
import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/admin/presentation/admin_members_screen.dart';
import '../../features/admin/presentation/admin_queues_screen.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/social/presentation/club_events_tab.dart';
import '../../features/social/presentation/club_screen.dart';
import '../../features/social/presentation/explore_screen.dart';
import '../../features/social/presentation/inbox_screen.dart';
import '../../features/vendors/presentation/vendor_dashboard_screen.dart';

/// The four bottom-tab branches, each showing whatever the active account
/// needs there. Personal: Posts · Map · Chats · Me. Club: Club · Events ·
/// Chats · Account. Partner: Dashboard · Chats · Account. Admin: Dashboard ·
/// Members · Queues · Account. Every account has its own inbox.
class TabSlot extends ConsumerWidget {
  const TabSlot(this.index, {super.key});
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    return switch (account) {
      PersonalAccount() => switch (index) {
          0 => const ExploreScreen(),
          1 => const MapScreen(),
          2 => const InboxScreen(),
          _ => const ProfileScreen(),
        },
      ClubAccount(:final club) => switch (index) {
          0 => ClubScreen(clubId: club.id, embedded: true),
          1 => ClubEventsTab(club: club),
          2 => const InboxScreen(),
          _ => const AccountTab(),
        },
      PartnerAccount() => switch (index) {
          2 => const InboxScreen(),
          3 => const AccountTab(),
          _ => const VendorDashboardScreen(embedded: true),
        },
      AdminAccount() => switch (index) {
          0 => const AdminDashboardScreen(embedded: true),
          1 => const AdminMembersScreen(),
          2 => const AdminQueuesScreen(),
          _ => const AccountTab(),
        },
    };
  }
}

/// Which tabs the bottom bar shows for an account: branch index + look.
class TabSpec {
  const TabSpec(this.branch, this.icon, this.selectedIcon, this.label);
  final int branch;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
