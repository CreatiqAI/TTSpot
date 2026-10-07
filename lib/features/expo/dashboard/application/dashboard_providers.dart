import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dashboard_repository.dart';
import '../domain/dashboard.dart';

final expoDashboardProvider = FutureProvider.autoDispose.family<ExpoDashboard, String>((ref, eventId) {
  return ref.watch(dashboardRepositoryProvider).dashboard(eventId);
});
