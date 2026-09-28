import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../data/floorplan_repository.dart';
import '../domain/floorplan.dart';

/// Levels (lowest first) with their pins, for one event.
final floorLevelsProvider = FutureProvider.autoDispose.family<List<FloorLevel>, String>((ref, eventId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(floorplanRepositoryProvider).levels(eventId);
});

/// My own spot at this event, or null.
final myEventPositionProvider = FutureProvider.autoDispose.family<MyPosition?, String>((ref, eventId) {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return Future.value(null);
  return ref.watch(floorplanRepositoryProvider).myPosition(eventId, me);
});

/// Host, club officer or admin (public.is_meet_host).
final isMeetHostProvider = FutureProvider.autoDispose.family<bool, String>((ref, eventId) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(false);
  return ref.watch(floorplanRepositoryProvider).isHost(eventId).catchError((_) => false);
});

/// Host only: members per level. Empty for everyone else.
final floorLevelCountsProvider = FutureProvider.autoDispose.family<Map<String, int>, String>((ref, eventId) async {
  final host = await ref.watch(isMeetHostProvider(eventId).future);
  if (!host) return const {};
  return ref.watch(floorplanRepositoryProvider).levelCounts(eventId);
});
