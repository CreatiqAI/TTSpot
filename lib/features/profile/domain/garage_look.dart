import 'car.dart';

/// How a car shows in the garage: standing in the bay as a cut-out of its own
/// photo, or as a silver-framed photo card.
enum GarageLook { cutout, card }

/// The two garage views, saved as `profiles.settings.garage_view`.
enum GarageView {
  bay,
  cards;

  static GarageView parse(String? v) => v == 'cards' ? GarageView.cards : GarageView.bay;
}

/// A cut-out that still matches the car's cover photo stands in the bay;
/// anything else (none yet, failed the quality check, made from an older
/// cover, or the member picked the card) shows the photo card.
GarageLook garageLookFor(Car car) {
  final source = car.photoCover;
  if (car.garageStyle == 'card') return GarageLook.card;
  if (car.cutoutUrl == null || source == null || car.cutoutSource != source) return GarageLook.card;
  return GarageLook.cutout;
}

/// The owner's phone should try a cut-out of this car: it has a cover photo
/// and no attempt was stored for that photo yet. A stored attempt that failed
/// the quality check (`cutout_url` null, `cutout_source` = the cover) counts
/// as done, so a car isn't cut again on every visit.
bool needsCutout(Car car) {
  final source = car.photoCover;
  if (source == null || car.garageStyle == 'card') return false;
  return car.cutoutSource != source;
}

/// What the native cut-out reports (see `my.ttspot.app/cutout` in
/// MainActivity.kt / CarCutout.kt and AppDelegate.swift).
enum CutoutStatus {
  /// A subject was found and cut out.
  ok,

  /// Nothing stood out from the background.
  noSubject,

  /// This phone can't do it (iOS below 17, Android without Google Play).
  unsupported,

  /// Android is still downloading the segmentation model; try again later.
  notReady,

  /// Anything else (bad image, out of memory…); try again another time.
  error;

  static CutoutStatus parse(Object? v) => switch (v) {
        'ok' => CutoutStatus.ok,
        'no_subject' => CutoutStatus.noSubject,
        'unsupported' => CutoutStatus.unsupported,
        'not_ready' => CutoutStatus.notReady,
        _ => CutoutStatus.error,
      };
}

/// The quality numbers that come back with a cut-out. Fractions are of the
/// whole photo, measured on the largest subject only.
class CutoutReport {
  const CutoutReport({
    required this.status,
    this.areaRatio = 0,
    this.edgeLeft = 0,
    this.edgeRight = 0,
    this.edgeTop = 0,
    this.edgeBottom = 0,
    this.subjects = 0,
    this.secondRatio = 0,
    this.width = 0,
    this.height = 0,
    this.message,
  });

  final CutoutStatus status;

  /// Subject pixels / photo pixels.
  final double areaRatio;

  /// How much of each photo edge the subject runs into (0 = clear of it,
  /// 1 = along the whole edge). A car cut off by the frame shows up here.
  final double edgeLeft;
  final double edgeRight;
  final double edgeTop;
  final double edgeBottom;

  /// Subjects found in the photo.
  final int subjects;

  /// The second-largest subject's area over the largest's (0 when alone).
  final double secondRatio;

  /// Size of the subject's box in the source photo, in pixels.
  final int width;
  final int height;

  /// Native error text, for the debug log only.
  final String? message;

  double get aspect => height == 0 ? 0 : width / height;

  factory CutoutReport.fromMap(Map<String, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    return CutoutReport(
      status: CutoutStatus.parse(m['status']),
      areaRatio: d('areaRatio'),
      edgeLeft: d('edgeLeft'),
      edgeRight: d('edgeRight'),
      edgeTop: d('edgeTop'),
      edgeBottom: d('edgeBottom'),
      subjects: i('subjects'),
      secondRatio: d('secondRatio'),
      width: i('width'),
      height: i('height'),
      message: m['message'] as String?,
    );
  }

  @override
  String toString() =>
      'CutoutReport(${status.name}, area ${areaRatio.toStringAsFixed(3)}, edges L${edgeLeft.toStringAsFixed(2)} R${edgeRight.toStringAsFixed(2)} '
      'B${edgeBottom.toStringAsFixed(2)} T${edgeTop.toStringAsFixed(2)}, subjects $subjects (2nd ${secondRatio.toStringAsFixed(2)}), ${width}x$height)';
}

/// Why a cut-out goes to the card instead of the bay.
enum CutoutReject {
  failed,
  noSubject,
  tooSmall,
  tooBig,
  croppedSide,
  croppedBottom,
  crowded,
  notCarShaped,
  lowResolution,
}

/// The quality gate: the bay only gets one clear main subject, whole (not cut
/// off at the left, right or bottom of the photo), at a sensible size and
/// shape. Everything else stays a photo card, which always looks right.
abstract final class CutoutGate {
  /// Subject smaller than this share of the photo: a far-away car that would
  /// look soft blown up to the bay's width.
  static const minArea = 0.06;

  /// Bigger than this: a close-up that is all car, usually cut off anyway.
  static const maxArea = 0.88;

  /// Share of the left or right edge the car may touch (a mirror tip, a
  /// bumper corner) before it counts as cut off.
  static const maxSideEdge = 0.08;

  /// Share of the bottom edge: the tyres may just touch it.
  static const maxBottomEdge = 0.22;

  /// A second subject this big next to the main one (another car, a person
  /// leaning on it) makes the photo too busy to cut out cleanly.
  static const maxSecondRatio = 0.35;

  /// Width over height of the subject's box: cars are wider than tall, from
  /// any side. A tall subject is more likely a person or a close-up.
  static const minAspect = 0.9;

  /// The subject's box must be at least this wide in the source photo.
  static const minWidthPx = 320;

  /// Null when the cut-out may stand in the bay.
  static CutoutReject? check(CutoutReport r) {
    if (r.status == CutoutStatus.noSubject || (r.status == CutoutStatus.ok && r.subjects == 0)) return CutoutReject.noSubject;
    if (r.status != CutoutStatus.ok) return CutoutReject.failed;
    if (r.areaRatio < minArea) return CutoutReject.tooSmall;
    if (r.areaRatio > maxArea) return CutoutReject.tooBig;
    if (r.edgeLeft > maxSideEdge || r.edgeRight > maxSideEdge) return CutoutReject.croppedSide;
    if (r.edgeBottom > maxBottomEdge) return CutoutReject.croppedBottom;
    if (r.subjects > 1 && r.secondRatio > maxSecondRatio) return CutoutReject.crowded;
    if (r.aspect < minAspect) return CutoutReject.notCarShaped;
    if (r.width < minWidthPx) return CutoutReject.lowResolution;
    return null;
  }

  static bool passes(CutoutReport r) => check(r) == null;
}

/// `uid/1727_0.jpg` → `uid/1727_0_cut.png`: the cut-out sits next to its photo.
String cutoutPath(String photoPath) {
  final dot = photoPath.lastIndexOf('.');
  final stem = dot > photoPath.lastIndexOf('/') ? photoPath.substring(0, dot) : photoPath;
  return '${stem}_cut.png';
}
