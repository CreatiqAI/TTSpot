import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/utils/geo.dart';
import '../../events/data/events_repository.dart';
import '../../events/domain/event.dart';
import '../../safety/data/safety_repository.dart';
import '../../social/data/community_repository.dart';
import '../../social/data/social_repository.dart';
import '../../social/domain/club.dart';
import '../../social/domain/post.dart';

// ----------------------------------------------------------------- filters ---

enum DateRange {
  today('Today'),
  weekend('This weekend'),
  month('This month'),
  all('Upcoming');

  const DateRange(this.label);
  final String label;

  /// Inclusive start / exclusive end, in local time. `end == null` = no limit.
  ({DateTime start, DateTime? end}) window({DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    switch (this) {
      case DateRange.today:
        return (start: n, end: today.add(const Duration(days: 1)));
      case DateRange.weekend:
        // Saturday of this week (or last Saturday if today is Sunday).
        final sat = n.weekday == DateTime.sunday
            ? today.subtract(const Duration(days: 1))
            : today.add(Duration(days: (DateTime.saturday - n.weekday) % 7));
        final start = sat.isAfter(n) ? sat : n;
        return (start: start, end: sat.add(const Duration(days: 2)));
      case DateRange.month:
        return (start: n, end: DateTime(n.year, n.month + 1, 1));
      case DateRange.all:
        return (start: n, end: null);
    }
  }
}

class MapFilters {
  const MapFilters({this.range = DateRange.all, this.types = const {}});
  final DateRange range;
  final Set<EventType> types;

  bool get isDefault => range == DateRange.all && types.isEmpty;

  /// Text for the floating pill, e.g. "This weekend · 2 types".
  String get label {
    if (types.isEmpty) return range.label;
    if (types.length == 1) return '${range.label} · ${types.first.label}';
    return '${range.label} · ${types.length} types';
  }

  MapFilters copyWith({DateRange? range, Set<EventType>? types}) =>
      MapFilters(range: range ?? this.range, types: types ?? this.types);
}

class MapFiltersNotifier extends Notifier<MapFilters> {
  @override
  MapFilters build() => const MapFilters();

  void setRange(DateRange r) => state = state.copyWith(range: r);

  void toggleType(EventType t) {
    final next = {...state.types};
    next.contains(t) ? next.remove(t) : next.add(t);
    state = state.copyWith(types: next);
  }

  void clear() => state = const MapFilters();
}

final mapFiltersProvider = NotifierProvider<MapFiltersNotifier, MapFilters>(MapFiltersNotifier.new);

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
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return null;
    }
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return LatLng(last.latitude, last.longitude);
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)),
    );
    return LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
});

/// Where distances are measured from: the user, or KL when unknown.
final mapOriginProvider = Provider<LatLng>((ref) => ref.watch(userLocationProvider).value ?? kualaLumpur);

// ------------------------------------------------------------------ events ---

/// Events matching the filters inside the current viewport, minus blocked organizers.
final mapEventsProvider = FutureProvider<List<Event>>((ref) async {
  final filters = ref.watch(mapFiltersProvider);
  final bounds = ref.watch(mapViewportProvider) ?? klangValleyBounds;
  final blocked = await ref.watch(blockedUserIdsProvider.future);
  final window = filters.range.window();

  final events = await ref.watch(eventsRepositoryProvider).fetchUpcomingInBounds(
        bounds: bounds,
        from: window.start,
        to: window.end,
        types: filters.types,
      );
  return events.where((e) => !blocked.contains(e.organizerId)).toList();
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
  return ref.watch(mapEventsProvider).whenData((events) {
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

/// The three time layers of the map.
enum MapMode {
  now('Now'),
  upcoming('Upcoming'),
  spots('Spots');

  const MapMode(this.label);
  final String label;
}

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

/// Search-filtered spots for the sheet: best first, distance breaks ties.
final visibleSpotsProvider = Provider<AsyncValue<List<Place>>>((ref) {
  final origin = ref.watch(mapOriginProvider);
  final query = ref.watch(mapSearchProvider).trim().toLowerCase();
  return ref.watch(spotsProvider).whenData((places) {
    var list = places;
    if (query.isNotEmpty) {
      list = list.where((p) => p.name.toLowerCase().contains(query) || p.tags.any((t) => t.toLowerCase().contains(query))).toList();
    }
    return [...list]..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return distanceKm(origin, a.latLng).compareTo(distanceKm(origin, b.latLng));
      });
  });
});
