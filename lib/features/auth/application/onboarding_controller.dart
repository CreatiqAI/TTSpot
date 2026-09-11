import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../data/auth_repository.dart';

final usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

/// Drives the onboarding form: validates username, uploads the avatar,
/// saves the profile, then refreshes [currentProfileProvider] so the router
/// moves the user on to the map.
class OnboardingController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> submit({
    required String username,
    required String displayName,
    required String homeState,
    String? bio,
    XFile? avatar,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) throw const AppException('You\'re signed out. Sign in again.');
      final repo = ref.read(authRepositoryProvider);

      final cleanUsername = username.trim().toLowerCase();
      if (!usernamePattern.hasMatch(cleanUsername)) {
        throw const AppException('Username: 3–20 characters, letters, numbers or _ only.');
      }
      if (homeState.trim().isEmpty) throw const AppException('Choose your home state.');
      if (!await repo.isUsernameAvailable(cleanUsername, forUserId: userId)) {
        throw const AppException('That username is already taken.');
      }

      String? avatarUrl;
      if (avatar != null) {
        avatarUrl = await repo.uploadAvatar(userId: userId, bytes: await avatar.readAsBytes());
      }

      await repo.saveProfile(
        userId: userId,
        username: cleanUsername,
        displayName: displayName.trim().isEmpty ? cleanUsername : displayName,
        homeState: homeState,
        bio: bio,
        avatarUrl: avatarUrl,
      );
      ref.invalidate(currentProfileProvider);
    });
  }
}

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, void>(OnboardingController.new);

/// Shared picker config: downsized + compressed so avatars stay well under the 2 MB bucket limit.
Future<XFile?> pickAvatarImage(ImageSource source) {
  return ImagePicker().pickImage(
    source: source,
    maxWidth: 800,
    maxHeight: 800,
    imageQuality: 85,
  );
}
