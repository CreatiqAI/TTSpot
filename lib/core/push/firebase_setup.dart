import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../env.dart';

/// True once Firebase started (keys present in env.json for this platform).
bool firebaseReady = false;

FirebaseOptions? _options() {
  if (Env.firebaseProjectId.isEmpty || Env.firebaseSenderId.isEmpty) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android when Env.firebaseAndroidAppId.isNotEmpty && Env.firebaseApiKey.isNotEmpty => const FirebaseOptions(
        apiKey: Env.firebaseApiKey,
        appId: Env.firebaseAndroidAppId,
        messagingSenderId: Env.firebaseSenderId,
        projectId: Env.firebaseProjectId,
      ),
    TargetPlatform.iOS when Env.firebaseIosAppId.isNotEmpty => FirebaseOptions(
        apiKey: Env.firebaseIosApiKey.isNotEmpty ? Env.firebaseIosApiKey : Env.firebaseApiKey,
        appId: Env.firebaseIosAppId,
        messagingSenderId: Env.firebaseSenderId,
        projectId: Env.firebaseProjectId,
        iosBundleId: 'my.ttspot.app',
      ),
    _ => null,
  };
}

/// Starts Firebase with options from env.json (no google-services files in the
/// repo) and routes uncaught errors to Crashlytics. Never throws: without keys,
/// or if Firebase fails, the app just runs without push and crash reports.
Future<void> initFirebase() async {
  final options = _options();
  if (options == null) return;
  try {
    await Firebase.initializeApp(options: options);
    firebaseReady = true;
  } catch (e) {
    debugPrint('[firebase] init failed: $e');
    return;
  }
  final crash = FirebaseCrashlytics.instance;
  await crash.setCrashlyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = crash.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    crash.recordError(error, stack, fatal: true);
    return true;
  };
}
