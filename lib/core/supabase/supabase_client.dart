import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';

/// Call once in main() before runApp().
Future<void> initSupabase() async {
  assert(Env.isConfigured, 'Missing SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY. Run with --dart-define-from-file=env.json');
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
  );
}

/// The single Supabase client. Repositories take this via `ref.watch`.
final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Convenience: the current user id, or null when signed out.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider); // rebuild on sign-in / sign-out
  return ref.watch(supabaseProvider).auth.currentUser?.id;
});

/// Emits on every auth change (sign in, sign out, token refresh).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});
