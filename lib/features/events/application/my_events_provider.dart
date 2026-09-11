import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../data/events_repository.dart';
import '../domain/event.dart';

class MyEvents {
  const MyEvents({required this.upcoming, required this.past});
  final List<Event> upcoming; // soonest first
  final List<Event> past; // most recent first
}

/// Everything I organise or joined, split by date. Invalidate after RSVP/create.
final myEventsProvider = FutureProvider<MyEvents>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const MyEvents(upcoming: [], past: []);
  final all = await ref.watch(eventsRepositoryProvider).fetchMine(me);
  final now = DateTime.now();
  final upcoming = all.where((e) => !e.startsAt.isBefore(now)).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  final past = all.where((e) => e.startsAt.isBefore(now)).toList();
  return MyEvents(upcoming: upcoming, past: past);
});
