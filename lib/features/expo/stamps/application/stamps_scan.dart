import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/friendly_error.dart';
import '../../../points/application/points_providers.dart';

/// A booth's stamp QR (`ttspot://booth/<exhibitorId>/<code>`). Track C.
Future<ScanOutcome> handleBoothScan(Ref ref, {required String exhibitorId, required String code}) async =>
    throw const AppException('Booth stamps are coming soon.');

/// A member's event pass QR (`ttspot://pass/<eventId>/<passCode>`), scanned by
/// booth staff to save a lead. Track C.
Future<ScanOutcome> handlePassScan(Ref ref, {required String eventId, required String passCode}) async =>
    throw const AppException("That's a member's event pass. Booth staff scan it to save a lead.");
