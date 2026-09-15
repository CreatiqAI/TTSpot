import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../domain/profile.dart';

/// Wraps every Supabase Auth + `profiles` + avatar-storage call.
/// Widgets never touch Supabase directly.
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  static bool _googleInitialised = false;

  User? get currentUser => _client.auth.currentUser;

  // ---------------------------------------------------------------- email ---

  /// Log in with an email **or a username**. Emails go straight to Supabase;
  /// usernames are resolved server-side by the `login` Edge Function (which
  /// never reveals the email) and the returned session is installed here.
  Future<void> signInWithEmail({required String email, required String password}) async {
    final id = email.trim().toLowerCase();
    if (id.contains('@')) {
      await _client.auth.signInWithPassword(email: id, password: password);
      return;
    }
    final res = await _client.functions.invoke('login', body: {'action': 'password', 'identifier': id, 'password': password});
    final data = res.data as Map?;
    if (data?['error'] == 'email_not_confirmed') {
      throw const AuthException('Email not confirmed', code: 'email_not_confirmed');
    }
    if (data == null || data['error'] != null) throw AppException(data?['error'] as String? ?? 'Wrong username or password.');
    await _client.auth.setSession(data['refresh_token'] as String);
  }

  /// Sends the reset email for an email or username. Always succeeds from the
  /// caller's point of view so nobody can probe which accounts exist.
  Future<void> requestPasswordReset(String identifier) async {
    final res = await _client.functions.invoke('login', body: {'action': 'reset', 'identifier': identifier.trim().toLowerCase()});
    final data = res.data as Map?;
    if (data != null && data['error'] != null) throw AppException(data['error'] as String);
  }

  /// After the reset link signed the member in.
  Future<void> updatePassword(String password) => _client.auth.updateUser(UserAttributes(password: password));

  /// Creates the account. Returns true when the email still has to be
  /// confirmed with the 6-digit code we just sent (the normal case).
  Future<bool> signUpWithEmail({required String email, required String password}) async {
    final res = await _client.auth.signUp(email: email.trim().toLowerCase(), password: password);
    return res.session == null;
  }

  /// The 6-digit code from the sign-up email. Success signs the member in.
  Future<void> verifySignupCode({required String email, required String code}) async {
    await _client.auth.verifyOTP(type: OtpType.signup, email: email.trim().toLowerCase(), token: code);
  }

  Future<void> resendSignupCode(String email) async {
    await _client.auth.resend(type: OtpType.signup, email: email.trim().toLowerCase());
  }

  // -------------------------------------------------------- linked logins ---

  /// Link a Google account to the signed-in member (Settings → Sign-in methods).
  Future<void> linkGoogle() async {
    final t = await _googleTokens();
    await _client.auth.linkIdentityWithIdToken(provider: OAuthProvider.google, idToken: t.$1, accessToken: t.$2);
  }

  Future<void> unlinkProvider(String provider) async {
    final ids = _client.auth.currentUser?.identities ?? const [];
    final id = ids.where((i) => i.provider == provider).firstOrNull;
    if (id == null) throw const AppException('That sign-in method is not linked.');
    await _client.auth.unlinkIdentity(id);
    await _client.auth.refreshSession();
  }

  // --------------------------------------------------------------- google ---

  /// Native Google sign-in → ID token → Supabase session.
  /// Needs GOOGLE_WEB_CLIENT_ID in env.json and the Google provider enabled in Supabase.
  Future<void> signInWithGoogle() async {
    final t = await _googleTokens();
    await _client.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: t.$1, accessToken: t.$2);
  }

  /// (idToken, accessToken) from the native Google picker.
  Future<(String, String?)> _googleTokens() async {
    if (Env.googleWebClientId.isEmpty) {
      throw const AppException('Google sign-in isn\'t set up yet. Use email for now.');
    }
    final gsi = GoogleSignIn.instance;
    if (!_googleInitialised) {
      await gsi.initialize(
        serverClientId: Env.googleWebClientId,
        clientId: Env.googleIosClientId.isEmpty ? null : Env.googleIosClientId,
      );
      _googleInitialised = true;
    }

    final GoogleSignInAccount account;
    try {
      account = await gsi.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AppException('Google sign-in cancelled.');
      }
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AppException('Google didn\'t return a sign-in token. Try again.');
    }
    const scopes = ['email', 'profile'];
    final auth = await account.authorizationClient.authorizationForScopes(scopes) ??
        await account.authorizationClient.authorizeScopes(scopes);
    return (idToken, auth.accessToken);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    if (_googleInitialised) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {/* not signed in with Google; ignore */}
    }
  }

  // -------------------------------------------------------------- profile ---

  Future<Profile?> fetchProfile(String userId, {bool withCarCount = false}) async {
    final row = await _client.from('profiles').select(withCarCount ? '*, cars(count)' : '*').eq('id', userId).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  /// Upsert so onboarding still works if the signup trigger somehow missed a row.
  Future<Profile> saveProfile({
    required String userId,
    String? username,
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? homeState,
  }) async {
    final row = await _client
        .from('profiles')
        .upsert({
          'id': userId,
          'username': ?username?.trim().toLowerCase(),
          'display_name': ?displayName?.trim(),
          'bio': ?bio?.trim(),
          'avatar_url': ?avatarUrl,
          'home_state': ?homeState,
        })
        .select()
        .single();
    return Profile.fromMap(row);
  }

  Future<bool> isUsernameAvailable(String username, {required String forUserId}) async {
    final row = await _client
        .from('profiles')
        .select('id')
        .eq('username', username.trim().toLowerCase())
        .maybeSingle();
    return row == null || row['id'] == forUserId;
  }

  /// Uploads to `avatars/<userId>/avatar.jpg` (overwrites) and returns a public URL
  /// with a cache-buster so the new image shows immediately.
  Future<String> uploadAvatar({required String userId, required Uint8List bytes}) async {
    final path = '$userId/avatar.jpg';
    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    final url = _client.storage.from('avatars').getPublicUrl(path);
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

/// The signed-in user's profile. Null when signed out. Re-fetched on auth change.
/// Call `ref.invalidate(currentProfileProvider)` after editing the profile.
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(authRepositoryProvider).fetchProfile(userId, withCarCount: true);
});
