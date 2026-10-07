import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/friendly_error.dart';
import '../../../floorplan/data/floorplan_repository.dart';
import '../../../points/application/points_providers.dart';

/// The event's invite / door QR (`https://ttspot.my/e/<CODE>`) scanned in the
/// app. Track A: checks the member in when the event is live and they're
/// inside the check-in area; otherwise opens the event.
Future<ScanOutcome> handleEventInviteScan(Ref ref, String code) async {
  final eventId = await ref.read(floorplanRepositoryProvider).eventForInviteCode(code);
  if (eventId == null) throw const AppException("That invite code isn't linked to a meet any more.");
  return ScanOutcome(title: 'Meet', route: '/event/$eventId', silent: true);
}
