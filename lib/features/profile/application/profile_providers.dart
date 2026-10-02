import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/plate_blur.dart' show imageContentType;
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/profile.dart';
import '../data/profile_repository.dart';
import '../domain/car.dart';
import '../domain/car_photo_storage.dart';
import '../domain/car_recognition.dart';
import 'cutout_providers.dart';
import 'plate_hiding.dart';

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

/// Add / edit / delete a car. [save] returns the car id.
class CarFormController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// [photos] in order: URLs to keep and bytes to upload (the forms read,
  /// and maybe blur, photos as soon as they are picked). An upload that
  /// [CarPhotoSave.replaces] a saved photo (its blurred copy, or its kept
  /// original coming back) takes its place, and once the car is saved the
  /// replaced file is deleted from the public bucket.
  ///
  /// A blurred upload keeps its original in the private car-originals
  /// bucket (`cars.photo_originals` says where), so the blur can come off
  /// later; an original that is no longer used there is deleted.
  Future<String?> save({
    String? carId,
    required String make,
    required String model,
    required String yearText,
    required String description,
    required List<CarPhotoSave> photos,
    String? color,
    String? specs,
    String? bodyStyle,
    String? garageStyle,
  }) async {
    state = const AsyncLoading();
    String? savedId;
    Car? saved;
    Uint8List? coverUpload;
    final replaced = <String>[];
    String? staleCutout;
    var droppedOriginals = const <String>[];
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
      if (photos.length > 5) throw const AppException('Up to 5 photos per car.');

      final repo = ref.read(profileRepositoryProvider);
      final before = carId == null ? null : await repo.fetchCar(carId);
      final urls = <String>[];
      final keptOriginals = <String, String>{}; // new blurred URL → its private original
      final bucketUrl = repo.carPhotosBucketUrl;
      for (var i = 0; i < photos.length; i++) {
        final p = photos[i];
        if (p.url != null) {
          urls.add(p.url!);
          continue;
        }
        final bytes = p.plateBlurred ? await compactBlurredPhoto(p.bytes!) : p.bytes!;
        final url = await repo.uploadCarPhoto(userId: me, bytes: bytes, index: i, plateBlurred: p.plateBlurred);
        if (p.plateBlurred && p.keptOriginal != null) {
          keptOriginals[url] = p.keptOriginal!;
        } else if (p.plateBlurred && p.original != null) {
          // Move, not delete: the original goes to the private bucket under
          // the same file name. No original kept means no save (it could
          // never come back), so a failure here stops the save.
          final type = imageContentType(p.original!);
          final path = originalPathFor(
            ownerId: me,
            blurredPath: Uri.decodeComponent(url.substring(bucketUrl.length)),
            replacedPath: p.replaces == null ? null : ownedPhotoPath(p.replaces!, bucketUrl: bucketUrl, ownerId: me),
            ext: switch (type) { 'image/png' => 'png', 'image/webp' => 'webp', _ => 'jpg' },
          );
          await repo.uploadCarOriginal(path: path, bytes: p.original!);
          keptOriginals[url] = path;
        }
        urls.add(url);
        if (i == 0) coverUpload = bytes;
        if (p.replaces != null) replaced.add(p.replaces!);
      }
      final originals = nextPhotoOriginals(ownerId: me, before: before?.photoOriginals ?? const {}, photoUrls: urls, added: keptOriginals);
      droppedOriginals = originals.dropped;
      // A new cover (its blurred copy, say): the old cut-out is stale and may
      // show the plate, so it's cleared and the new cover gets cut.
      final coverChanged = before != null && before.photoCover != urls.firstOrNull;
      if (coverChanged && before.cutoutUrl != null && replaced.contains(before.cutoutSource)) staleCutout = before.cutoutUrl;
      final car = carId == null
          ? await repo.insertCar(
              ownerId: me,
              make: make,
              model: model,
              year: year,
              description: description,
              photoUrls: urls,
              color: color,
              specs: specs,
              bodyStyle: bodyStyle,
              photoOriginals: originals.originals,
              garageStyle: garageStyle,
            )
          : await repo.updateCar(
              id: carId,
              make: make,
              model: model,
              year: year,
              description: description,
              photoUrls: urls,
              color: color,
              specs: specs,
              bodyStyle: bodyStyle,
              garageStyle: garageStyle,
              clearCutout: coverChanged,
              photoOriginals: originals.originals,
            );
      savedId = car.id;
      saved = car;
      if (replaced.isNotEmpty || staleCutout != null) {
        try {
          final gone = await repo.deleteUnreferencedPhotos(ownerId: me, replaced: replaced, staleCutouts: [?staleCutout]);
          if (kDebugMode) debugPrint('Plate: deleted ${gone.length} replaced files: $gone');
        } catch (e) {
          // The car is saved with the blurred copies either way.
          if (kDebugMode) debugPrint('Plate: could not delete the replaced photos: $e');
        }
      }
      if (droppedOriginals.isNotEmpty) {
        try {
          final gone = await repo.deleteUnreferencedOriginals(ownerId: me, candidates: droppedOriginals);
          if (kDebugMode) debugPrint('Plate: deleted ${gone.length} kept originals: $gone');
        } catch (e) {
          // Private either way; the car is saved.
          if (kDebugMode) debugPrint('Plate: could not delete kept originals: $e');
        }
      }
      ref.invalidate(userCarsProvider(me));
      ref.invalidate(profileStatsProvider(me));
      ref.invalidate(carProvider(car.id));
    });
    // The garage cut-out, in the background: the form is already done. A
    // cover that was just uploaded goes in as bytes, no download.
    final car = saved;
    if (car != null) {
      unawaited(ref.read(cutoutServiceProvider).ensure(car, coverBytes: coverUpload));
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
      final repo = ref.read(profileRepositoryProvider);
      // The kept originals of its blurred photos go with it (storage has no
      // cascade from the row, so the owner's app removes them).
      final car = await repo.fetchCar(carId);
      await repo.deleteCar(carId);
      final kept = car?.photoOriginals.values ?? const <String>[];
      if (kept.isNotEmpty) {
        try {
          await repo.deleteUnreferencedOriginals(ownerId: me, candidates: kept);
        } catch (e) {
          if (kDebugMode) debugPrint('Car delete: could not delete kept originals: $e');
        }
      }
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
