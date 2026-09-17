import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../social/application/community_providers.dart';
import '../../social/domain/club.dart';
import '../../vendors/domain/vendor.dart';

/// Which hat I'm wearing. The Me tab, the create sheet and new posts/meets
/// follow it. Personal is the default and it resets when the user changes.
sealed class ActiveAccount {
  const ActiveAccount();
}

class PersonalAccount extends ActiveAccount {
  const PersonalAccount();
}

class ClubAccount extends ActiveAccount {
  const ClubAccount(this.club);
  final Club club;
}

class PartnerAccount extends ActiveAccount {
  const PartnerAccount(this.vendor);
  final Vendor vendor;
}

/// TT Spot staff view: queues, reports, members, platform settings.
class AdminAccount extends ActiveAccount {
  const AdminAccount();
}

class ActiveAccountNotifier extends Notifier<ActiveAccount> {
  @override
  ActiveAccount build() {
    ref.watch(currentUserIdProvider);
    return const PersonalAccount();
  }

  void set(ActiveAccount a) => state = a;
}

final activeAccountProvider = NotifierProvider<ActiveAccountNotifier, ActiveAccount>(ActiveAccountNotifier.new);

/// Clubs I own or help run: the ones I can switch into.
final managedClubsProvider = FutureProvider<List<Club>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  final clubs = await ref.watch(myClubsProvider.future);
  final roles = await ref.watch(myClubRolesProvider.future);
  return clubs.where((c) => c.ownerId == me || const {'owner', 'vp', 'secretary'}.contains(roles[c.id])).toList();
});

/// The club new posts and meets belong to right now (null = just me).
final actingClubIdProvider = Provider<String?>((ref) => switch (ref.watch(activeAccountProvider)) {
      ClubAccount(:final club) => club.id,
      _ => null,
    });
