import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../data/badges_repository.dart';
import '../domain/badges.dart';

/// The badges page for [userId] (tiers, counts, what's on their profile).
final badgeProgressProvider = FutureProvider.autoDispose.family<List<BadgeProgress>, String>(
  (ref, userId) => ref.watch(badgesRepositoryProvider).progress(userId),
);

/// The honour row on [userId]'s profile (empty: no row at all).
final honourBadgesProvider = FutureProvider.autoDispose.family<List<HonourBadge>, String>(
  (ref, userId) => ref.watch(badgesRepositoryProvider).honour(userId),
);

class BadgeActions {
  BadgeActions(this._ref);
  final Ref _ref;

  /// Save which badges show on my profile, in order. Empty = automatic.
  Future<void> setHonour(List<String> ids) async {
    await _ref.read(badgesRepositoryProvider).setHonour(ids.take(kHonourMax).toList());
    final me = _ref.read(currentUserIdProvider);
    if (me != null) {
      _ref.invalidate(honourBadgesProvider(me));
      _ref.invalidate(badgeProgressProvider(me));
    }
  }
}

final badgeActionsProvider = Provider<BadgeActions>((ref) => BadgeActions(ref));
