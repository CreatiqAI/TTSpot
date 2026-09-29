import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/latlng.dart';
import '../../events/data/events_repository.dart';
import '../../events/domain/event.dart';
import '../../safety/data/safety_repository.dart';
import '../../social/data/community_repository.dart';
import '../../social/domain/club.dart';
import 'map_providers.dart';

// The Map tab's list view: every upcoming meet, every club and every spot,
// not only what is inside the map's viewport. It shows while
// `mapListViewProvider` is true.

/// The list's three tabs.
enum MapListTab {
  meets('Meets'),
  clubs('Clubs'),
  spots('Spots');

  const MapListTab(this.label);
  final String label;
}

/// "Near me" on the list: within this many km of me.
const kNearMeKm = 30.0;

/// Where the list measures distances from: me (else KL), rounded to ~1 km so
/// a GPS fix every few metres does not re-sort the rows under a finger.
final listOriginProvider = Provider<LatLng>((ref) {
  final o = ref.watch(mapOriginProvider);
  double r(double v) => (v * 100).roundToDouble() / 100;
  return LatLng(r(o.latitude), r(o.longitude));
});

/// Every meet that is not over yet, anywhere, soonest first, minus blocked
/// hosts. Meets under way (started in the last 8 h and still open) stay in.
final allUpcomingMeetsProvider = FutureProvider<List<Event>>((ref) async {
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final from = DateTime.now().subtract(const Duration(hours: 8));
  final events = await ref.watch(eventsRepositoryProvider).fetchUpcoming(from: from);
  return events.where((e) => !e.isPast && !blocked.contains(e.organizerId)).toList();
});

/// Who hosts the meets that have no club or partner on them, by user id.
final meetHostNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final meets = await ref.watch(allUpcomingMeetsProvider.future);
  final ids = meets.where((e) => e.clubName == null && e.vendorName == null).map((e) => e.organizerId);
  return ref.watch(eventsRepositoryProvider).hostNames(ids);
});

/// Every club. The list sorts and filters them itself.
final allClubsProvider = FutureProvider<List<Club>>((ref) => ref.watch(communityRepositoryProvider).clubs(limit: 200));

/// Meets per club over the last 30 days and ahead: the "Most active" signal.
final clubActivityProvider = FutureProvider<Map<String, int>>((ref) {
  final since = DateTime.now().subtract(const Duration(days: 30));
  return ref.watch(communityRepositoryProvider).clubMeetCounts(since: since);
});

/// Every spot and partner shop. The list sorts them by distance.
final allSpotsProvider = FutureProvider<List<Place>>((ref) => ref.watch(communityRepositoryProvider).topSpots(limit: 300));
