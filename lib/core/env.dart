/// Build-time configuration, injected with `--dart-define-from-file=env.json`.
///
/// Never hard-code keys here. See SETUP.md for how to create env.json.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  /// Dashboard → Settings → API Keys. The new `sb_publishable_...` key, or the
  /// legacy `anon` JWT — both work here.
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Google OAuth *Web* client ID — required by Supabase to verify the
  /// ID token that native Google sign-in returns. Filled in during the auth step.
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Google OAuth *iOS* client ID (only needed when building for iOS).
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// DEBUG ONLY. Base64 of a PEM root certificate to additionally trust, for
  /// dev machines where antivirus / corporate proxies re-sign HTTPS (e.g. Avast).
  /// Ignored in release builds. Leave empty if you don't need it.
  static const devExtraCaPemB64 = String.fromEnvironment('DEV_EXTRA_CA_PEM_B64');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
