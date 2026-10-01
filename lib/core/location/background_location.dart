import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';

/// "Share location when TT Spot is closed" — the native half.
///
/// Android: a location foreground service with a Stop button
/// (android/.../BgLocationService.kt). iOS: a CLLocationManager with
/// significant-change monitoring in AppDelegate.swift. Both post fixes to the
/// `push_location_by_token` RPC with a per-phone token, never with the
/// Supabase session (rotating that from native code would log the member out).
/// The token sits in the Android Keystore-encrypted app prefs / iOS Keychain.
abstract final class BgLocationNative {
  static const _channel = MethodChannel('my.ttspot.app/bglocation');

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static Future<NativeBgStatus> status() async {
    if (!supported) return NativeBgStatus.unsupported;
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('status');
      return m == null ? NativeBgStatus.unsupported : NativeBgStatus.fromMap(m);
    } on MissingPluginException {
      return NativeBgStatus.unsupported;
    } on PlatformException {
      return NativeBgStatus.unsupported;
    }
  }

  /// Saves the setup and starts sharing. True when the service / manager runs.
  static Future<bool> start({required String token, required String url, required String key, required String userId, String? devCa}) async {
    final r = await _channel.invokeMethod<bool>('start', {'token': token, 'url': url, 'key': key, 'userId': userId, 'devCa': ?devCa});
    return r ?? false;
  }

  /// Nobody (ghost): stop sending, keep the token.
  static Future<void> pause() => _quiet(() => _channel.invokeMethod<void>('pause'));

  /// Back from Nobody, or making sure it runs. True when running.
  static Future<bool> resume() async {
    try {
      return await _channel.invokeMethod<bool>('resume') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Off: stop, forget the token, and (by default) revoke it on the server
  /// using the token itself, so this works without a session too.
  static Future<void> stop({bool revoke = true}) => _quiet(() => _channel.invokeMethod<void>('stop', {'revoke': revoke}));

  /// "Allow all the time" (Android) / "Always" (iOS). True when granted.
  /// Android 11+ opens the app's location page in phone settings.
  static Future<bool> requestBackground() async {
    try {
      return await _channel.invokeMethod<bool>('requestBackground') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> _quiet(Future<void> Function() f) async {
    try {
      await f();
    } on MissingPluginException {
      // web / desktop / tests
    } on PlatformException {
      // nothing to undo
    }
  }
}

/// What the phone's native side reports.
class NativeBgStatus {
  const NativeBgStatus({
    required this.supported,
    this.enabled = false,
    this.paused = false,
    this.running = false,
    this.userId,
    this.lastResult,
    this.lastAt,
    this.background = false,
    this.foreground = false,
    this.device = 'phone',
  });

  static const unsupported = NativeBgStatus(supported: false);

  factory NativeBgStatus.fromMap(Map<String, dynamic> m) => NativeBgStatus(
        supported: true,
        enabled: m['enabled'] as bool? ?? false,
        paused: m['paused'] as bool? ?? false,
        running: m['running'] as bool? ?? false,
        userId: m['userId'] as String?,
        lastResult: m['lastResult'] as String?,
        lastAt: (m['lastAt'] as num?) == null ? null : DateTime.fromMillisecondsSinceEpoch((m['lastAt'] as num).toInt()),
        background: m['background'] as bool? ?? false,
        foreground: m['foreground'] as bool? ?? false,
        device: (m['device'] as String?)?.trim().isNotEmpty == true ? m['device'] as String : 'phone',
      );

  final bool supported;
  /// The switch is on on this phone (a token is saved).
  final bool enabled;
  final bool paused;
  final bool running;
  /// Whose token it is.
  final String? userId;
  /// Last answer from the server ('ok', 'throttled', 'hidden', 'invalid'),
  /// or why it stopped ('off', 'stopped' from the notification).
  final String? lastResult;
  final DateTime? lastAt;
  /// "Allow all the time" / "Always" granted.
  final bool background;
  final bool foreground;
  /// This phone's name on the server (model + install id), one live token each.
  final String device;
}

// ------------------------------------------------------------------ logic ---

/// What to tell the native side after looking at the facts.
enum BgAction { none, run, pause, forget }

/// Pure decision, run on launch, resume, sign-in/out and visibility changes.
///
/// * Off on this phone: nothing.
/// * Signed out, or the token belongs to someone else (another member signed
///   in): forget it (native revokes it with the token itself).
/// * Nobody (ghost): pause. The server would store nothing anyway, but the
///   notification shouldn't say "sharing" and the GPS can rest.
/// * No "Allow all the time": pause until it's back (the app shows a warning).
/// * Otherwise make sure it runs. An unknown visibility (still loading) counts
///   as visible: the server checks ghost on every ping regardless.
BgAction decideBgAction({
  required bool enabled,
  required String? ownerId,
  required String? currentUserId,
  required bool alwaysAllowed,
  required String? shareMode,
  required bool running,
  required bool paused,
}) {
  if (!enabled) return BgAction.none;
  if (currentUserId == null || ownerId != currentUserId) return BgAction.forget;
  if (shareMode == 'ghost' || !alwaysAllowed) return running || !paused ? BgAction.pause : BgAction.none;
  return running ? BgAction.none : BgAction.run;
}

/// The Settings row's status.
enum BgView { unsupported, off, on, needsAlways, hidden }

BgView bgViewFor({required bool supported, required bool enabled, required bool alwaysAllowed, required String? shareMode}) {
  if (!supported) return BgView.unsupported;
  if (!enabled) return BgView.off;
  if (!alwaysAllowed) return BgView.needsAlways;
  if (shareMode == 'ghost') return BgView.hidden;
  return BgView.on;
}

String bgSubtitle(BgView v, {required bool ios}) => switch (v) {
      BgView.unsupported => 'Not available on this device',
      BgView.off => 'Off',
      BgView.on => ios ? 'On · Always allowed' : 'On · Allowed all the time',
      BgView.needsAlways => ios ? 'Needs "Always" location' : 'Needs "Allow all the time"',
      BgView.hidden => 'Paused · your map visibility is Nobody',
    };
