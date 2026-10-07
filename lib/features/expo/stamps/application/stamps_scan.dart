import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/utils/friendly_error.dart';
import '../../../points/application/points_providers.dart';
import '../../expo_routes.dart';
import '../data/stamps_repository.dart';
import 'stamps_providers.dart';

/// A booth's stamp QR (`ttspot://booth/<exhibitorId>/<code>`): stamp it (checked
/// in + inside the event area), +2 points the first time, "you are here".
Future<ScanOutcome> handleBoothScan(Ref ref, {required String exhibitorId, required String code}) async {
  final pos = await boothQuickFix();
  if (pos == null) {
    throw const AppException('Turn on location so we can confirm you are at the event, then scan again.');
  }
  final r = await ref.read(stampsRepositoryProvider).collectStamp(exhibitorId: exhibitorId, code: code, lat: pos.latitude, lng: pos.longitude);
  ref.read(stampsActionsProvider).refreshAfterStamp(eventId: r.eventId, exhibitorId: r.exhibitorId);
  if (r.points > 0) ref.read(pointsActionsProvider).refreshBalance();
  return ScanOutcome(
    title: r.title,
    subtitle: r.subtitle,
    points: r.points,
    route: stampsRouteAfterScan(r.eventId, r.freebieWaiting ? r.exhibitorId : null),
  );
}

/// The stamp card, opening the hand-over card when a freebie is waiting.
String stampsRouteAfterScan(String eventId, String? freebieExhibitorId) =>
    freebieExhibitorId == null ? ExpoRoutes.stamps(eventId) : '${ExpoRoutes.stamps(eventId)}?freebie=$freebieExhibitorId';

/// The leads screen asking which booth to save [passCode] for.
String leadsPickRoute(String eventId, String exhibitorId, String passCode) =>
    '${ExpoRoutes.leads(eventId, exhibitorId)}?pass=${Uri.encodeQueryComponent(passCode)}';

/// A member's event pass QR (`ttspot://pass/<eventId>/<passCode>`), scanned by
/// booth staff to save a lead. Staff of several booths pick one on the leads screen.
Future<ScanOutcome> handlePassScan(Ref ref, {required String eventId, required String passCode}) async {
  final booths = await ref.read(stampsRepositoryProvider).myStaffBooths(eventId);
  if (booths.isEmpty) {
    throw const AppException("That's a member's event pass. Booth staff scan it to save a lead.");
  }
  if (booths.length > 1) {
    return ScanOutcome(title: 'Pick a booth', route: leadsPickRoute(eventId, booths.first.id, passCode), silent: true);
  }
  final r = await ref.read(stampsActionsProvider).saveLead(eventId: eventId, passCode: passCode, exhibitorId: booths.first.id);
  return ScanOutcome(title: r.title, subtitle: r.subtitle, route: ExpoRoutes.leads(eventId, r.exhibitorId));
}

/// A recent fix, asking for permission if we never did (same as the meet
/// check-in scan). Null when refused or no fix in time.
Future<Position?> boothQuickFix() async {
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
