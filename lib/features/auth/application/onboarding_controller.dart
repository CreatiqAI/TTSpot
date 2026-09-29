import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/media.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../points/data/points_repository.dart';
import '../data/auth_repository.dart';
import 'account_basics.dart';

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
    String? referralCode,
    String? phone,
    bool acceptedTerms = false,
    /// Onboarding passes false: it refreshes the profile itself once TiTi has
    /// handed over the first blind box, so the router does not move on early.
    bool refreshProfile = true,
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
      // Onboarding passes phone + Terms; Edit profile does not.
      if (phone != null) {
        if (normalizePhone(phone) == null) throw const AppException('Enter a valid phone number, e.g. 012-345 6789.');
        if (!acceptedTerms) throw const AppException('Please accept the Terms of Use and Privacy Policy.');
      }
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
      if (phone != null) await ref.read(accountActionsProvider).setBasics(phone: phone, acceptedTerms: acceptedTerms);
      // A member's code, a meet's invite code, or (older invites) a username.
      final code = (referralCode ?? '').trim().replaceFirst(RegExp(r'^@'), '');
      if (code.isNotEmpty && code.toLowerCase() != cleanUsername) {
        try {
          await ref.read(pointsRepositoryProvider).redeemReferralCode(code);
        } catch (_) {/* a bad code never blocks sign-up */}
      }
      if (refreshProfile) ref.invalidate(currentProfileProvider);
    });
  }
}

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, void>(OnboardingController.new);

/// Shared picker config: avatars show in every list at 96 px or less (only
/// the profile's "View photo" goes bigger), so they go up small.
Future<XFile?> pickAvatarImage(ImageSource source) {
  return ImagePicker().pickImage(
    source: source,
    maxWidth: kSmallPhotoSide,
    maxHeight: kSmallPhotoSide,
    imageQuality: 85,
  );
}
