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

  /// Dev convenience: in debug builds a bare name like `testing` becomes
  /// `testing@ttspot.my`, so test accounts can be typed as usernames.
  static const devLoginDomain = 'ttspot.my';

  static String normalizeLogin(String input) {
    final s = input.trim().toLowerCase();
    if (kDebugMode && s.isNotEmpty && !s.contains('@')) return '$s@$devLoginDomain';
    return s;
  }

  Future<void> signInWithEmail({required String email, required String password}) =>
      _client.auth.signInWithPassword(email: normalizeLogin(email), password: password);

  /// [termsAcceptedAt] is stored in the user's metadata as an audit trail.
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required DateTime termsAcceptedAt,
  }) async {
    final res = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'terms_accepted_at': termsAcceptedAt.toUtc().toIso8601String()},
    );
    // With "Confirm email" enabled in the dashboard there is no session yet.
    if (res.session == null) {
      throw const AppException('Account created. Check your email to confirm, then sign in.');
    }
  }

  // --------------------------------------------------------------- google ---

  /// Native Google sign-in → ID token → Supabase session.
  /// Needs GOOGLE_WEB_CLIENT_ID in env.json and the Google provider enabled in Supabase.
  Future<void> signInWithGoogle() async {
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

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );
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
