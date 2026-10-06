import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// TT Spot is a map first: friends and clubmates on it, check-ins that prove
/// you were there, and meet QR codes that only work at the meet. So right
/// after onboarding comes the permissions step (PermissionsScreen at
/// /location): location, notifications and, optionally, sharing while the
/// app is closed, each explained on its own card instead of bare system
/// dialogs. The router shows it once per launch until location is on.

/// Whether location permission is granted right now (checked on every launch).
final locationGrantedProvider = FutureProvider<bool>((ref) async {
  try {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  } catch (_) {
    return false;
  }
});

/// The member left the permissions step this launch (Continue, or "Not now"
/// on the no-location confirm). Resets when the app restarts, so the step
/// shows again next time while location is still off, which is the intent:
/// the app is built around location.
class PermissionsStepDone extends Notifier<bool> {
  @override
  bool build() => false;
  void done() => state = true;
}

final permissionsStepDoneProvider = NotifierProvider<PermissionsStepDone, bool>(PermissionsStepDone.new);
