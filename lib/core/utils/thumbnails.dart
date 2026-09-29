import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/media.dart';
import '../env.dart';

// Grid thumbnails. A photo that also shows as a small tile (post, moment,
// car, mod, spot, check-in, product and meet cover photos) gets a ~480 px
// JPEG twin in the same bucket: `abc.jpg` → `abc_t.jpg` (always `.jpg`, also
// for a PNG original). Tiles load it with ThumbImage, which falls back to the
// full photo when there is none (anything uploaded before thumbnails).
// Nothing deletes these photos from storage yet; whatever starts to should
// remove `thumbPath(path)` too.

/// Buckets whose photos can have a thumbnail.
const _thumbBuckets = {'post-photos', 'car-photos', 'event-covers'};

/// `uid/posts/123.png` → `uid/posts/123_t.jpg`.
String thumbPath(String path) {
  final dot = path.lastIndexOf('.');
  final stem = dot > path.lastIndexOf('/') ? path.substring(0, dot) : path;
  return '${stem}_t.jpg';
}

/// Uploads the thumbnail of [bytes], stored at [path] in [bucket]. Never
/// throws: without a thumbnail the grid just shows the full photo.
Future<void> uploadThumb(StorageFileApi bucket, String path, Uint8List bytes) async {
  try {
    final thumb = await FlutterImageCompress.compressWithList(bytes, minWidth: kThumbSide, minHeight: kThumbSide, quality: kThumbQuality);
    await bucket.uploadBinary(thumbPath(path), thumb, fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: kImmutableCacheControl));
  } catch (e) {
    if (kDebugMode) debugPrint('Thumbnail for $path failed: $e');
  }
}

/// The thumbnail URL of one of our photos, or [url] itself for anything else
/// (another host, a bucket without thumbnails, a `?v=` URL that gets
/// overwritten, a local file).
String thumbUrl(String url) {
  final prefix = '${Env.supabaseUrl}/storage/v1/object/public/';
  if (Env.supabaseUrl.isEmpty || !url.startsWith(prefix) || url.contains('?')) return url;
  final rest = url.substring(prefix.length); // <bucket>/<path>
  final slash = rest.indexOf('/');
  if (slash < 0 || !_thumbBuckets.contains(rest.substring(0, slash)) || rest.endsWith('_t.jpg')) return url;
  return '$prefix${thumbPath(rest)}';
}
