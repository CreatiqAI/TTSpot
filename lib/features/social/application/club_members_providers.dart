import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/club_members_repository.dart';
import '../domain/club_member.dart';

/// Everyone in a club, for its members page (officers first, then by join
/// date), each with their default car.
final clubMembersListProvider = FutureProvider.autoDispose.family<List<ClubMemberEntry>, String>(
  (ref, clubId) => ref.watch(clubMembersRepositoryProvider).list(clubId),
);
