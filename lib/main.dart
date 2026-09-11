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
                const Text(
                  'Toolchain works!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                const Text(
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

class TtSpotApp extends ConsumerWidget {
  const TtSpotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'TT Spot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
