import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../data/club_tag_repository.dart';
import '../domain/club_tag.dart';
import 'community_providers.dart';

/// The official club tag a person shows beside their name (profile header).
/// Lists read it off the author instead (`Profile.clubTag`). Null when they
/// have none, and quietly null if the server can't say.
final clubTagProvider = FutureProvider.autoDispose.family<ClubTag?, String>((ref, userId) async {
  try {
    return await ref.watch(clubTagRepositoryProvider).tagOf(userId);
  } on PostgrestException {
    return null; // a tag is decoration: never an error on the profile
  }
});

/// Am I wearing this club's tag? False when signed out or not a member.
final wearingClubTagProvider = FutureProvider.autoDispose.family<bool, String>((ref, clubId) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return false;
  return ref.watch(clubTagRepositoryProvider).wearing(clubId, me);
});

class ClubTagActions {
  ClubTagActions(this._ref);
  final Ref _ref;

  /// Wear [clubId]'s tag on my name, or take it off. One club at a time.
  Future<void> setWearing(String clubId, bool show) async {
    final me = _ref.read(currentUserIdProvider);
    if (me == null) throw const AppException('You\'re signed out. Sign in again.');
    await _ref.read(clubTagRepositoryProvider).setWearing(clubId, show);
    _ref.invalidate(wearingClubTagProvider);
    _ref.invalidate(clubTagProvider(me));
    _ref.invalidate(clubMembersProvider(clubId));
  }
}

final clubTagActionsProvider = Provider<ClubTagActions>((ref) => ClubTagActions(ref));
