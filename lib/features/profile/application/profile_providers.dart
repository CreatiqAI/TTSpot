import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/plate_blur.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/profile.dart';
import '../data/profile_repository.dart';
import '../domain/car.dart';
import '../domain/car_recognition.dart';

/// Any user's profile by id (the signed-in user's own is also in currentProfileProvider).
final profileProvider = FutureProvider.family<Profile?, String>((ref, id) {
  return ref.watch(authRepositoryProvider).fetchProfile(id);
});

final userCarsProvider = FutureProvider.family<List<Car>, String>((ref, ownerId) {
  return ref.watch(profileRepositoryProvider).fetchCars(ownerId);
});

final carProvider = FutureProvider.family<Car?, String>((ref, carId) {
  return ref.watch(profileRepositoryProvider).fetchCar(carId);
});

final profileStatsProvider = FutureProvider.family<ProfileStats, String>((ref, userId) {
  return ref.watch(profileRepositoryProvider).fetchStats(userId);
});

/// A car photo ready to upload: the plate blurred when one was seen, plus what
/// the recogniser thinks the car is (null when it could not run or was unsure).
class PreparedCarPhoto {
  const PreparedCarPhoto({required this.bytes, this.guess, this.plateBlurred = false});
  final Uint8List bytes;
  final CarRecognition? guess;
  final bool plateBlurred;
}

/// Recognise the car and blur its plate, on the phone, before anything is
/// stored. Never throws: with no network or no key you get the original
/// bytes back and no guess, and the form is just a form.
Future<PreparedCarPhoto> prepareCarPhoto(ProfileRepository repo, Uint8List original) async {
  CarRecognition guess;
  try {
    guess = await repo.recognizeCar(bytes: original);
  } catch (_) {
    return PreparedCarPhoto(bytes: original);
  }
  final plate = guess.plate;
  if (plate == null) return PreparedCarPhoto(bytes: original, guess: guess);
  try {
    final blurred = await blurPlate(original, x0: plate.x0, y0: plate.y0, x1: plate.x1, y1: plate.y1);
    return PreparedCarPhoto(bytes: blurred, guess: guess, plateBlurred: true);
  } catch (_) {
    // The image would not decode; there is nothing better to upload.
    return PreparedCarPhoto(bytes: original, guess: guess);
  }
}

/// Add / edit / delete a car. [save] returns the car id.
class CarFormController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// [newPhotos] are bytes, not files: the forms read (and possibly blur)
  /// them as soon as they are picked.
  Future<String?> save({
    String? carId,
    required String make,
    required String model,
    required String yearText,
    required String description,
    required List<String> keptPhotoUrls,
    required List<Uint8List> newPhotos,
    String? color,
    String? specs,
    String? bodyStyle,
  }) async {
    state = const AsyncLoading();
    String? savedId;
    state = await AsyncValue.guard(() async {
      final me = ref.read(currentUserIdProvider);
      if (me == null) throw const AppException('You\'re signed out. Sign in again.');
      if (make.trim().isEmpty) throw const AppException('What make is it? e.g. Perodua, Honda.');
      if (model.trim().isEmpty) throw const AppException('Which model? e.g. Myvi, Civic.');
      int? year;
      if (yearText.trim().isNotEmpty) {
        year = int.tryParse(yearText.trim());
        if (year == null || year < 1950 || year > DateTime.now().year + 1) {
          throw const AppException('Enter a valid year.');
        }
      }
      if (keptPhotoUrls.length + newPhotos.length > 5) throw const AppException('Up to 5 photos per car.');

      final repo = ref.read(profileRepositoryProvider);
      final urls = [...keptPhotoUrls];
      for (var i = 0; i < newPhotos.length; i++) {
        urls.add(await repo.uploadCarPhoto(userId: me, bytes: newPhotos[i], index: i));
      }
      final car = carId == null
          ? await repo.insertCar(ownerId: me, make: make, model: model, year: year, description: description, photoUrls: urls, color: color, specs: specs, bodyStyle: bodyStyle)
          : await repo.updateCar(id: carId, make: make, model: model, year: year, description: description, photoUrls: urls, color: color, specs: specs, bodyStyle: bodyStyle);
      savedId = car.id;
      ref.invalidate(userCarsProvider(me));
      ref.invalidate(profileStatsProvider(me));
      ref.invalidate(carProvider(car.id));
    });
    return savedId;
  }

  /// The car that fronts my profile and drives on the map.
  Future<void> setDefault(String carId) async {
    final me = ref.read(currentUserIdProvider);
    if (me == null) throw const AppException('You\'re signed out. Sign in again.');
    await ref.read(profileRepositoryProvider).setDefaultCar(carId);
    ref.invalidate(userCarsProvider(me));
  }

  Future<bool> delete(String carId) async {
    state = const AsyncLoading();
    var ok = false;
    state = await AsyncValue.guard(() async {
      final me = ref.read(currentUserIdProvider);
      if (me == null) throw const AppException('You\'re signed out. Sign in again.');
      await ref.read(profileRepositoryProvider).deleteCar(carId);
      ref.invalidate(userCarsProvider(me));
      ref.invalidate(profileStatsProvider(me));
      ok = true;
    });
    return ok;
  }
}

final carFormControllerProvider = AsyncNotifierProvider<CarFormController, void>(CarFormController.new);

Future<XFile?> pickCarPhoto(ImageSource source) {
  return ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
}
