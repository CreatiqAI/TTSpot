import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/router/app_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' show MapboxOptions;

import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/application/background_location_controller.dart';
import 'features/settings/application/settings_providers.dart';
import 'core/push/firebase_setup.dart';
import 'core/push/in_app_notice.dart';
import 'core/push/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemOverlay);
  _trustDevCertificateIfConfigured();

  // Let the app boot without a database so the toolchain can be tested first.
  if (!Env.isConfigured) {
    runApp(const _NotConfiguredApp());
    return;
  }
  MapboxOptions.setAccessToken(Env.mapboxPublicToken);
  await initSupabase();
  await initFirebase();
  runApp(const ProviderScope(retry: _retry, child: TtSpotApp()));
}

const _localReleaseTest = bool.fromEnvironment('LOCAL_RELEASE_TEST');

/// Debug builds only: trust an extra root certificate supplied via env.json so
/// HTTPS works on dev machines where antivirus (Avast) re-signs traffic.
/// Must run before any HttpClient is created. No-op in release, except a local
/// release smoke test built with --dart-define=LOCAL_RELEASE_TEST=true (store
/// builds never set it): release-only compiler bugs need a release build to
/// show, and that build has to reach the server from this PC.
void _trustDevCertificateIfConfigured() {
  if ((!kDebugMode && !_localReleaseTest) || Env.devExtraCaPemB64.isEmpty) return;
  try {
    SecurityContext.defaultContext.setTrustedCertificatesBytes(base64Decode(Env.devExtraCaPemB64));
    debugPrint('[dev] Extra root certificate trusted for this debug build.');
  } catch (e) {
    debugPrint('[dev] Could not load DEV_EXTRA_CA_PEM_B64: $e');
  }
}

/// Shown when env.json is missing. Proves Flutter + emulator work end to end.
class _NotConfiguredApp extends StatelessWidget {
  const _NotConfiguredApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏁', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 16),
                Text(
                  'Toolchain works!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Flutter and the emulator are running. Next: create env.json with your Supabase URL and key, then run with\n--dart-define-from-file=env.json',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TtSpotApp extends ConsumerStatefulWidget {
  const TtSpotApp({super.key});

  @override
  ConsumerState<TtSpotApp> createState() => _TtSpotAppState();
}

class _TtSpotAppState extends ConsumerState<TtSpotApp> {
  Timer? _clock;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Auto theme flips at 7 am / 7 pm: check once a minute, and again the
    // moment the app comes back (timers sleep while it is in the background).
    _clock = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
    _lifecycle = AppLifecycleListener(onResume: () {
      if (mounted) setState(() {});
      // "Allow all the time" may have been taken away in phone settings.
      ref.read(backgroundLocationProvider.notifier).sync(fromResume: true);
    });
    // Location sharing with the app closed follows sign-in/out and Nobody for
    // the app's whole life, not only while Settings is open.
    ref.listenManual(backgroundLocationProvider, (_, _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Both logos decoded up front, so a theme switch never shows the old ink.
    precacheImage(const AssetImage('assets/brand/logo.png'), context, onError: (_, _) {});
    precacheImage(const AssetImage('assets/brand/logo_dark.png'), context, onError: (_, _) {});
  }

  @override
  void dispose() {
    _clock?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  /// Dark when the setting says so, or in auto mode between 7 pm and 7 am.
  bool get _dark {
    final pref = ref.watch(settingsProvider).theme;
    if (pref == 'dark') return true;
    if (pref == 'light') return false;
    final h = DateTime.now().hour;
    return h >= 19 || h < 7;
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final dark = _dark;
    if (AppColors.dark != dark) {
      AppColors.dark = dark;
      SystemChrome.setSystemUIOverlayStyle(AppTheme.systemOverlay);
    }
    return MaterialApp.router(
      // A new key rebuilds every widget with the other palette. GoRouter keeps the location.
      key: ValueKey(dark),
      title: 'TT Spot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.current,
      routerConfig: router,
      scaffoldMessengerKey: rootMessengerKey,
      // iPhone habit: tapping anywhere outside a text field closes the keyboard.
      // Over everything: the in-app banner for pushes while the app is open.
      builder: (context, child) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                final f = FocusManager.instance.primaryFocus;
                if (f != null && f.context != null) f.unfocus();
              },
              child: child,
            ),
          ),
          const InAppNoticeHost(),
        ],
      ),
    );
  }
}

/// Failed loads retry twice, quickly (a network blip), then show their error.
/// Riverpod's default keeps retrying with back-off for ~40 s, which reads as
/// an endless spinner (the "Become a partner" bug).
Duration? _retry(int retryCount, Object error) => retryCount < 2 ? Duration(milliseconds: 600 * (retryCount + 1)) : null;
