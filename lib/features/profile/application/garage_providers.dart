import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../data/garage_repository.dart';
import '../domain/car_documents.dart';
import '../domain/car_meet.dart';
import '../domain/car_mod.dart';

/// A car's mods, newest first. Private ones and prices come back for the
/// owner only.
final carModsProvider = FutureProvider.family<List<CarMod>, String>((ref, carId) => ref.watch(garageRepositoryProvider).carMods(carId));

/// Meets a car went to, newest first (its Meets count and history). Never
/// fails the page: an error reads as none.
final carMeetsProvider = FutureProvider.family<List<CarMeet>, String>((ref, carId) async {
  try {
    return await ref.watch(garageRepositoryProvider).carMeets(carId);
  } catch (e) {
    if (kDebugMode) debugPrint('carMeets($carId) failed: $e');
    return const <CarMeet>[];
  }
});

/// My papers for one car, or null when none are saved.
final carDocumentsProvider = FutureProvider.family<CarDocuments?, String>((ref, carId) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(null);
  return ref.watch(garageRepositoryProvider).documents(carId);
});

/// Add / edit / delete mods, save / clear documents.
class GarageActions {
  GarageActions(this._ref);
  final Ref _ref;

  GarageRepository get _repo => _ref.read(garageRepositoryProvider);

  String get _me {
    final id = _ref.read(currentUserIdProvider);
    if (id == null) throw const AppException('You\'re signed out. Sign in again.');
    return id;
  }

  /// [keptPhotos]: the photo list to keep when no new photo was picked
  /// (older entries can carry several). A [newPhoto] replaces them all.
  Future<void> saveMod({
    String? id,
    required String carId,
    required ModCategory category,
    required String title,
    required DateTime doneOn,
    double? cost,
    String? shop,
    String? vendorId,
    String? description,
    List<String> keptPhotos = const [],
    Uint8List? newPhoto,
    required bool isPrivate,
  }) async {
    if (title.trim().length < 2) throw const AppException('Name the mod, e.g. BC Racing coilovers.');
    final photos = newPhoto == null ? keptPhotos : [await _repo.uploadModPhoto(userId: _me, bytes: newPhoto)];
    await _repo.saveMod(
      id: id,
      carId: carId,
      category: category,
      title: title,
      doneOn: doneOn,
      cost: cost,
      shop: (shop ?? '').trim().isEmpty ? null : shop!.trim(),
      vendorId: vendorId,
      description: (description ?? '').trim().isEmpty ? null : description!.trim(),
      photoUrls: photos,
      isPrivate: isPrivate,
    );
    _ref.invalidate(carModsProvider(carId));
  }

  Future<void> deleteMod(String carId, String modId) async {
    await _repo.deleteMod(modId);
    _ref.invalidate(carModsProvider(carId));
  }

  /// Saving an empty form clears the row.
  Future<void> saveDocuments(CarDocuments docs) async {
    if (docs.isEmpty) {
      await _repo.deleteDocuments(docs.carId);
    } else {
      await _repo.saveDocuments(docs);
    }
    _ref.invalidate(carDocumentsProvider(docs.carId));
  }
}

final garageActionsProvider = Provider<GarageActions>((ref) => GarageActions(ref));
