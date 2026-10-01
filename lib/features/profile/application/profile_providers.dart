import 'dart:async';

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
import 'cutout_providers.dart';

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

/// A car photo as picked, plus what the recogniser thinks the car is (null
/// when it could not run or was unsure).
class PreparedCarPhoto {
  const PreparedCarPhoto({required this.bytes, this.guess});
  final Uint8List bytes;
  final CarRecognition? guess;
}

/// Recognise the car on the phone before anything is stored. Never throws:
/// with no network or no key you get the original bytes back and no guess,
/// and the form is just a form. The bytes are always the original; the plate
/// is only blurred when the member turns on "Hide my number plate"
/// ([CarPhotoPick]).
Future<PreparedCarPhoto> prepareCarPhoto(ProfileRepository repo, Uint8List original) async {
  try {
    final guess = await repo.recognizeCar(bytes: original);
    return PreparedCarPhoto(bytes: original, guess: guess);
  } catch (_) {
    return PreparedCarPhoto(bytes: original);
  }
}

/// A picked car photo for the "Hide my number plate" switch (off by default:
/// the original goes up). The original is kept so the switch can go back.
class CarPhotoPick {
  /// [scan] is the recogniser's answer for this photo, when it already ran
  /// (it says where the plate is).
  CarPhotoPick(this.original, {CarRecognition? scan}) : _scanned = scan != null, _plate = scan?.plate;
  final Uint8List original;
  bool _scanned;
  PlateBox? _plate;
  Uint8List? _hidden;
  Future<bool>? _pending;

  /// What to show and upload.
  Uint8List bytes({required bool hidePlate}) => hidePlate ? (_hidden ?? original) : original;

  /// [hidePlateOn] has run: the plate is blurred, or none was seen.
  bool get plateChecked => _hidden != null;

  /// A plate was found and blurred.
  bool get plateBlurred => _hidden != null && !identical(_hidden, original);
}

/// Blurs the plate on [p]. When this photo hasn't been scanned yet, asks the
/// recogniser where the plate is first (the original goes up as a data URL,
/// never to storage). False when it couldn't check (offline, say), so the
/// form can stop instead of uploading a readable plate.
Future<bool> hidePlateOn(ProfileRepository repo, CarPhotoPick p) {
  if (p._hidden != null) return Future.value(true);
  // The switch and Save can both ask while one run is still going.
  return p._pending ??= _hidePlate(repo, p).whenComplete(() => p._pending = null);
}

Future<bool> _hidePlate(ProfileRepository repo, CarPhotoPick p) async {
  if (!p._scanned) {
    try {
      p._plate = (await repo.recognizeCar(bytes: p.original)).plate;
      p._scanned = true;
    } catch (_) {
      return false;
    }
  }
  final box = p._plate;
  if (box == null) {
    p._hidden = p.original; // no plate seen
    return true;
  }
  try {
    p._hidden = await blurPlate(p.original, x0: box.x0, y0: box.y0, x1: box.x1, y1: box.y1);
    return true;
  } catch (_) {
    return false;
  }
}

/// The recogniser's box can land beside the plate (or it saw none): the
/// member taps the plate and the blur moves there. [fx], [fy] are the tap as
/// fractions of the photo; [aspect] is its width / height. Keeps the found
/// box's size, else a typical plate's (about a sixth of the width).
Future<void> placePlateAt(CarPhotoPick p, double fx, double fy, {required double aspect}) async {
  final old = p._plate;
  final w = old == null ? 0.16 : (old.x1 - old.x0).abs();
  final h = old == null ? 0.16 * aspect / 4 : (old.y1 - old.y0).abs();
  final box = PlateBox((fx - w / 2).clamp(0.0, 1.0), (fy - h / 2).clamp(0.0, 1.0), (fx + w / 2).clamp(0.0, 1.0), (fy + h / 2).clamp(0.0, 1.0));
  final blurred = await blurPlate(p.original, x0: box.x0, y0: box.y0, x1: box.x1, y1: box.y1);
  p._plate = box;
  p._scanned = true;
  p._hidden = blurred;
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
    String? garageStyle,
  }) async {
    state = const AsyncLoading();
    String? savedId;
    Car? saved;
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
          : await repo.updateCar(id: carId, make: make, model: model, year: year, description: description, photoUrls: urls, color: color, specs: specs, bodyStyle: bodyStyle, garageStyle: garageStyle);
      savedId = car.id;
      saved = car;
      ref.invalidate(userCarsProvider(me));
      ref.invalidate(profileStatsProvider(me));
      ref.invalidate(carProvider(car.id));
    });
    // The garage cut-out, in the background: the form is already done. A
    // cover that was just picked goes in as bytes, no download.
    final car = saved;
    if (car != null) {
      final freshCover = keptPhotoUrls.isEmpty && newPhotos.isNotEmpty ? newPhotos.first : null;
      unawaited(ref.read(cutoutServiceProvider).ensure(car, coverBytes: freshCover));
    }
    return savedId;
  }

  /// "Garage look": 'auto' (cut-out when there is a good one) or 'card'.
  Future<void> setGarageStyle(Car car, String style) async {
    final me = ref.read(currentUserIdProvider);
    if (me == null) throw const AppException('You\'re signed out. Sign in again.');
    await ref.read(profileRepositoryProvider).setGarageStyle(car.id, style);
    ref.invalidate(userCarsProvider(me));
    ref.invalidate(carProvider(car.id));
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
