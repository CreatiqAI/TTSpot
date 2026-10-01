import '../../../core/config/media.dart';

/// Why a picked video can't go on a post, or null when it can. [bytes] is
/// the file size; [length] its duration once the player has read it (the
/// library picker does not always enforce the 60 s cap). A video that rounds
/// to 60 s is fine, so "1:00" on screen always means it fits.
String? postVideoProblem({required int bytes, Duration? length}) {
  if (bytes <= 0) return 'That video could not be read. Try another.';
  if (bytes > kPostVideoMaxMb * 1024 * 1024) {
    return 'That video is over $kPostVideoMaxMb MB. Pick a shorter one or trim it first.';
  }
  if (length != null && (length.inMilliseconds / 1000).round() > kPostVideoMaxDuration.inSeconds) {
    return 'Videos can be up to ${kPostVideoMaxDuration.inSeconds} seconds. Trim it in your gallery first.';
  }
  return null;
}

/// Storage extension and content type for a picked video file: QuickTime
/// stays QuickTime (iPhone), everything else goes up as MP4.
({String ext, String contentType}) postVideoFormat(String path) =>
    path.toLowerCase().endsWith('.mov') ? (ext: 'mov', contentType: 'video/quicktime') : (ext: 'mp4', contentType: 'video/mp4');
