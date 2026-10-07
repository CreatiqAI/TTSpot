import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/friendly_error.dart';
import '../../../points/application/points_providers.dart';
import '../data/contest_repository.dart';
import '../domain/contest.dart';

/// A show car's vote QR (`ttspot://vote/<entryId>`): open the vote with that
/// car's sheet up, where the member confirms their vote.
Future<ScanOutcome> handleVoteScan(Ref ref, {required String entryId}) async {
  final info = await ref.read(contestRepositoryProvider).entryInfo(entryId);
  if (info.contestStatus == ContestStatus.cancelled) throw const AppException('This vote was cancelled.');
  if (info.status != EntryStatus.approved) throw const AppException("That car isn't in the vote any more.");
  return ScanOutcome(
    title: info.number == null ? 'Show car vote' : 'Show car #${info.number}',
    route: voteEntryRoute(info.eventId, info.contestId, info.entryId),
    silent: true,
  );
}
