import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/location/live_position.dart';
import '../../../core/geo/latlng.dart';

import '../../../core/utils/geo.dart';
import '../../events/data/events_repository.dart';
import '../../events/domain/event.dart';
import '../../safety/data/safety_repository.dart';
import '../../social/application/community_providers.dart';
import '../../social/data/community_repository.dart';
import '../../social/data/social_repository.dart';
import '../../social/domain/club.dart';
import '../../social/domain/post.dart';
import 'map_filters.dart';

export 'map_filters.dart';

// ----------------------------------------------------------------- filters ---

/// The Events tab's chips (all hosts, all types, this week to start with).
class EventFilterNotifier extends Notifier<EventFilter> {
  @override
  EventFilter build() => EventFilter.initial;
  void set(EventFilter f) => state = f;
  void toggleHost(HostChip c) => state = state.toggleHost(c);
  void toggleType(TypeChip c) => state = state.toggleType(c);
  void toggleWhen(WhenChip c) => state = state.toggleWhen(c);
  void allHosts() => state = state.copyWith(hosts: const {});
  void allTypes() => state = state.copyWith(types: const {});
  void reset() => state = EventFilter.initial;
}

final eventFilterProvider = NotifierProvider<EventFilterNotifier, EventFilter>(EventFilterNotifier.new);

/// A chip row on the Now or Spots tab: the picked chips, empty = All.
class ChipSetNotifier<T> extends Notifier<Set<T>> {
  @override
  Set<T> build() => <T>{};
  void toggle(T c) => state = state.contains(c) ? ({...state}..remove(c)) : {...state, c};
  void all() => state = <T>{};
}

final spotChipsProvider = NotifierProvider<ChipSetNotifier<SpotChip>, Set<SpotChip>>(ChipSetNotifier<SpotChip>.new);
final nowChipsProvider = NotifierProvider<ChipSetNotifier<NowChip>, Set<NowChip>>(ChipSetNotifier<NowChip>.new);

// ---------------------------------------------------------------- viewport ---

/// Visible map bounds, updated when the camera stops moving.
class MapViewportNotifier extends Notifier<LatLngBounds?> {
  @override
  LatLngBounds? build() => null;
  void set(LatLngBounds b) => state = b;
}

final mapViewportProvider = NotifierProvider<MapViewportNotifier, LatLngBounds?>(MapViewportNotifier.new);

// ---------------------------------------------------------------- location ---

/// The user's position, or null when denied / unavailable. Resolves once;
/// call `ref.invalidate(userLocationProvider)` to retry.
final userLocationProvider = FutureProvider<LatLng?>((ref) async {
  // Live GPS wins: this re-resolves every time the stream moves me (>= 5 m).
  final live = ref.watch(livePositionProvider);
  if (live != null) return live.latLng;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    // Only check: the permissions page (and the locate button) ask. Asking
    // here popped the system prompt over the map before that page showed.
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return null;
    }
    // Permission is there but the stream isn't running yet (first launch): start it.
    unawaited(ref.read(livePositionProvider.notifier).start());
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && DateTime.now().difference(last.timestamp) < LivePositionNotifier.cachedMaxAge) {
      return LatLng(last.latitude, last.longitude);
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 8)),
    );
    return LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
});

/// Where distances are measured from: the user, or KL when unknown.
final mapOriginProvider = Provider<LatLng>((ref) => ref.watch(userLocationProvider).value ?? kualaLumpur);

// ------------------------------------------------------------------ events ---

/// Every meet in the viewport that is not over yet (under way or to come),
/// minus blocked organizers. The Events tab's chips filter it on the phone
/// ([filteredMapEventsProvider]), so a chip never waits for the network.
final mapEventsProvider = FutureProvider<List<Event>>((ref) async {
  final bounds = ref.watch(mapViewportProvider) ?? klangValleyBounds;
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  // Meets under way started up to 8 h ago (the live window's longest).
  final from = DateTime.now().subtract(const Duration(hours: 8));
  final events = await ref.watch(eventsRepositoryProvider).fetchUpcomingInBounds(bounds: bounds, from: from, limit: 200);
  return events.where((e) => !e.isPast && !blocked.contains(e.organizerId)).toList();
});

/// The viewport's meets that pass the Events tab's chips (zoom aside: the
/// map hides the small tiers when zoomed out, the list does not).
final filteredMapEventsProvider = Provider<AsyncValue<List<Event>>>((ref) {
  final filter = ref.watch(eventFilterProvider);
  return ref.watch(mapEventsProvider).whenData((events) {
    final now = DateTime.now();
    return events.where((e) => filter.matches(e, now)).toList();
  });
});

/// What each Events chip would show right now (the numbers on the chips).
final eventChipCountsProvider = Provider<EventChipCounts?>((ref) {
  final events = ref.watch(mapEventsProvider).value;
  if (events == null) return null;
  return ref.watch(eventFilterProvider).counts(events, DateTime.now());
});

class MapSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String q) => state = q;
}

final mapSearchProvider = NotifierProvider<MapSearchNotifier, String>(MapSearchNotifier.new);

/// What the bottom sheet lists: search-filtered and sorted by distance.
final visibleMapEventsProvider = Provider<AsyncValue<List<Event>>>((ref) {
  final origin = ref.watch(mapOriginProvider);
  final query = ref.watch(mapSearchProvider).trim().toLowerCase();
  return ref.watch(filteredMapEventsProvider).whenData((events) {
    var list = events;
    if (query.isNotEmpty) {
      list = list
          .where((e) => e.title.toLowerCase().contains(query) || e.venueName.toLowerCase().contains(query))
          .toList();
    }
    return [...list]..sort(
        (a, b) => distanceKm(origin, a.latLng).compareTo(distanceKm(origin, b.latLng)),
      );
  });
});

// ------------------------------------------------------------------- modes ---

/// The tab the map is on ([MapMode] lives in map_filters.dart).
class MapModeNotifier extends Notifier<MapMode> {
  @override
  MapMode build() => MapMode.now;
  void set(MapMode m) => state = m;
}

final mapModeProvider = NotifierProvider<MapModeNotifier, MapMode>(MapModeNotifier.new);

// --------------------------------------------------------------------- now ---

/// Meets inside their live window, in the viewport.
final liveEventsProvider = FutureProvider<List<Event>>((ref) async {
  final bounds = ref.watch(mapViewportProvider) ?? klangValleyBounds;
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final events = await ref.watch(eventsRepositoryProvider).fetchLiveInBounds(bounds: bounds);
  return events.where((e) => !blocked.contains(e.organizerId)).toList();
});

/// The meets the Now tab draws: the live ones and the viewport's meets this
/// week, once each ([nowEvents]). No query of its own: both lists are
/// already fetched for the view.
final nowMapEventsProvider = Provider<List<Event>>((ref) {
  final live = ref.watch(liveEventsProvider).value ?? const <Event>[];
  final inView = ref.watch(mapEventsProvider).value ?? const <Event>[];
  return nowEvents(live, inView, DateTime.now());
});

/// Moments from the last 24 h with a location, in the viewport.
final liveMomentsProvider = FutureProvider<List<Story>>((ref) async {
  final bounds = ref.watch(mapViewportProvider) ?? klangValleyBounds;
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final list = await ref.watch(socialRepositoryProvider).fetchLiveMomentsInBounds(
        south: bounds.southwest.latitude,
        north: bounds.northeast.latitude,
        west: bounds.southwest.longitude,
        east: bounds.northeast.longitude,
      );
  return list.where((m) => !blocked.contains(m.authorId)).toList();
});

// ------------------------------------------------------------------- spots ---

/// Map view vs. meets list on the Map tab.
class MapListViewNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
  void toggle() => state = !state;
}

final mapListViewProvider = NotifierProvider<MapListViewNotifier, bool>(MapListViewNotifier.new);

/// Spots to check in at, in the viewport, best first.
final spotsProvider = FutureProvider<List<Place>>((ref) async {
  final bounds = ref.watch(mapViewportProvider) ?? klangValleyBounds;
  return ref.watch(communityRepositoryProvider).spotsInBounds(
        south: bounds.southwest.latitude,
        north: bounds.northeast.latitude,
        west: bounds.southwest.longitude,
        east: bounds.northeast.longitude,
      );
});

/// Whether a spot matches what is typed in the sheet's search.
bool spotMatches(Place p, String query) {
  final q = query.trim().toLowerCase();
  return q.isEmpty || p.name.toLowerCase().contains(q) || p.tags.any((t) => t.toLowerCase().contains(q));
}

/// Search-filtered spots in the viewport for the sheet (the Spots chips
/// apply too): nearest to me first.
final visibleSpotsProvider = Provider<AsyncValue<List<Place>>>((ref) {
  final origin = ref.watch(mapOriginProvider);
  final query = ref.watch(mapSearchProvider);
  final chips = ref.watch(spotChipsProvider);
  final saved = ref.watch(savedPlaceIdsProvider);
  return ref.watch(spotsProvider).whenData((places) {
    final list = places.where((p) => spotMatches(p, query) && spotChipsMatch(p, chips, saved)).toList();
    return list..sort((a, b) => distanceKm(origin, a.latLng).compareTo(distanceKm(origin, b.latLng)));
  });
});

/// Where "nearest" is measured from, rounded to ~1 km so a GPS fix every few
/// metres does not re-query the nearest spots.
final _nearOriginProvider = Provider<LatLng>((ref) {
  final o = ref.watch(mapOriginProvider);
  double r(double v) => (v * 100).roundToDouble() / 100;
  return LatLng(r(o.latitude), r(o.longitude));
});

/// The 5 spots nearest to me, however far, nearest first. Feeds the Spots
/// layer's opening view, the "spots nearby" pill and the list when the
/// viewport has none. Falls back to the top spots sorted by distance until
/// the nearest_spots function is deployed.
final nearestSpotsProvider = FutureProvider<List<Place>>((ref) async {
  final o = ref.watch(_nearOriginProvider);
  final repo = ref.watch(communityRepositoryProvider);
  try {
    return await repo.nearestSpots(lat: o.latitude, lng: o.longitude, limit: 5);
  } on PostgrestException catch (e) {
    if (e.code != 'PGRST202' && e.code != '42883') rethrow;
    final top = await repo.topSpots(limit: 80);
    return (top..sort((a, b) => distanceKm(o, a.latLng).compareTo(distanceKm(o, b.latLng)))).take(5).toList();
  }
});

/// Every place the Spots tab could draw: the viewport's spots plus every
/// saved spot (wherever it is), once each, before the chips.
final mapAllPlacesProvider = Provider<List<Place>>((ref) {
  final inView = ref.watch(spotsProvider).value ?? const <Place>[];
  final saved = ref.watch(savedPlacesProvider).value ?? const <Place>[];
  final seen = <String>{};
  return [
    for (final p in [...saved, ...inView])
      if (seen.add(p.id)) p,
  ];
});

/// What the Spots tab draws: [mapAllPlacesProvider] through its chips.
final mapPlacesProvider = Provider<List<Place>>((ref) {
  final chips = ref.watch(spotChipsProvider);
  final saved = ref.watch(savedPlaceIdsProvider);
  return [for (final p in ref.watch(mapAllPlacesProvider)) if (spotChipsMatch(p, chips, saved)) p];
});

/// What each Spots chip would show in the viewport (plus saved spots).
final spotChipCountsProvider = Provider<(int, Map<SpotChip, int>)>((ref) {
  return spotChipCounts(ref.watch(mapAllPlacesProvider), ref.watch(savedPlaceIdsProvider));
});

/// The member closed the "spots nearby" pill: it stays away for the session.
class SpotsHintDismissedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void dismiss() => state = true;
}

final spotsHintDismissedProvider = NotifierProvider<SpotsHintDismissedNotifier, bool>(SpotsHintDismissedNotifier.new);

/// Where another screen asked the map to go. With [place], the map also
/// opens that place's preview card (Search, "Show on map" on a spot).
class MapFocus {
  const MapFocus(this.at, {this.place});
  final LatLng at;
  final Place? place;
}

/// A one-off request for the map to glide somewhere. The map clears it once
/// handled.
class MapFocusNotifier extends Notifier<MapFocus?> {
  @override
  MapFocus? build() => null;
  void request(LatLng at) => state = MapFocus(at);
  /// Glide to [p] and open its preview card.
  void preview(Place p) => state = MapFocus(p.latLng, place: p);
  void clear() => state = null;
}

final mapFocusProvider = NotifierProvider<MapFocusNotifier, MapFocus?>(MapFocusNotifier.new);
