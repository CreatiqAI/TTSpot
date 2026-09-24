import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/router/app_router.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/application/settings_providers.dart';
import 'core/push/firebase_setup.dart';
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
  await initSupabase();
  await initFirebase();
  runApp(const ProviderScope(child: TtSpotApp()));
}

/// Debug builds only: trust an extra root certificate supplied via env.json so
/// HTTPS works on dev machines where antivirus (Avast) re-signs traffic.
/// Must run before any HttpClient is created. No-op in release.
void _trustDevCertificateIfConfigured() {
  if (!kDebugMode || Env.devExtraCaPemB64.isEmpty) return;
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

  @override
  void initState() {
    super.initState();
    // Auto theme flips at 7 am / 7 pm: check once a minute.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _clock?.cancel();
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
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          final f = FocusManager.instance.primaryFocus;
          if (f != null && f.context != null) f.unfocus();
        },
        child: child,
      ),
    );
  }
}
