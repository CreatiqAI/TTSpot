import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../data/club_tag_repository.dart';
import '../domain/club.dart';
import '../domain/club_tag.dart';
import 'club_members_providers.dart';
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

/// Does this club's tag show on my name right now (my pick, or as president
/// the default)? False when signed out or not a member.
final wearingClubTagProvider = FutureProvider.autoDispose.family<bool, String>((ref, clubId) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return false;
  final tag = await ref.watch(clubTagProvider(me).future);
  return tag?.clubId == clubId;
});

/// The official clubs I'm in (president or member): the tags I can choose
/// from, oldest first. Underground clubs have none.
final myOfficialClubsProvider = FutureProvider.autoDispose<List<Club>>((ref) async {
  final clubs = await ref.watch(myClubsProvider.future);
  final now = DateTime.now();
  return clubs.where((c) => clubHasTag(c, now)).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
});

/// Official and not lapsed: the server's rule for a club with a tag.
bool clubHasTag(Club c, [DateTime? now]) => c.isOfficial && (c.officialUntil == null || c.officialUntil!.isAfter(now ?? DateTime.now()));

class ClubTagActions {
  ClubTagActions(this._ref);
  final Ref _ref;

  String _me() {
    final me = _ref.read(currentUserIdProvider);
    if (me == null) throw const AppException('You\'re signed out. Sign in again.');
    return me;
  }

  /// Wear [clubId]'s tag on my name, or take it off (then no tag shows,
  /// presidents included). One club at a time.
  Future<void> setWearing(String clubId, bool show) async {
    final me = _me();
    await _ref.read(clubTagRepositoryProvider).setWearing(clubId, show);
    _changed(me);
  }

  /// Settings > Club tag on my name: [clubId]'s tag, or none (null).
  Future<ClubTag?> choose(String? clubId) async {
    final me = _me();
    final tag = await _ref.read(clubTagRepositoryProvider).choose(clubId);
    _changed(me);
    return tag;
  }

  /// My tag changed: every place that drew it asks again.
  void _changed(String me) {
    _ref.invalidate(clubTagProvider(me));
    _ref.invalidate(wearingClubTagProvider);
    _ref.invalidate(clubMembersProvider);
    _ref.invalidate(clubMembersListProvider);
  }
}

final clubTagActionsProvider = Provider<ClubTagActions>((ref) => ClubTagActions(ref));
