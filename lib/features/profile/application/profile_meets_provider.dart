import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile_repository.dart';
import '../domain/profile_meets.dart';

/// The list behind a profile's "Meets" number, loaded when the sheet opens.
final profileMeetsProvider = FutureProvider.autoDispose.family<ProfileMeets, String>((ref, userId) {
  return ref.watch(profileRepositoryProvider).fetchMeets(userId);
});
