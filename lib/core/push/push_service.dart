import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final _subs = <StreamSubscription<dynamic>>[];

  /// Called once the member is inside the app (past onboarding). Asks for
  /// permission the first time, so the prompt comes with the app on screen.
  Future<void> start() async {
    if (_started || !firebaseReady) return;
    final me = _ref.read(currentUserIdProvider);
    if (me == null) return;
    _started = true;
    FirebaseCrashlytics.instance.setUserIdentifier(me);
    final fm = FirebaseMessaging.instance;
    try {
      final perm = await fm.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      await fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // The FCM token needs the APNs token first; it can lag a moment on first launch.
        for (var i = 0; i < 5 && await fm.getAPNSToken() == null; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      final token = await fm.getToken();
      if (token != null) await _register(token);
      _subs.add(fm.onTokenRefresh.listen(_register));
      _subs.add(FirebaseMessaging.onMessage.listen(_foreground));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_open));
      final initial = await fm.getInitialMessage();
      if (initial != null) _open(initial);
    } catch (e) {
      debugPrint('[push] start failed: $e');
    }
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
