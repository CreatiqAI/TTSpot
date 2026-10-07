import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/utils/friendly_error.dart';
import '../../../events/application/event_providers.dart';
import '../../../events/application/live_activity.dart';
import '../../../map/application/map_providers.dart';
import '../../../organizer/application/organizer_providers.dart';
import '../../../points/application/points_providers.dart';
import '../../../social/application/notification_providers.dart';
import '../../expo_routes.dart';
import '../data/door_repository.dart';
import '../domain/door_models.dart';
import 'door_providers.dart';

/// The event's invite / door QR (`https://ttspot.my/e/<CODE>`) scanned in the
/// app. During the event (its live window) it checks me in when I'm inside
/// the check-in area, then opens the floor plan (or my pass) with a welcome.
/// Any other time it just opens the event, as before.
Future<ScanOutcome> handleEventInviteScan(Ref ref, String code) async {
  final repo = ref.read(doorRepositoryProvider);
  // First ask without a location: no permission prompt when the event isn't on.
  var r = await repo.checkinByDoor(code: code);
  if (!r.live) return ScanOutcome(title: 'Meet', route: '/event/${r.eventId}', silent: true);
  if (r.needLocation) {
    final pos = await _quickFix();
    if (pos == null) {
      throw const AppException('Turn on location so we can confirm you are at the event, then scan again.');
    }
    r = await repo.checkinByDoor(code: code, lat: pos.latitude, lng: pos.longitude);
  }

  final eventId = r.eventId;
  ref.invalidate(myCheckinsProvider);
  ref.invalidate(eventCarsProvider(eventId));
  ref.invalidate(eventDetailProvider(eventId));
  ref.invalidate(eventCheckedInProvider(eventId));
  ref.invalidate(eventRecapProvider(eventId));
  ref.invalidate(liveEventsProvider);
  ref.invalidate(notificationsProvider);
  ref.invalidate(eventHubProvider(eventId));
  ref.invalidate(myDrawStatusProvider(eventId));
  ref.read(pointsActionsProvider).refreshBalance();

  if (!r.isNew) {
    // Scanned the door again: straight to my pass.
    return ScanOutcome(title: 'Your pass', route: ExpoRoutes.pass(eventId), silent: true);
  }
  if (r.hasForm && !r.formDone) ref.read(pendingRegistrationProvider.notifier).add(eventId);
  // The lock screen meet shows the entry number from now on.
  unawaited(ref.read(liveActivityServiceProvider).sync());
  return doorOutcome(r);
}

/// The scanner result for a fresh door check-in.
ScanOutcome doorOutcome(DoorResult r) => ScanOutcome(
      title: r.entryNo == null ? "You're in" : "You're in · ${entryLabel(r.entryNo!)}",
      subtitle: r.entryNo == null ? 'Checked in.' : 'Your entry number is also your lucky draw number.',
      points: r.points,
      checkinEventId: r.eventId,
      route: r.hasFloorplan ? ExpoRoutes.floorplanWelcome(r.eventId) : ExpoRoutes.pass(r.eventId),
    );

/// A recent fix, asking for permission if we never did. Null when the member
/// refuses or the device can't get one in time. (Same as PointsActions'.)
Future<Position?> _quickFix() async {
  try {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 2)) return last;
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
    );
  } catch (_) {
    return null;
  }
}
