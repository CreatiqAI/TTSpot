import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../data/exhibitors_repository.dart';
import '../domain/exhibitor.dart';

/// An event's exhibitors, partners first. Empty when signed out.
final eventExhibitorsProvider = FutureProvider.autoDispose.family<List<Exhibitor>, String>((ref, eventId) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const <Exhibitor>[]);
  return ref.watch(exhibitorsRepositoryProvider).list(eventId);
});

/// One exhibitor by id, from the event's list (null while loading or gone).
Exhibitor? exhibitorById(List<Exhibitor>? all, String id) {
  if (all == null) return null;
  for (final e in all) {
    if (e.id == id) return e;
  }
  return null;
}
