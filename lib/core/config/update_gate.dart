import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../supabase/supabase_client.dart';
import '../theme/app_theme.dart';
import '../theme/titi.dart';
import '../widgets/primary_button.dart';
import 'app_version.dart';

// The minimum version gate. The server keeps the oldest app version allowed
// to run (platform_settings.min_app_version, read with the public RPC
// app_min_version, so it works before sign-in). Older apps get a full-screen
// "Time for an update" page over everything. A failed check never blocks.

/// Numeric compare of two "x.y.z" versions: <0 when [a] is older, 0 the
/// same, >0 newer. A build ("+73") or pre-release ("-beta") suffix is
/// ignored, missing parts count as 0, and a non-number part reads as 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.trim().split(RegExp(r'[+-]')).first.split('.')) int.tryParse(p.trim()) ?? 0];
  final x = parts(a);
  final y = parts(b);
  final n = x.length > y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// [current] is older than [minimum], so it must update.
bool mustUpdate(String current, String minimum) => compareVersions(current, minimum) < 0;

/// The store page for this phone.
String updateStoreUrl({TargetPlatform? platform}) => (platform ?? defaultTargetPlatform) == TargetPlatform.iOS
    ? 'https://apps.apple.com/app/id6815672400'
    : 'https://play.google.com/store/apps/details?id=my.ttspot.app';

/// Checked at most this often (launch always checks).
const kUpdateCheckEvery = Duration(minutes: 10);

/// Fetches `app_min_version()`. Overridden in tests.
final minAppVersionLoaderProvider = Provider<Future<String> Function()>((ref) {
  return () async {
    final v = await ref.read(supabaseProvider).rpc('app_min_version').timeout(const Duration(seconds: 10));
    return v is String ? v : '0.0.0';
  };
});

/// True when this app is too old to keep working.
class UpdateGate extends Notifier<bool> {
  UpdateGate({this.version = kAppVersion, DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  /// This app's version.
  final String version;
  final DateTime Function() _now;
  DateTime? _checkedAt;
  bool _busy = false;

  @override
  bool build() => false;

  /// Launch and resume. Skips when checked less than [kUpdateCheckEvery]
  /// ago. Any failure leaves the current answer as it is.
  Future<void> check() async {
    final now = _now();
    final last = _checkedAt;
    if (_busy || (last != null && now.difference(last) < kUpdateCheckEvery)) return;
    _busy = true;
    try {
      final min = await ref.read(minAppVersionLoaderProvider)();
      _checkedAt = now;
      state = mustUpdate(version, min);
    } catch (e) {
      debugPrint('update check: $e');
    } finally {
      _busy = false;
    }
  }
}

final updateGateProvider = NotifierProvider<UpdateGate, bool>(UpdateGate.new);

/// The blocking "Time for an update" page.
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key});

  Future<void> _open(BuildContext context) async {
    try {
      if (await launchUrl(Uri.parse(updateStoreUrl()), mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text("Couldn't open the store.")));
    }
  }

  @override
  Widget build(BuildContext context) => Material(
        key: const ValueKey('update-required'),
        color: AppColors.surface,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Titi(TitiPose.wrench, height: 170),
                    const SizedBox(height: 20),
                    Text(
                      'Time for an update',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: AppFonts.display, fontSize: 28, height: 1.1, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This version of TT Spot is too old to keep working. Update to carry on.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, height: 1.45, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 26),
                    PrimaryButton(label: 'Update', onPressed: () => _open(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
