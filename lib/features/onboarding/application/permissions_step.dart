import 'package:firebase_messaging/firebase_messaging.dart' show AuthorizationStatus;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/location/background_location.dart';
import '../../../core/push/push_service.dart';
import '../../settings/application/background_location_controller.dart';

/// What a permission card's button shows.
/// * enable: the phone can still show its prompt.
/// * on: granted (a green check).
/// * settings: the phone won't ask again (or the switch it needs lives
///   there), so the button opens TT Spot's page in phone settings.
enum PermPill { enable, on, settings }

bool locationAllowed(LocationPermission? p) => p == LocationPermission.whileInUse || p == LocationPermission.always;

/// Location card. [blocked]: learned this launch that the phone refuses
/// without asking (Android only says so after a request).
PermPill locationPill(LocationPermission? p, {required bool serviceOn, required bool blocked}) {
  if (locationAllowed(p)) return serviceOn ? PermPill.on : PermPill.settings;
  if (p == LocationPermission.deniedForever || blocked) return PermPill.settings;
  return PermPill.enable;
}

bool notificationsAllowed(AuthorizationStatus? s) => s == AuthorizationStatus.authorized || s == AuthorizationStatus.provisional;

/// Notifications card. iPhone says "denied" only after the member answered
/// and never shows its prompt twice. Android says "denied" before the first
/// prompt too, so there it takes [blocked] (learned from a request).
PermPill notificationsPill(AuthorizationStatus? s, {required bool blocked, required bool ios}) {
  if (notificationsAllowed(s)) return PermPill.on;
  if (s == AuthorizationStatus.denied && (ios || blocked)) return PermPill.settings;
  return PermPill.enable;
}

/// "Share my spot when the app is closed" card; null = no card (this phone
/// can't do it). Waiting for "Always" / "Allow all the time" after Enable, or
/// that grant taken away later: Settings.
PermPill? backgroundPill(BgLocationState s) {
  if (!s.loaded) return PermPill.enable;
  return switch (s.view) {
    BgView.unsupported => null,
    BgView.on || BgView.hidden => PermPill.on,
    BgView.needsAlways => PermPill.settings,
    BgView.off => s.waitingForAlways ? PermPill.settings : PermPill.enable,
  };
}

/// The phone's side of the permissions step behind one seam, so widget tests
/// can stand in for the system prompts.
class PermissionsDevice {
  const PermissionsDevice(this._push);
  final PushService _push;

  Future<LocationPermission> location() => Geolocator.checkPermission();
  Future<bool> locationServiceOn() => Geolocator.isLocationServiceEnabled();
  /// The phone's "Allow While Using App" / "While using the app" prompt.
  Future<LocationPermission> requestLocation() => Geolocator.requestPermission();
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// The page is on screen: the map won't pop the notification prompt later.
  void stepShown() => _push.permissionsStepShown();
  Future<AuthorizationStatus?> notifications() => _push.permission();
  Future<({AuthorizationStatus status, bool prompted})?> requestNotifications() => _push.askOnPermissionsStep();
  /// Registers this phone for push once notifications are allowed.
  Future<void> registerPush() => _push.start();
  Future<bool> openNotificationSettings() => openPhoneNotificationSettings();

  /// The "Always" / "Allow all the time" step on its own (the Fix path).
  Future<bool> requestBackground() => BgLocationNative.requestBackground();
}

final permissionsDeviceProvider = Provider<PermissionsDevice>((ref) => PermissionsDevice(ref.read(pushServiceProvider)));
