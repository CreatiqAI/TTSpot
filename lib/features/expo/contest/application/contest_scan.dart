import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/friendly_error.dart';
import '../../../points/application/points_providers.dart';

/// A show car's vote QR (`ttspot://vote/<entryId>`). Track E.
Future<ScanOutcome> handleVoteScan(Ref ref, {required String entryId}) async =>
    throw const AppException('Show car voting is coming soon.');
