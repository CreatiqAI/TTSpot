import '../../../core/theme/app_images.dart' show crestAsset;
import '../../events/domain/event.dart';
import '../../social/domain/club.dart';

// The map's rules, kept free of Flutter so they can be unit tested: how big
// an event's pin is and from which zoom it shows (its tier), and what each
// quick-filter chip on the Now, Events and Spots tabs keeps.
//
// Zoom is Google-style everywhere in the app (Mapbox zoom + 1, see
// AppMapController.cameraView): about 8 = the whole Klang Valley and beyond,
// 11 = a city, 12.5 = a district, 14.5 = streets.

// ------------------------------------------------------------------ tiers ---

/// How important an event is on the map. The bigger the tier, the bigger the
/// pin and the further out it still shows.
enum PinTier {
  /// Official clubs (the paid tier), approved organizers and official events.
  major,

  /// Partner (vendor) events.
  partner,

  /// TT sessions, underground club meets and personal meets.
  minor,
}

/// Which tier an event's pin is. A TT session is always small, whoever hosts
/// it: it is a casual hangout, not a planned event.
PinTier pinTierOf(Event e) {
  if (e.type == EventType.tt || e.isInstant) return PinTier.minor;
  if (e.isOfficialClubEvent || e.hostIsOrganizer || e.type == EventType.official) return PinTier.major;
  if (e.vendorId != null) return PinTier.partner;
  return PinTier.minor;
}

/// Size and zoom rules for one tier.
class TierRule {
  const TierRule({required this.side, required this.minZoom, required this.labelZoom, required this.groupPx});

  /// The round photo head, ring included, in logical px.
  final double side;

  /// Below this zoom the pin is not drawn at all.
  final double minZoom;

  /// From this zoom the event's name shows under the pin.
  final double labelZoom;

  /// Two pins of this tier closer than this on screen merge into a count bubble.
  final double groupPx;
}

/// Every event shows at every zoom (owner, 2026-10-06: meets must stay
/// findable however far out); crowded ones fold into count bubbles. Tier 1:
/// 56 px, named from zoom 11 (a city). Tier 2: 44 px, named from 13.5.
/// Tier 3: 32 px, named at street zoom (14.5) like every other small pin.
const kTierRules = {
  PinTier.major: TierRule(side: 56, minZoom: 0, labelZoom: 11, groupPx: 46),
  PinTier.partner: TierRule(side: 44, minZoom: 0, labelZoom: 13.5, groupPx: 38),
  PinTier.minor: TierRule(side: 32, minZoom: 0, labelZoom: 14.5, groupPx: 32),
};

TierRule tierRule(PinTier t) => kTierRules[t]!;

/// Whether an event pin of [tier] is drawn at [zoom].
bool tierVisibleAt(PinTier tier, double zoom) => zoom >= tierRule(tier).minZoom;

/// Whether an event pin of [tier] carries its name at [zoom].
bool tierLabelAt(PinTier tier, double zoom) => zoom >= tierRule(tier).labelZoom;

/// Every zoom at which something about the event pins changes. The map
/// redraws when the zoom crosses one of them.
final List<double> kTierZoomSteps = {
  for (final r in kTierRules.values) ...[if (r.minZoom > 0) r.minZoom, r.labelZoom],
}.toList()
  ..sort();

/// How many of [kTierZoomSteps] lie at or below [zoom]: two zooms with the
/// same band show the same event pins.
int tierBandAt(double zoom) => kTierZoomSteps.where((z) => zoom >= z).length;

// -------------------------------------------------------------- pin art ---

/// What an event's pin shows. [url] (a cover photo or a club / partner
/// logo) is drawn once it has downloaded; [asset] (bundled) is drawn at once
/// while it does, and for good when there is no [url] or it fails.
class EventPinArt {
  const EventPinArt({this.url, required this.asset, this.assetIsCrest = false});
  final String? url;
  final String asset;

  /// [asset] is a club crest: an emblem fitted on white, not a photo to crop.
  final bool assetIsCrest;
}

/// The event's cover; else, for a club's event, the club's logo (its crest
/// when it has none); else the partner's logo; else the bundled cover for
/// its type (official / TT / meet / convoy / track day / charity). While a
/// photo downloads, a club event shows its crest and any other its type cover.
EventPinArt eventPinArt(Event e) {
  String? clean(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
  final club = e.clubId;
  final stand = club != null ? crestAsset(club) : e.defaultCover;
  final crest = club != null;
  final cover = clean(e.coverUrl);
  if (cover != null) return EventPinArt(url: cover, asset: stand, assetIsCrest: crest);
  if (club != null) return EventPinArt(url: clean(e.clubAvatarUrl), asset: stand, assetIsCrest: true);
  final logo = clean(e.vendorLogoUrl);
  return EventPinArt(url: logo, asset: stand);
}

// ------------------------------------------------------------ events tab ---

/// Who hosts an event, for the Events tab's first chip row. Every event is
/// exactly one of these.
enum EventHost { official, partner, club, tt, personal }

EventHost eventHostOf(Event e) {
  if (e.type == EventType.tt || e.isInstant) return EventHost.tt;
  return switch (pinTierOf(e)) {
    PinTier.major => EventHost.official,
    PinTier.partner => EventHost.partner,
    PinTier.minor => e.clubId != null ? EventHost.club : EventHost.personal,
  };
}

/// The host chips (personal meets only show under "All").
enum HostChip {
  official('Official'),
  partners('Partners'),
  clubs('Clubs'),
  tt('TT sessions');

  const HostChip(this.label);
  final String label;

  bool matches(Event e) => switch (this) {
        HostChip.official => eventHostOf(e) == EventHost.official,
        HostChip.partners => eventHostOf(e) == EventHost.partner,
        HostChip.clubs => eventHostOf(e) == EventHost.club,
        HostChip.tt => eventHostOf(e) == EventHost.tt,
      };
}

/// The type chips. Charity and official events count as meets; TT sessions
/// have their own host chip and match none of these.
enum TypeChip {
  trackday('Track day'),
  convoy('Convoy'),
  meet('Meet');

  const TypeChip(this.label);
  final String label;

  bool matches(Event e) {
    if (e.type == EventType.tt || e.isInstant) return false;
    return switch (this) {
      TypeChip.trackday => e.type == EventType.trackday,
      TypeChip.convoy => e.type == EventType.convoy,
      TypeChip.meet => e.type == EventType.meet || e.type == EventType.charity || e.type == EventType.official,
    };
  }
}

/// The time chips. "This week" covers today too; a meet under way counts as today.
enum WhenChip {
  today('Today'),
  week('This week'),
  later('Later');

  const WhenChip(this.label);
  final String label;

  bool matches(Event e, DateTime now) {
    final midnight = DateTime(now.year, now.month, now.day);
    final tomorrow = midnight.add(const Duration(days: 1));
    final weekEnd = midnight.add(const Duration(days: 7));
    return switch (this) {
      WhenChip.today => e.startsAt.isBefore(tomorrow),
      WhenChip.week => e.startsAt.isBefore(weekEnd),
      WhenChip.later => !e.startsAt.isBefore(weekEnd),
    };
  }
}

/// The Events tab's chips. Inside a row the picked chips add up (Clubs + TT
/// = either); across rows they narrow (Clubs and This week). An empty row
/// is "All".
class EventFilter {
  const EventFilter({this.hosts = const {}, this.types = const {}, this.when = const {WhenChip.week}});

  final Set<HostChip> hosts;
  final Set<TypeChip> types;
  final Set<WhenChip> when;

  /// All hosts, all types, this week.
  static const initial = EventFilter();

  bool get isInitial => hosts.isEmpty && types.isEmpty && when.length == 1 && when.contains(WhenChip.week);

  bool hostOk(Event e) => hosts.isEmpty || hosts.any((c) => c.matches(e));
  bool typeOk(Event e) => types.isEmpty || types.any((c) => c.matches(e));
  bool whenOk(Event e, DateTime now) => when.isEmpty || when.any((c) => c.matches(e, now));

  bool matches(Event e, DateTime now) => hostOk(e) && typeOk(e) && whenOk(e, now);

  EventFilter copyWith({Set<HostChip>? hosts, Set<TypeChip>? types, Set<WhenChip>? when}) =>
      EventFilter(hosts: hosts ?? this.hosts, types: types ?? this.types, when: when ?? this.when);

  EventFilter toggleHost(HostChip c) => copyWith(hosts: _toggle(hosts, c));
  EventFilter toggleType(TypeChip c) => copyWith(types: _toggle(types, c));
  EventFilter toggleWhen(WhenChip c) => copyWith(when: _toggle(when, c));

  /// How many of [events] each chip would show, given the other two rows as
  /// they are (the usual faceted count: picking the chip adds no surprise).
  EventChipCounts counts(Iterable<Event> events, DateTime now) {
    final host = {for (final c in HostChip.values) c: 0};
    final type = {for (final c in TypeChip.values) c: 0};
    final time = {for (final c in WhenChip.values) c: 0};
    var allHosts = 0, allTypes = 0;
    for (final e in events) {
      final h = hostOk(e), t = typeOk(e), w = whenOk(e, now);
      if (t && w) {
        allHosts++;
        for (final c in HostChip.values) {
          if (c.matches(e)) host[c] = host[c]! + 1;
        }
      }
      if (h && w) {
        allTypes++;
        for (final c in TypeChip.values) {
          if (c.matches(e)) type[c] = type[c]! + 1;
        }
      }
      if (h && t) {
        for (final c in WhenChip.values) {
          if (c.matches(e, now)) time[c] = time[c]! + 1;
        }
      }
    }
    return EventChipCounts(allHosts: allHosts, allTypes: allTypes, host: host, type: type, time: time);
  }
}

class EventChipCounts {
  const EventChipCounts({required this.allHosts, required this.allTypes, required this.host, required this.type, required this.time});
  final int allHosts;
  final int allTypes;
  final Map<HostChip, int> host;
  final Map<TypeChip, int> type;
  final Map<WhenChip, int> time;
}

Set<T> _toggle<T>(Set<T> s, T v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};

// ------------------------------------------------------------- spots tab ---

/// The Spots tab's chips. Empty = All. Picked chips add up.
enum SpotChip {
  cafe('Car cafés'),
  mamak('Mamak'),
  workshop('Workshops'),
  detailing('Detailing'),
  partners('Partners'),
  saved('Saved');

  const SpotChip(this.label);
  final String label;

  bool matches(Place p, Set<String> savedIds) => switch (this) {
        SpotChip.cafe => p.kind == 'cafe',
        SpotChip.mamak => p.kind == 'mamak',
        SpotChip.workshop => const {'workshop', 'tyres', 'bodyshop', 'audio', 'accessories'}.contains(p.kind),
        SpotChip.detailing => p.kind == 'detailing' || p.kind == 'carwash',
        SpotChip.partners => p.isPartner,
        SpotChip.saved => savedIds.contains(p.id),
      };
}

bool spotChipsMatch(Place p, Set<SpotChip> chips, Set<String> savedIds) => chips.isEmpty || chips.any((c) => c.matches(p, savedIds));

/// How many of [places] each spot chip keeps, and how many in all.
(int, Map<SpotChip, int>) spotChipCounts(Iterable<Place> places, Set<String> savedIds) {
  final counts = {for (final c in SpotChip.values) c: 0};
  var all = 0;
  for (final p in places) {
    all++;
    for (final c in SpotChip.values) {
      if (c.matches(p, savedIds)) counts[c] = counts[c]! + 1;
    }
  }
  return (all, counts);
}

// --------------------------------------------------------------- now tab ---

/// The Now tab's chips: whom and what to show. Empty = All. Picked chips add up.
enum NowChip {
  friends('Friends'),
  club('Clubmates'),
  nearby('Nearby'),
  events('Events'),
  moments('Moments'),
  spots('Spots');

  const NowChip(this.label);
  final String label;
}

/// Whether a person of this kind shows on the Now tab with [chips] picked.
bool nowShowsPerson(Set<NowChip> chips, {required bool stranger, required bool viaClub}) {
  if (chips.isEmpty) return true;
  if (stranger) return chips.contains(NowChip.nearby);
  return viaClub ? chips.contains(NowChip.club) : chips.contains(NowChip.friends);
}

bool nowShowsEvents(Set<NowChip> chips) => chips.isEmpty || chips.contains(NowChip.events);
bool nowShowsMoments(Set<NowChip> chips) => chips.isEmpty || chips.contains(NowChip.moments);
bool nowShowsSpots(Set<NowChip> chips) => chips.isEmpty || chips.contains(NowChip.spots);

/// The events the Now tab draws: every meet under way ([live], from the live
/// query) and every other meet in view ([inView]) that starts this week,
/// each once, the ones under way first.
List<Event> nowEvents(List<Event> live, List<Event> inView, DateTime now) {
  final seen = <String>{};
  return [
    for (final e in live)
      if (seen.add(e.id)) e,
    for (final e in inView)
      if (WhenChip.week.matches(e, now) && seen.add(e.id)) e,
  ];
}

/// On the Now tab places share the map with people and events: partner
/// shops and my saved spots show at every zoom (crowded ones fold into a
/// count bubble). Other spots too (owner, 2026-10-07: far out they fold into
/// numbered bubbles instead of vanishing).
double nowPlaceMinZoom({required bool partner, required bool saved}) => kNowSpotMinZoom;

/// On Now, ordinary spots (not partners, not saved) come in at district zoom.
const kNowSpotMinZoom = 0.0;

bool nowPlaceVisibleAt(double zoom, {required bool partner, required bool saved}) => zoom >= nowPlaceMinZoom(partner: partner, saved: saved);

/// Below street zoom the Now tab draws places at this share of their
/// Spots-tab size, so the people and events on top stay easy to read.
const kNowPlaceScale = 0.85;

/// Partner shop pins are drawn this much bigger than a spot's teardrop (51 ×
/// 64 px at street zoom against 32 × 40), on every tab: a partner pays to be
/// seen, and its logo has to read on the map.
const kPartnerPinScale = 1.6;

// ------------------------------------------------------------------ tabs ---

/// The map's three tabs. Now is the whole map: people, moments, every meet
/// this week and every spot. Events and Spots are filters of it that keep
/// one kind (plus my own pin, always).
enum MapMode {
  now('Now'),
  events('Events'),
  spots('Spots');

  const MapMode(this.label);
  final String label;
}

/// Which kinds of pin a tab draws, besides my own.
typedef MapLayers = ({bool people, bool moments, bool events, bool places});

/// [MapLayers] for [mode], through the Now chips on the Now tab.
MapLayers mapLayersFor(MapMode mode, Set<NowChip> chips) => switch (mode) {
      MapMode.now => (
          people: chips.isEmpty || chips.contains(NowChip.friends) || chips.contains(NowChip.club) || chips.contains(NowChip.nearby),
          moments: nowShowsMoments(chips),
          events: nowShowsEvents(chips),
          places: nowShowsSpots(chips),
        ),
      MapMode.events => (people: false, moments: false, events: true, places: false),
      MapMode.spots => (people: false, moments: false, events: false, places: true),
    };
