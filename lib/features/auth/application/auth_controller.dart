import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../../../core/push/push_service.dart';

/// Drives the sign-in screen. State is loading / error / idle; the router
/// reacts to the resulting auth change, so callers don't navigate manually.
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signIn({required String email, required String password}) => _run(
        () => ref.read(authRepositoryProvider).signInWithEmail(email: email, password: password),
      );

  /// True when a 6-digit code was emailed and still has to be entered.
  Future<bool> signUp({required String email, required String password}) async {
    state = const AsyncLoading();
    var needsCode = false;
    state = await AsyncValue.guard(() async {
      needsCode = await ref.read(authRepositoryProvider).signUpWithEmail(email: email, password: password);
    });
    return !state.hasError && needsCode;
  }

  Future<void> requestPasswordReset(String identifier) => _run(
        () => ref.read(authRepositoryProvider).requestPasswordReset(identifier),
      );

  Future<void> signInWithGoogle() => _run(
        () => ref.read(authRepositoryProvider).signInWithGoogle(),
      );

  Future<void> signInWithApple() => _run(
        () => ref.read(authRepositoryProvider).signInWithApple(),
      );

  Future<void> signOut() => _run(() async {
        await ref.read(pushServiceProvider).unregister();
        await ref.read(authRepositoryProvider).signOut();
      });

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(AuthController.new);
