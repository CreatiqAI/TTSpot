import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/features/events/domain/event.dart';
import 'package:car_meet/features/map/application/map_filters.dart';
import 'package:car_meet/features/map/presentation/widgets/car_marker.dart';
import 'package:car_meet/features/map/presentation/widgets/event_pins.dart';
import 'package:car_meet/features/map/presentation/widgets/map_glyphs.dart';
import 'package:car_meet/features/map/presentation/widgets/map_pins.dart';
import 'package:car_meet/features/social/domain/club.dart';

/// The map's rules: which tier an event's pin is (host -> tier), from which
/// zoom each tier shows and is named, what each quick-filter chip keeps,
/// which picture a pin uses, and the friend colours.

final _now = DateTime(2026, 10, 2, 15); // a Friday afternoon

Event _event({
  String id = 'e',
  EventType type = EventType.meet,
  bool instant = false,
  String? clubId,
  String? clubTier,
  String? clubAvatar,
  String? vendorId,
  String? vendorLogo,
  bool organizer = false,
  String? cover,
  DateTime? startsAt,
}) =>
    Event(
      id: id,
      organizerId: 'host',
      title: 'Meet $id',
      type: type,
      isInstant: instant,
      coverUrl: cover,
      startsAt: startsAt ?? _now.add(const Duration(days: 1)),
      venueName: 'Somewhere',
      lat: 3.1,
      lng: 101.6,
      status: EventStatus.active,
      attendeeCount: 0,
      createdAt: _now,
      clubId: clubId,
      clubTier: clubTier,
      clubAvatarUrl: clubAvatar,
      vendorId: vendorId,
      vendorLogoUrl: vendorLogo,
      hostIsOrganizer: organizer,
    );

Place _place(String id, String kind, {String? vendorId}) =>
    Place(id: id, name: id, kind: kind, lat: 3.1, lng: 101.6, createdAt: _now, vendorId: vendorId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tier by host', () {
    test('official clubs, approved organizers and official events are tier 1', () {
      expect(pinTierOf(_event(clubId: 'c', clubTier: 'official')), PinTier.major);
      expect(pinTierOf(_event(organizer: true)), PinTier.major);
      expect(pinTierOf(_event(type: EventType.official)), PinTier.major);
      // An official club's meet with a partner on it stays tier 1.
      expect(pinTierOf(_event(clubId: 'c', clubTier: 'official', vendorId: 'v')), PinTier.major);
    });

    test('partner events are tier 2', () {
      expect(pinTierOf(_event(vendorId: 'v')), PinTier.partner);
      expect(pinTierOf(_event(vendorId: 'v', type: EventType.trackday)), PinTier.partner);
    });

    test('TT sessions, underground clubs and personal meets are tier 3', () {
      expect(pinTierOf(_event(type: EventType.tt)), PinTier.minor);
      expect(pinTierOf(_event(instant: true)), PinTier.minor);
      expect(pinTierOf(_event(clubId: 'c', clubTier: 'underground')), PinTier.minor);
      expect(pinTierOf(_event()), PinTier.minor);
      expect(pinTierOf(_event(type: EventType.convoy)), PinTier.minor);
    });

    test('a TT session is small whoever hosts it', () {
      expect(pinTierOf(_event(type: EventType.tt, organizer: true)), PinTier.minor);
      expect(pinTierOf(_event(instant: true, clubId: 'c', clubTier: 'official')), PinTier.minor);
      expect(pinTierOf(_event(type: EventType.tt, vendorId: 'v')), PinTier.minor);
    });
  });

  group('zoom rules', () {
    test('sizes shrink with the tier', () {
      expect(tierRule(PinTier.major).side, 56);
      expect(tierRule(PinTier.partner).side, 44);
      expect(tierRule(PinTier.minor).side, 32);
    });

    test('tier 1 shows from far out, tier 2 from towns, tier 3 from districts', () {
      expect(tierVisibleAt(PinTier.major, 5.9), isFalse);
      expect(tierVisibleAt(PinTier.major, 6), isTrue);
      expect(tierVisibleAt(PinTier.major, 8), isTrue);
      expect(tierVisibleAt(PinTier.partner, 8), isFalse);
      expect(tierVisibleAt(PinTier.partner, 10.49), isFalse);
      expect(tierVisibleAt(PinTier.partner, 10.5), isTrue);
      expect(tierVisibleAt(PinTier.minor, 12.49), isFalse);
      expect(tierVisibleAt(PinTier.minor, 12.5), isTrue);
      expect(tierVisibleAt(PinTier.minor, 18), isTrue);
    });

    test('at every zoom a bigger tier shows wherever a smaller one does', () {
      for (var z = 4.0; z <= 20; z += 0.25) {
        if (tierVisibleAt(PinTier.minor, z)) expect(tierVisibleAt(PinTier.partner, z), isTrue, reason: 'zoom $z');
        if (tierVisibleAt(PinTier.partner, z)) expect(tierVisibleAt(PinTier.major, z), isTrue, reason: 'zoom $z');
      }
    });

    test('names: tier 1 from a city view, the others closer, never before the pin', () {
      expect(tierLabelAt(PinTier.major, 10.9), isFalse);
      expect(tierLabelAt(PinTier.major, 11), isTrue);
      expect(tierLabelAt(PinTier.partner, 13.4), isFalse);
      expect(tierLabelAt(PinTier.partner, 13.5), isTrue);
      expect(tierLabelAt(PinTier.minor, 14.4), isFalse);
      expect(tierLabelAt(PinTier.minor, 14.5), isTrue);
      for (final t in PinTier.values) {
        expect(tierRule(t).labelZoom, greaterThanOrEqualTo(tierRule(t).minZoom));
      }
    });

    test('the zoom band changes exactly where a rule does (the map redraws there)', () {
      expect(tierBandAt(5), 0);
      expect(tierBandAt(12.45), tierBandAt(12.3));
      expect(tierBandAt(12.5), tierBandAt(12.45) + 1);
      expect(tierBandAt(10.5), tierBandAt(10.49) + 1);
      expect(tierBandAt(20), kTierZoomSteps.length);
      for (final z in kTierZoomSteps) {
        expect(tierBandAt(z), greaterThan(tierBandAt(z - 0.01)), reason: 'step $z');
      }
    });
  });

  group('Events chips', () {
    final official = _event(id: 'off', clubId: 'c', clubTier: 'official', startsAt: _now.add(const Duration(hours: 3)));
    final partner = _event(id: 'par', vendorId: 'v', type: EventType.trackday, startsAt: _now.add(const Duration(days: 2)));
    final club = _event(id: 'club', clubId: 'u', type: EventType.convoy, startsAt: _now.add(const Duration(days: 10)));
    final tt = _event(id: 'tt', type: EventType.tt, startsAt: _now.subtract(const Duration(hours: 1)));
    final personal = _event(id: 'me', startsAt: _now.add(const Duration(days: 5)));
    final all = [official, partner, club, tt, personal];

    test('every event has exactly one host', () {
      expect(eventHostOf(official), EventHost.official);
      expect(eventHostOf(partner), EventHost.partner);
      expect(eventHostOf(club), EventHost.club);
      expect(eventHostOf(tt), EventHost.tt);
      expect(eventHostOf(personal), EventHost.personal);
      for (final e in all) {
        expect(HostChip.values.where((c) => c.matches(e)).length, lessThanOrEqualTo(1));
      }
    });

    test('type chips: meets include charity and official, TT matches none', () {
      expect(TypeChip.meet.matches(_event(type: EventType.charity)), isTrue);
      expect(TypeChip.meet.matches(_event(type: EventType.official)), isTrue);
      expect(TypeChip.trackday.matches(partner), isTrue);
      expect(TypeChip.convoy.matches(club), isTrue);
      expect(TypeChip.values.any((c) => c.matches(tt)), isFalse);
    });

    test('time chips: a meet under way is today, this week covers today', () {
      expect(WhenChip.today.matches(tt, _now), isTrue);
      expect(WhenChip.today.matches(official, _now), isTrue);
      expect(WhenChip.week.matches(official, _now), isTrue);
      expect(WhenChip.today.matches(partner, _now), isFalse);
      expect(WhenChip.week.matches(partner, _now), isTrue);
      expect(WhenChip.week.matches(club, _now), isFalse);
      expect(WhenChip.later.matches(club, _now), isTrue);
      expect(WhenChip.later.matches(personal, _now), isFalse);
    });

    test('defaults: all hosts, all types, this week', () {
      const f = EventFilter.initial;
      expect(f.isInitial, isTrue);
      expect([for (final e in all) if (f.matches(e, _now)) e.id], ['off', 'par', 'tt', 'me']);
    });

    test('picked chips add up inside a row and narrow across rows', () {
      final f = EventFilter.initial.toggleHost(HostChip.official).toggleHost(HostChip.tt);
      expect(f.isInitial, isFalse);
      expect([for (final e in all) if (f.matches(e, _now)) e.id], ['off', 'tt']);
      final g = f.toggleType(TypeChip.meet);
      expect([for (final e in all) if (g.matches(e, _now)) e.id], ['off']);
      // Un-picking the last time chip means every time.
      final h = EventFilter.initial.toggleWhen(WhenChip.week);
      expect(h.when, isEmpty);
      expect([for (final e in all) if (h.matches(e, _now)) e], hasLength(all.length));
      final later = h.toggleWhen(WhenChip.later);
      expect([for (final e in all) if (later.matches(e, _now)) e.id], ['club']);
    });

    test('chip counts are faceted: each row counts under the other rows', () {
      final f = EventFilter.initial.toggleHost(HostChip.partners);
      final c = f.counts(all, _now);
      // Hosts are counted within this week, whatever host is picked.
      expect(c.allHosts, 4);
      expect(c.host[HostChip.official], 1);
      expect(c.host[HostChip.partners], 1);
      expect(c.host[HostChip.clubs], 0); // the club convoy is in 10 days
      expect(c.host[HostChip.tt], 1);
      // Types and times only count partner events.
      expect(c.allTypes, 1);
      expect(c.type[TypeChip.trackday], 1);
      expect(c.type[TypeChip.meet], 0);
      expect(c.time[WhenChip.week], 1);
      expect(c.time[WhenChip.later], 0);
    });
  });

  group('Spots chips', () {
    final places = [
      _place('cafe', 'cafe'),
      _place('mamak', 'mamak'),
      _place('tyres', 'tyres'),
      _place('wash', 'carwash'),
      _place('shop', 'workshop', vendorId: 'v'),
      _place('park', 'carpark'),
    ];
    const saved = {'park'};

    test('All keeps everything; picked chips add up', () {
      expect(places.where((p) => spotChipsMatch(p, const {}, saved)), hasLength(places.length));
      expect([for (final p in places) if (spotChipsMatch(p, {SpotChip.cafe, SpotChip.mamak}, saved)) p.id], ['cafe', 'mamak']);
      expect([for (final p in places) if (spotChipsMatch(p, {SpotChip.workshop}, saved)) p.id], ['tyres', 'shop']);
      expect([for (final p in places) if (spotChipsMatch(p, {SpotChip.detailing}, saved)) p.id], ['wash']);
      expect([for (final p in places) if (spotChipsMatch(p, {SpotChip.partners}, saved)) p.id], ['shop']);
      expect([for (final p in places) if (spotChipsMatch(p, {SpotChip.saved}, saved)) p.id], ['park']);
    });

    test('counts', () {
      final (all, counts) = spotChipCounts(places, saved);
      expect(all, 6);
      expect(counts[SpotChip.workshop], 2);
      expect(counts[SpotChip.saved], 1);
    });
  });

  group('Now chips', () {
    test('All shows everyone; picked chips choose who', () {
      expect(nowShowsPerson(const {}, stranger: true, viaClub: false), isTrue);
      expect(nowShowsPerson({NowChip.friends}, stranger: false, viaClub: false), isTrue);
      expect(nowShowsPerson({NowChip.friends}, stranger: false, viaClub: true), isFalse);
      expect(nowShowsPerson({NowChip.club}, stranger: false, viaClub: true), isTrue);
      expect(nowShowsPerson({NowChip.friends}, stranger: true, viaClub: false), isFalse);
      expect(nowShowsPerson({NowChip.nearby}, stranger: true, viaClub: false), isTrue);
      expect(nowShowsMeets(const {}), isTrue);
      expect(nowShowsMeets({NowChip.friends}), isFalse);
      expect(nowShowsMoments({NowChip.moments}), isTrue);
    });
  });

  group('pin picture', () {
    test('cover first, else the club logo or crest, else the partner logo, else the type cover', () {
      final withCover = eventPinArt(_event(cover: 'https://x/cover.jpg', clubId: 'c'));
      expect(withCover.url, 'https://x/cover.jpg');
      expect(withCover.asset, startsWith('assets/crests/'));

      final clubLogo = eventPinArt(_event(clubId: 'c', clubAvatar: 'https://x/logo.png'));
      expect(clubLogo.url, 'https://x/logo.png');
      expect(clubLogo.assetIsCrest, isTrue);

      final crest = eventPinArt(_event(clubId: 'c'));
      expect(crest.url, isNull);
      expect(crest.asset, startsWith('assets/crests/'));
      expect(crest.assetIsCrest, isTrue);

      final partner = eventPinArt(_event(vendorId: 'v', vendorLogo: 'https://x/shop.png', type: EventType.trackday));
      expect(partner.url, 'https://x/shop.png');
      expect(partner.asset, 'assets/covers/trackday.jpg');

      expect(eventPinArt(_event(type: EventType.convoy)).asset, 'assets/covers/convoy.jpg');
      expect(eventPinArt(_event(instant: true)).asset, 'assets/covers/tt.jpg');
      expect(eventPinArt(_event(clubId: 'c', clubTier: 'official', cover: '  ')).url, isNull);
    });
  });

  group('friend colours', () {
    test('twelve distinct colours, the original seven unchanged', () {
      expect(kTagColors, hasLength(12));
      expect(kTagColors.values.map((c) => c.toARGB32()).toSet(), hasLength(12));
      const original = {
        'red': 0xFFE00008,
        'orange': 0xFFFF7A1A,
        'yellow': 0xFFF5C518,
        'green': 0xFF1DA750,
        'blue': 0xFF2B7CFF,
        'purple': 0xFFA855F7,
        'pink': 0xFFEC4899,
      };
      original.forEach((k, v) => expect(kTagColors[k]?.toARGB32(), v, reason: k));
      expect(kTagColorLabels.keys.toSet(), kTagColors.keys.toSet());
    });

    test('a tag wins over the relationship colour; strangers stay grey', () {
      expect(personColor(tag: 'teal'), kTagColors['teal']);
      expect(personColor(tag: 'teal', viaClub: true), kTagColors['teal']);
      expect(personColor(), kRelationFriend);
      expect(personColor(viaClub: true), kRelationClub);
      expect(personColor(tag: 'unknown'), kRelationFriend);
      expect(personColor(tag: 'teal', stranger: true), kRelationStranger);
    });
  });

  group('event pin bitmap', () {
    test('each tier draws at its size, with the tip at the anchor, without waiting on the network', () async {
      {
        final pins = MapPinFactory(devicePixelRatio: 2);
        final factory = EventPinFactory(devicePixelRatio: 2, pins: pins);
        for (final (event, tier) in [
          (_event(clubId: 'c', clubTier: 'official'), PinTier.major),
          (_event(vendorId: 'v'), PinTier.partner),
          (_event(type: EventType.tt), PinTier.minor),
        ]) {
          final pin = await factory.event(event, tier: tier);
          final side = tierRule(tier).side;
          // The head plus a little room for the shadow and the badge.
          expect(pin.size.width, inInclusiveRange(side, side + 10));
          expect(pin.size.height, inInclusiveRange(side + eventPinTail(side), side + eventPinTail(side) + 12));
          // Anchored at the pointer's tip, low in the bitmap, centred.
          expect(pin.anchor.dx, 0.5);
          expect(pin.anchor.dy, greaterThan(0.85));
          final codec = await ui.instantiateImageCodec(pin.bytes);
          final img = (await codec.getNextFrame()).image;
          expect(img.width, (pin.size.width * 2).ceil());
        }
        // Same event, same look: the cached bitmap comes back.
        final a = await factory.event(_event(vendorId: 'v'), tier: PinTier.partner);
        final b = await factory.event(_event(vendorId: 'v'), tier: PinTier.partner);
        expect(identical(a, b), isTrue);
        // A name under the pin makes it taller, a LIVE tab too.
        final named = await factory.event(_event(vendorId: 'v'), tier: PinTier.partner, label: 'Track day at Sepang');
        expect(named.size.height, greaterThan(a.size.height));
        final live = await factory.event(_event(vendorId: 'v'), tier: PinTier.partner, live: true);
        expect(live.size.height, greaterThan(a.size.height));
        factory.dispose();
        pins.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('the first request for a bitmap or a picture completes (no wait on itself)', () async {
      // Each cache shares in-flight work through a map entry removed in
      // whenComplete; an arrow callback returned that same future and the
      // first caller waited forever.
      const limit = Duration(seconds: 10);
      final glyphs = GlyphMarkerFactory(devicePixelRatio: 2);
      final first = glyphs.teardrop(color: kEventRed, glyph: AppIcons.flagFill);
      final second = glyphs.teardrop(color: kEventRed, glyph: AppIcons.flagFill);
      expect(await first.timeout(limit), isA<MapPin>());
      expect(await second.timeout(limit), isA<MapPin>());
      final pins = MapPinFactory(devicePixelRatio: 2);
      expect(await pins.image('assets/crests/crest_1.png', targetWidth: 64).timeout(limit), isNotNull);
      expect(pins.isLoaded('assets/crests/crest_1.png'), isTrue);
      pins.dispose();
      glyphs.dispose();
    });

    test('ring colours follow the tier', () {
      expect(tierRingColor(PinTier.major), isNot(tierRingColor(PinTier.partner)));
      expect(tierRingColor(PinTier.partner), isNot(tierRingColor(PinTier.minor)));
      expect(tierRingColor(PinTier.minor), const Color(0xFFE00008));
    });
  });
}
