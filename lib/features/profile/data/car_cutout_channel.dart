import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/garage_look.dart';

/// A cut-out from the phone: the PNG (alpha, cropped to the car with a little
/// room around it) and the numbers the quality gate reads.
class CutoutResult {
  const CutoutResult(this.report, [this.png]);
  final CutoutReport report;
  final Uint8List? png;
}

/// Cuts the car out of a photo on the phone, no plugin and nothing sent
/// anywhere: Apple Vision's foreground instance mask on iPhone (iOS 17+) and
/// ML Kit subject segmentation through Google Play services on Android. Only
/// the largest subject is kept. See CarCutout.kt and AppDelegate.swift.
abstract final class CarCutoutChannel {
  static const _channel = MethodChannel('my.ttspot.app/cutout');

  /// Longest side of the PNG that comes back. The bay is about 370 pt wide,
  /// so this covers a 3x screen without shipping the full photo.
  static const maxSide = 1080;

  /// Set once the phone said it can't (old iOS, no Google Play): no point
  /// asking again this session.
  static bool unsupported = false;

  static Future<CutoutResult> cut(Uint8List bytes) async {
    if (unsupported || kIsWeb) return const CutoutResult(CutoutReport(status: CutoutStatus.unsupported));
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('cutout', {'bytes': bytes, 'maxSide': maxSide});
      final report = CutoutReport.fromMap(m ?? const {});
      if (report.status == CutoutStatus.unsupported) unsupported = true;
      return CutoutResult(report, m?['png'] as Uint8List?);
    } on MissingPluginException {
      unsupported = true;
      return const CutoutResult(CutoutReport(status: CutoutStatus.unsupported));
    } on PlatformException catch (e) {
      return CutoutResult(CutoutReport(status: CutoutStatus.error, message: '${e.code}: ${e.message}'));
    }
  }
}
