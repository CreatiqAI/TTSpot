import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/social/application/chat_providers.dart';
import '../../features/social/application/notification_providers.dart';
import '../router/app_router.dart';
import '../supabase/supabase_client.dart';
import 'firebase_setup.dart';

/// Lets push banners show while the app is open (Android doesn't draw a
/// system notification for a foreground message).
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Registers this phone for push after sign-in and opens the right screen when
/// a notification is tapped. The server side is the `push` Edge Function.
class PushService {
  PushService(this._ref);
  final Ref _ref;
  bool _started = false;
  bool _starting = false;
  bool _listening = false;
  bool _asked = false;
  final _subs = <StreamSubscription<dynamic>>[];

  /// One line for Settings → Notifications ("On", "Off in iPhone Settings"…).
  final status = ValueNotifier<String>('Checking…');

  /// Called once the member is inside the app (past onboarding) and again on
  /// resume until it works. Asks for permission once per launch; the resume
  /// calls only check, so a "Don't allow" isn't followed by a second prompt.
  /// [ask] = the member tapped Turn on: show the phone's prompt again if it
  /// still may.
  Future<void> start({bool ask = false}) async {
    if (_started || _starting) return;
    final me = _ref.read(currentUserIdProvider);
    if (me == null) return;
    if (!firebaseReady) {
      _set('Not available: ${firebaseInitError ?? 'Firebase not started'}');
      return;
    }
    _starting = true;
    final fm = FirebaseMessaging.instance;
    try {
      FirebaseCrashlytics.instance.setUserIdentifier(me);
      final perm = ask || !_asked ? await fm.requestPermission() : await fm.getNotificationSettings();
      _asked = true;
      final allowed = perm.authorizationStatus == AuthorizationStatus.authorized || perm.authorizationStatus == AuthorizationStatus.provisional;
      if (!allowed) {
        // Android 13+ also reports deniedPermanently; either way nothing can show.
        _set(defaultTargetPlatform == TargetPlatform.iOS ? 'Off in iPhone Settings' : 'Off in phone settings');
        return;
      }
      await fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // The FCM token needs the APNs token first; it can lag on first launch.
        String? apns;
        for (var i = 0; i < 10 && (apns = await fm.getAPNSToken()) == null; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (apns == null) {
          _set('Waiting for Apple (no APNs token yet)');
          return;
        }
      }
      final token = await fm.getToken();
      if (token == null) {
        _set('No push token from Firebase');
        return;
      }
      await _register(token);
      if (!_listening) {
        _listening = true;
        _subs.add(fm.onTokenRefresh.listen(_register));
        _subs.add(FirebaseMessaging.onMessage.listen(_foreground));
        _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_open));
        final initial = await fm.getInitialMessage();
        if (initial != null) _open(initial);
      }
      _started = true;
      _set('On');
    } catch (e) {
      _set('Error: $e');
      debugPrint('[push] start failed: $e');
    } finally {
      _starting = false;
    }
  }

  /// What the phone allows right now (null = Firebase isn't running, can't tell).
  /// Asked fresh each time: the member may have changed it in phone settings.
  Future<AuthorizationStatus?> permission() async {
    if (!firebaseReady) return null;
    try {
      return (await FirebaseMessaging.instance.getNotificationSettings()).authorizationStatus;
    } catch (_) {
      return null;
    }
  }

  /// Shows the result in Settings and keeps the last one on the profile
  /// (settings.push_debug) so problems on a tester's phone can be read remotely.
  void _set(String s) {
    status.value = s;
    unawaited(_ref
        .read(supabaseProvider)
        .rpc('update_my_settings', params: {'p_patch': {'push_debug': '${DateTime.now().toUtc().toIso8601String()} ${defaultTargetPlatform.name} $s'}})
        .then((_) {}, onError: (_) {}));
  }

  Future<void> _register(String token) => _ref.read(supabaseProvider).rpc('register_push_token', params: {
        'p_token': token,
        'p_platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      });

  /// Before sign-out, so the next account on this phone doesn't get our pushes.
  Future<void> unregister() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _listening = false;
    _started = false;
    if (!firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _ref.read(supabaseProvider).rpc('unregister_push_token', params: {'p_token': token});
    } catch (_) {/* offline or never registered: the server drops dead tokens anyway */}
  }

  void _open(RemoteMessage m) {
    final route = m.data['route'] as String?;
    if (route != null && route.startsWith('/')) _ref.read(appRouterProvider).push(route);
  }

  void _foreground(RemoteMessage m) {
    _ref.invalidate(notificationsProvider);
    _ref.invalidate(inboxProvider);
    // iOS shows its own banner (presentation options above); Android needs ours.
    if (defaultTargetPlatform == TargetPlatform.iOS) return;
    final n = m.notification;
    if (n == null) return;
    final route = m.data['route'] as String?;
    // Already looking at that chat: the message is on screen.
    if (route != null && _ref.read(appRouterProvider).state.uri.path == route) return;
    rootMessengerKey.currentState?.showSnackBar(SnackBar(
      content: Text([n.title, n.body].whereType<String>().join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
      action: route == null ? null : SnackBarAction(label: 'Open', onPressed: () => _open(m)),
    ));
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));

/// Android has no URL for an app's notification settings (url_launcher only
/// sends VIEW intents), so MainActivity opens them over this channel.
const _settingsChannel = MethodChannel('my.ttspot.app/settings');

/// Opens TT Spot's notification settings on the phone: the app's page in
/// iPhone Settings, or Android's notification screen for the app. False when
/// nothing opened.
Future<bool> openPhoneNotificationSettings() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _settingsChannel.invokeMethod<bool>('openNotificationSettings') ?? false;
    }
    return await launchUrl(Uri.parse('app-settings:'));
  } catch (_) {
    return false;
  }
}
