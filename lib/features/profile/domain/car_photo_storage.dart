import '../../../core/utils/thumbnails.dart' show thumbPath;
import 'garage_look.dart' show cutoutPath;

// Which car-photos files a save may delete. Pure Dart: test/car_photo_storage_test.

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
