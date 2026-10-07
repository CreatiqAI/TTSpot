import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../data/contest_repository.dart';
import '../domain/contest.dart';

/// The vote to show for an event (newest open, else newest closed).
final currentContestIdProvider = FutureProvider.autoDispose.family<String?, String>((ref, eventId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(contestRepositoryProvider).currentContestId(eventId);
});

final contestBoardProvider = FutureProvider.autoDispose.family<ContestBoard, String>((ref, contestId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(contestRepositoryProvider).board(contestId);
});

/// Mutations. Each refreshes what it touched.
class ContestActions {
  ContestActions(this._ref);
  final Ref _ref;

  ContestRepository get _repo => _ref.read(contestRepositoryProvider);

  void _board(String contestId) => _ref.invalidate(contestBoardProvider(contestId));

  Future<String> save({
    required String eventId,
    String? contestId,
    required String title,
    String? about,
    DateTime? opensAt,
    DateTime? closesAt,
    required bool membersEnter,
  }) async {
    final String id;
    if (contestId == null) {
      id = await _repo.create(eventId: eventId, title: title, about: about, opensAt: opensAt, closesAt: closesAt, membersEnter: membersEnter);
    } else {
      await _repo.update(contestId: contestId, title: title, about: about, opensAt: opensAt, closesAt: closesAt, membersEnter: membersEnter);
      id = contestId;
    }
    _ref.invalidate(currentContestIdProvider(eventId));
    _board(id);
    return id;
  }

  Future<void> close(String eventId, String contestId) async {
    await _repo.close(contestId);
    _ref.invalidate(currentContestIdProvider(eventId));
    _board(contestId);
  }

  Future<void> cancel(String eventId, String contestId) async {
    await _repo.cancel(contestId);
    _ref.invalidate(currentContestIdProvider(eventId));
    _board(contestId);
  }

  Future<void> enter(String contestId, String carId) async {
    await _repo.enter(contestId, carId);
    _board(contestId);
  }

  Future<void> withdraw(String contestId, String entryId) async {
    await _repo.withdraw(entryId);
    _board(contestId);
  }

  Future<int?> review(String contestId, String entryId, {required bool approve}) async {
    final n = await _repo.review(entryId, approve: approve);
    _board(contestId);
    return n;
  }

  Future<int?> hostAdd(String contestId, String username, {String? carId}) async {
    final n = await _repo.hostAdd(contestId, username, carId: carId);
    _board(contestId);
    return n;
  }

  Future<void> vote(String contestId, String entryId) async {
    await _repo.vote(entryId);
    _board(contestId);
  }
}

final contestActionsProvider = Provider<ContestActions>((ref) => ContestActions(ref));
