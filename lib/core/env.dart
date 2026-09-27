/// Build-time configuration, injected with `--dart-define-from-file=env.json`.
///
/// Never hard-code keys here. See SETUP.md for how to create env.json.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  /// Dashboard → Settings → API Keys. The new `sb_publishable_...` key, or the
  /// legacy `anon` JWT — both work here.
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Mapbox public token (pk.…), account → Tokens. The map does not render without it.
  static const mapboxPublicToken = String.fromEnvironment('MAPBOX_PUBLIC_TOKEN');

  /// DEBUG ONLY. Base64 of a PEM root certificate to additionally trust, for
  /// dev machines where antivirus / corporate proxies re-sign HTTPS (e.g. Avast).
  /// Ignored in release builds. Leave empty if you don't need it.
  static const devExtraCaPemB64 = String.fromEnvironment('DEV_EXTRA_CA_PEM_B64');

  /// Firebase (push + crash reports). Project settings → General → Your apps.
  /// All empty = Firebase stays off and the app runs without push.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseAndroidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const firebaseIosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const firebaseIosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
