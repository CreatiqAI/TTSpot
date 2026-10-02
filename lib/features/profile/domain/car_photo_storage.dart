import 'dart:typed_data';

import '../../../core/utils/thumbnails.dart' show thumbPath;
import 'garage_look.dart' show cutoutPath;

// Which car-photos files a save may delete, and where the originals of
// blurred photos are kept. Pure Dart: test/car_photo_storage_test and
// test/car_originals_test.

/// A car photo uploaded with its plate blurred is stored as
/// `<uid>/<millis>_<i>_pb.<ext>`, so the form knows it is already hidden.
const kPlateBlurredSuffix = '_pb';

/// True for a car photo uploaded with "Hide my number plate" on (see
/// [kPlateBlurredSuffix]). Older blurred photos (0.3.44–0.3.46, plain PNGs)
/// don't say so and are treated as unchecked.
bool isPlateBlurredUrl(String url) {
  final path = url.split('?').first.split('#').first;
  final name = path.substring(path.lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return stem.endsWith(kPlateBlurredSuffix);
}

/// The object path of [url] in the bucket at [bucketUrl] (its public URL,
/// `…/storage/v1/object/public/car-photos/`) when it is one of [ownerId]'s
/// own files: `<ownerId>/…`, no query (a `?v=` URL gets overwritten in
/// place), nothing like `..`. Null for anything else.
String? ownedPhotoPath(String url, {required String bucketUrl, required String ownerId}) {
  if (ownerId.isEmpty || url.contains('?') || url.contains('#')) return null;
  final path = _pathIn(url, bucketUrl);
  if (path == null) return null;
  final parts = path.split('/');
  if (parts.length < 2 || parts.first != ownerId) return null;
  if (parts.any((p) => p.isEmpty || p == '.' || p == '..' || p.contains(r'\'))) return null;
  return path;
}

/// After a save swapped the photos in [replaced] for blurred copies: the
/// storage paths to delete, because the originals show the plate and the
/// bucket is public.
///
/// Each replaced photo goes with its grid thumbnail (`…_t.jpg`) and the
/// garage cut-out made from it (`…_cut.png`), plus [staleCutouts] (a cut-out
/// stored under another name). Only [ownerId]'s own files, and none that
/// [referenced] still points at: every `photo_urls` entry and `cutout_url`
/// of every car of theirs, read after the save.
List<String> stalePhotoPaths({
  required String ownerId,
  required String bucketUrl,
  required Iterable<String> replaced,
  required Iterable<String> referenced,
  Iterable<String> staleCutouts = const [],
}) {
  // Compared as paths, so a differently encoded URL still counts as in use.
  // A referenced `?v=` URL keeps its file too.
  final keep = <String>{
    for (final u in referenced)
      ?_pathIn(u.split('?').first.split('#').first, bucketUrl),
  };
  final out = <String>[];
  void add(String p) {
    if (!keep.contains(p) && !out.contains(p)) out.add(p);
  }

  for (final u in replaced) {
    final p = ownedPhotoPath(u, bucketUrl: bucketUrl, ownerId: ownerId);
    if (p == null || keep.contains(p)) continue; // not theirs, or still on a car
    add(p);
    add(thumbPath(p));
    add(cutoutPath(p));
  }
  for (final u in staleCutouts) {
    final p = ownedPhotoPath(u, bucketUrl: bucketUrl, ownerId: ownerId);
    if (p != null) add(p);
  }
  return out;
}

/// `<bucketUrl><path>` → the decoded path, or null when [url] is elsewhere.
String? _pathIn(String url, String bucketUrl) {
  if (bucketUrl.isEmpty) return null;
  final prefix = bucketUrl.endsWith('/') ? bucketUrl : '$bucketUrl/';
  if (!url.startsWith(prefix)) return null;
  try {
    final path = Uri.decodeComponent(url.substring(prefix.length));
    return path.isEmpty ? null : path;
  } catch (_) {
    return null;
  }
}

// ─────────────────────────────────────────────────── kept originals ──
//
// Since 2 Oct 2026 a photo blurred on save keeps its original in the private
// `car-originals` bucket (`<uid>/<file>`), and `cars.photo_originals` maps
// the public blurred URL to it, so the blur can be taken off again ("Show
// original" in Check the plate). Photos blurred before that have no entry.

/// The private bucket the originals of blurred photos live in.
const kCarOriginalsBucket = 'car-originals';

/// One photo in a save, in order: keep a URL, or upload bytes (replacing a
/// saved photo when [replaces] is set).
class CarPhotoSave {
  const CarPhotoSave.keep(String this.url)
      : bytes = null,
        plateBlurred = false,
        replaces = null,
        original = null,
        keptOriginal = null;
  const CarPhotoSave.upload(Uint8List this.bytes, {this.plateBlurred = false, this.replaces, this.original, this.keptOriginal}) : url = null;

  final String? url;
  final Uint8List? bytes;
  final bool plateBlurred;

  /// The saved photo this upload takes the place of (it is deleted from the
  /// public bucket after the save, with its thumbnail and cut-out).
  final String? replaces;

  /// A blurred upload's original, to keep privately in car-originals.
  final Uint8List? original;

  /// A blurred upload whose original is already kept (its car-originals
  /// path): nothing new to store.
  final String? keptOriginal;

  /// Puts a blurred photo back without its blur: the original goes up again
  /// and its private copy is deleted after the save.
  bool get restoresOriginal => bytes != null && !plateBlurred && replaces != null && isPlateBlurredUrl(replaces!);
}

/// What Save does with one photo of a car form. Pure, so the decision is
/// tested on its own (CarFormPhoto.plan passes its state in).
///
/// [url] is set for a photo already on the car, [original] is what the
/// photo shows unblurred (picked bytes, a saved photo's download, or a kept
/// original brought back), [blurred] the blurred copy when one is ready.
/// [restored]: the member chose "Show original" on a blurred photo, so
/// [original] is its kept original ([originalPath]).
///
///  * Switch on with a blurred copy: the copy goes up (replacing [url]),
///    and the original is kept privately: already there ([originalPath]),
///    else [original] is stored with it.
///  * A restored photo otherwise: the original goes up again in place of
///    the blurred one (whose private copy then goes).
///  * Otherwise a saved photo stays as it is, a new one goes up as picked.
CarPhotoSave planCarPhoto({
  required String? url,
  required bool hidePlate,
  Uint8List? original,
  Uint8List? blurred,
  bool restored = false,
  String? originalPath,
}) {
  if (hidePlate && blurred != null) {
    return CarPhotoSave.upload(blurred, plateBlurred: true, replaces: url, keptOriginal: originalPath, original: originalPath == null ? original : null);
  }
  if (restored && url != null && original != null) return CarPhotoSave.upload(original, replaces: url);
  if (url != null) return CarPhotoSave.keep(url);
  if (original == null) throw StateError('A new photo without bytes');
  return CarPhotoSave.upload(original);
}

/// True when [path] is a file of [ownerId]'s in car-originals:
/// `<ownerId>/<file>`, nothing like `..`.
bool isOwnOriginalPath(String path, String ownerId) {
  if (ownerId.isEmpty || path.contains('?') || path.contains('#')) return false;
  final parts = path.split('/');
  if (parts.length < 2 || parts.first != ownerId) return false;
  return !parts.any((p) => p.isEmpty || p == '.' || p == '..' || p.contains(r'\'));
}

/// Where the original of a photo blurred on save is kept in car-originals:
/// under the same file name as the public photo it replaces when that was
/// one of [ownerId]'s own ([replacedPath], `<uid>/1700_0.jpg` →
/// `<uid>/1700_0.jpg`), else the blurred copy's name without `_pb`, with the
/// original's own extension ([blurredPath] `<uid>/1800_0_pb.jpg`, [ext]
/// `png` → `<uid>/1800_0.png`).
String originalPathFor({required String ownerId, required String blurredPath, String? replacedPath, required String ext}) {
  if (replacedPath != null && isOwnOriginalPath(replacedPath, ownerId)) {
    return '$ownerId/${replacedPath.substring(replacedPath.lastIndexOf('/') + 1)}';
  }
  final name = blurredPath.substring(blurredPath.lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  var stem = dot > 0 ? name.substring(0, dot) : name;
  if (stem.endsWith(kPlateBlurredSuffix)) stem = stem.substring(0, stem.length - kPlateBlurredSuffix.length);
  return '$ownerId/$stem.$ext';
}

/// `cars.photo_originals` after a save, and the private originals it no
/// longer uses.
///
/// [before] is the car's map as loaded, [photoUrls] its photos after the
/// save, [added] the blurred photos uploaded in this save and their
/// originals. An entry stays while its photo is still on the car; one whose
/// photo went (removed, or replaced by "Show original" or by a new blurred
/// copy) is dropped, and its private file with it unless another entry still
/// uses it (a re-blur of a kept original). Only [ownerId]'s own paths.
({Map<String, String> originals, List<String> dropped}) nextPhotoOriginals({
  required String ownerId,
  required Map<String, String> before,
  required List<String> photoUrls,
  Map<String, String> added = const {},
}) {
  final originals = <String, String>{};
  for (final u in photoUrls) {
    final p = added[u] ?? before[u];
    if (p != null && isOwnOriginalPath(p, ownerId)) originals[u] = p;
  }
  final used = originals.values.toSet();
  final dropped = <String>[];
  for (final p in before.values) {
    if (!used.contains(p) && isOwnOriginalPath(p, ownerId) && !dropped.contains(p)) dropped.add(p);
  }
  return (originals: originals, dropped: dropped);
}

/// Of [candidates], the private originals that may be deleted: [ownerId]'s
/// own that no car of theirs still points at ([referenced]: every value of
/// every car's `photo_originals`, read after the save or delete).
List<String> staleOriginalPaths({required String ownerId, required Iterable<String> candidates, required Iterable<String> referenced}) {
  final keep = referenced.toSet();
  final out = <String>[];
  for (final p in candidates) {
    if (isOwnOriginalPath(p, ownerId) && !keep.contains(p) && !out.contains(p)) out.add(p);
  }
  return out;
}

/// `cars.photo_originals` as stored (a JSON object of strings); anything
/// else reads as empty.
Map<String, String> parsePhotoOriginals(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final e in raw.entries)
      if (e.key is String && e.value is String) e.key as String: e.value as String,
  };
}
