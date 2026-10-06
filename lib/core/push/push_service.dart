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
import '../../features/social/domain/chat.dart' show Conversation;
import '../location/location_gate.dart' show locationGrantedProvider;
import '../router/app_router.dart';
import '../supabase/supabase_client.dart';
import 'firebase_setup.dart';
import 'in_app_notice.dart';

/// App-wide SnackBars from outside a page (background location uses it).
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
  bool _stepShown = false;
  final _subs = <StreamSubscription<dynamic>>[];

  /// One line for Settings → Notifications ("On", "Off in iPhone Settings"…).
  final status = ValueNotifier<String>('Checking…');

  /// The permissions step (after onboarding, while location is off) opened
  /// this launch. It has its own Enable for notifications, so the map must not
  /// pop the phone's prompt on top of the app after it.
  void permissionsStepShown() => _stepShown = true;

  /// Called once the member is inside the app (past onboarding) and again on
  /// resume until it works. Asks for permission at most once per launch (see
  /// [_mayPromptOnOpen]); the resume calls only check, so a "Don't allow"
  /// isn't followed by a second prompt. [ask] = the member tapped Turn on:
  /// show the phone's prompt again if it still may.
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
      final prompt = ask || (!_asked && await _mayPromptOnOpen());
      final perm = prompt ? await fm.requestPermission() : await fm.getNotificationSettings();
      _asked = true;
      final allowed = perm.authorizationStatus == AuthorizationStatus.authorized || perm.authorizationStatus == AuthorizationStatus.provisional;
      if (!allowed) {
        // Android 13+ also reports deniedPermanently; either way nothing can show.
        _set(defaultTargetPlatform == TargetPlatform.iOS ? 'Off in iPhone Settings' : 'Off in phone settings');
        return;
      }
      // Open app: no phone banner or sound (iOS), our in-app banner instead.
      // Android draws nothing in the foreground on its own: FCM skips
      // notification payloads, and ChatPushService skips data-only chats.
      await fm.setForegroundNotificationPresentationOptions(alert: false, badge: true, sound: false);
      // Taps and in-app banners don't need our token, so listen first: a
      // tapped notification still opens its chat when the token fetch below
      // fails (offline at launch) and is retried on the next resume.
      if (!_listening) {
        _listening = true;
        _subs.add(fm.onTokenRefresh.listen(_register));
        _subs.add(FirebaseMessaging.onMessage.listen(_foreground));
        _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_open));
        final initial = await fm.getInitialMessage();
        if (initial != null) _open(initial);
      }
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
      _started = true;
      _set('On');
    } catch (e) {
      _set('Error: $e');
      debugPrint('[push] start failed: $e');
    } finally {
      _starting = false;
    }
  }

  /// Whether opening the app may show the phone's notification prompt by
  /// itself. Not after the permissions step was on screen this launch (the
  /// member saw the Notifications card and chose), and not while location is
  /// off or still unknown: the router is about to show that step, and the
  /// prompt would land on top of it. Members who never see the step (location
  /// was already on, e.g. everyone from before it existed) keep the one prompt
  /// per launch they always had; the phone itself stops showing it once they
  /// have answered.
  Future<bool> _mayPromptOnOpen() async {
    if (_stepShown) return false;
    try {
      return await _ref.read(locationGrantedProvider.future).timeout(const Duration(seconds: 5));
    } catch (_) {
      return false;
    }
  }

  /// The permissions step's Enable on the Notifications card: the phone's
  /// prompt (when it may still show one), then [start] registers this phone
  /// exactly as on any launch. `prompted` is false when the answer came back
  /// at once: the phone showed nothing (blocked), so only its settings can
  /// turn notifications on. Null when Firebase isn't running.
  Future<({AuthorizationStatus status, bool prompted})?> askOnPermissionsStep() async {
    if (!firebaseReady) return null;
    final clock = Stopwatch()..start();
    final AuthorizationStatus answer;
    try {
      answer = (await FirebaseMessaging.instance.requestPermission()).authorizationStatus;
    } catch (_) {
      return null;
    }
    _asked = true;
    unawaited(start()); // registers the token when allowed; a no-op once push is on
    return (status: answer, prompted: clock.elapsed >= kInstantAnswer);
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

  Future<void> _register(String token) async {
    final android = defaultTargetPlatform == TargetPlatform.android;
    final db = _ref.read(supabaseProvider);
    await db.rpc('register_push_token', params: {'p_token': token, 'p_platform': android ? 'android' : 'ios'});
    // This build draws chat pushes itself (ChatPushService.kt), so the server
    // may send them data-only. Older installs never say so and keep the
    // standard notification.
    if (android) await db.rpc('mark_push_token_native_chat', params: {'p_token': token}).then((_) {}, onError: (_) {});
  }

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

  void _open(RemoteMessage m) => openRoute(m.data['route'] as String?);

  /// Where a tapped push (system or in-app banner) goes.
  void openRoute(String? route) {
    if (route != null && route.startsWith('/')) _ref.read(appRouterProvider).push(route);
  }

  String? _currentPath() {
    try {
      return _ref.read(appRouterProvider).state.uri.path;
    } catch (_) {
      return null;
    }
  }

  /// A push while the app is open: refresh, then our own banner unless I'm
  /// already in that chat (or on that page) or muted it.
  void _foreground(RemoteMessage m) {
    // Muted chats from the inbox as it was, before the refresh below.
    final muted = {for (final c in _ref.read(inboxProvider).value ?? const <Conversation>[]) if (c.muted) c.id};
    _ref.invalidate(notificationsProvider);
    _ref.invalidate(inboxProvider);
    final notice = InAppNotice.fromPush(m.data, title: m.notification?.title, body: m.notification?.body, messageId: m.messageId);
    if (notice == null) return;
    final path = _currentPath();
    if (!shouldShowInAppNotice(notice, viewingChatId: OpenChats.viewing(path), mutedChatIds: muted, currentPath: path)) return;
    InAppNotices.show(notice, onTap: notice.route == null ? null : () => openRoute(notice.route));
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));

/// A permission request that answers faster than this showed no prompt: no
/// person reads a system dialog and taps in under 0.7 s. The phone refused
/// on its own (denied for good), so the way on is the app's settings page.
const kInstantAnswer = Duration(milliseconds: 700);

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
