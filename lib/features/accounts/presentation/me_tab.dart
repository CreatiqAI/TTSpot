import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/presentation/admin_dashboard_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../social/presentation/club_screen.dart';
import '../../vendors/presentation/vendor_dashboard_screen.dart';
import '../application/active_account.dart';

/// The Me tab shows whichever account is active: my profile, a club I run,
/// or my partner dashboard.
class MeTab extends ConsumerWidget {
  const MeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    return switch (account) {
      PersonalAccount() => const ProfileScreen(),
      ClubAccount(:final club) => ClubScreen(clubId: club.id, embedded: true),
      PartnerAccount() => const VendorDashboardScreen(embedded: true),
      AdminAccount() => const AdminDashboardScreen(embedded: true),
    };
  }
}
