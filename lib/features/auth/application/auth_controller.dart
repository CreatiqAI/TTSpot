import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

/// Drives the sign-in screen. State is loading / error / idle; the router
/// reacts to the resulting auth change, so callers don't navigate manually.
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signIn({required String email, required String password}) => _run(
        () => ref.read(authRepositoryProvider).signInWithEmail(email: email, password: password),
      );

  Future<void> signUp({required String email, required String password}) => _run(
        () => ref.read(authRepositoryProvider).signUpWithEmail(
              email: email,
              password: password,
              termsAcceptedAt: DateTime.now(),
            ),
      );

  Future<void> signInWithGoogle() => _run(
        () => ref.read(authRepositoryProvider).signInWithGoogle(),
      );

  Future<void> signOut() => _run(() => ref.read(authRepositoryProvider).signOut());

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(AuthController.new);
