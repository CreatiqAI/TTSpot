import 'package:car_meet/core/guide/guide.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/guides/map_guides.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:car_meet/features/vendors/domain/vendor.dart';
import 'package:car_meet/features/vendors/presentation/widgets/partner_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every variant of the five guides (the steps follow what the page shows).
List<Guide> _all() {
  final event = EventGuideKeys();
  final club = ClubGuideKeys();
  final partner = PartnerGuideKeys();
  return [
    mapGuide(MapGuideKeys()),
    for (final attending in [false, true])
      for (final full in [false, true])
        for (final live in [false, true])
          for (final onMyWay in [false, true])
            for (final chat in [false, true]) eventGuide(event, attending: attending, full: full, live: live, onMyWay: onMyWay, chat: chat),
    spotGuide(SpotGuideKeys()),
    for (final member in [false, true])
      for (final official in [false, true])
        for (final invited in [false, true]) clubGuide(club, member: member, official: official, invited: invited),
    for (final hasLocation in [false, true])
      for (final hasSpot in [false, true]) partnerGuide(partner, hasLocation: hasLocation, hasSpot: hasSpot),
  ];
}

int _words(String s) => s.trim().split(RegExp(r'\s+')).length;

void main() {
  test('each guide uses its own id', () {
    expect(mapGuide(MapGuideKeys()).id, GuideIds.map);
    expect(eventGuide(EventGuideKeys(), attending: false).id, GuideIds.event);
    expect(spotGuide(SpotGuideKeys()).id, GuideIds.spot);
    expect(clubGuide(ClubGuideKeys(), member: false, official: false).id, GuideIds.club);
    expect(partnerGuide(PartnerGuideKeys(), hasLocation: true, hasSpot: true).id, GuideIds.partner);
    for (final g in _all()) {
      expect(GuideIds.all, contains(g.id));
    }
  });

  test('copy is short: titles 2-5 words and <= 40 chars, bodies <= 18 words and <= 110 chars', () {
    for (final g in _all()) {
      expect(g.steps, isNotEmpty, reason: g.id);
      for (final s in g.steps) {
        expect(s.title.length, lessThanOrEqualTo(40), reason: '${g.id}: ${s.title}');
        expect(_words(s.title), inInclusiveRange(2, 5), reason: '${g.id}: ${s.title}');
        expect(s.body.length, lessThanOrEqualTo(110), reason: '${g.id}: ${s.body}');
        expect(_words(s.body), lessThanOrEqualTo(18), reason: '${g.id}: ${s.body}');
      }
    }
  });

  test('map: switch, chips, buttons, nearby bar, then tap any pin', () {
    final k = MapGuideKeys();
    final g = mapGuide(k);
    expect(g.steps.map((s) => s.target), [k.modeSwitch, k.chips, k.buttons, k.nearbyBar, null]);
    expect(g.steps.first.body, contains('Spots'));
    expect(g.steps.last.body, startsWith('A TT, a meet'));
  });

  test('event: only the steps whose widgets show', () {
    final k = EventGuideKeys();
    // Not going yet, meet still to come: Join, then the host's QR line.
    final ahead = eventGuide(k, attending: false);
    expect(ahead.steps.map((s) => s.target), [k.rsvp, null]);
    expect(ahead.steps.last.body, contains('QR'));
    expect(ahead.steps.last.body, contains('+10'));
    // Going, live, inside the on-my-way window: check in, on my way, chat (no 'leave' tip).
    final live = eventGuide(k, attending: true, live: true, onMyWay: true, chat: true);
    expect(live.steps.map((s) => s.target), [k.checkIn, k.onMyWay, k.chat]);
    // Full and not going: no Join step.
    expect(eventGuide(k, attending: false, full: true).steps.map((s) => s.target), isNot(contains(k.rsvp)));
    for (final g in _all().where((g) => g.id == GuideIds.event)) {
      expect(g.steps.length, lessThanOrEqualTo(5));
    }
  });

  test('spot: check in (+10 once a week) and moments', () {
    final k = SpotGuideKeys();
    final g = spotGuide(k);
    expect(g.steps.map((s) => s.target), [k.checkIn, k.moment]);
    expect(g.steps.first.body, contains('+10'));
    expect(g.steps.first.body, contains('once a week'));
  });

  test('club: join or member, chat for members, the tag when official', () {
    final k = ClubGuideKeys();
    expect(clubGuide(k, member: true, official: true).steps.map((s) => s.target), [k.join, k.chat, k.tagSwitch]);
    expect(clubGuide(k, member: true, official: false).steps.map((s) => s.target), [k.join, k.chat]);
    expect(clubGuide(k, member: false, official: true).steps.map((s) => s.target), [k.join, k.officialChip]);
    expect(clubGuide(k, member: false, official: true, invited: true).steps.first.target, k.invite);
    expect(clubGuide(k, member: false, official: false).steps.length, 2);
  });

  test('partner: follow, vouchers / products, then directions or check in', () {
    final k = PartnerGuideKeys();
    expect(partnerGuide(k, hasLocation: true, hasSpot: true).steps.map((s) => s.target), [k.follow, k.tabs, k.directions]);
    expect(partnerGuide(k, hasLocation: true, hasSpot: true).steps.last.body, contains('Check in'));
    expect(partnerGuide(k, hasLocation: false, hasSpot: true).steps.map((s) => s.target), [k.follow, k.tabs, null]);
    expect(partnerGuide(k, hasLocation: false, hasSpot: false).steps.length, 2);
  });

  test('no guide runs past five steps or under two in its usual shape', () {
    for (final g in _all()) {
      expect(g.steps.length, lessThanOrEqualTo(5), reason: g.id);
    }
    expect(mapGuide(MapGuideKeys()).steps.length, inInclusiveRange(2, 5));
    expect(spotGuide(SpotGuideKeys()).steps.length, inInclusiveRange(2, 5));
  });

  testWidgets('GuideKeyScope keeps one set of keys across rebuilds', (t) async {
    final seen = <ClubGuideKeys>{};
    final tick = ValueNotifier(0);
    await t.pumpWidget(ValueListenableBuilder<int>(
      valueListenable: tick,
      builder: (_, _, _) => GuideKeyScope<ClubGuideKeys>(
        create: ClubGuideKeys.new,
        builder: (_, keys) {
          seen.add(keys);
          return const SizedBox();
        },
      ),
    ));
    tick.value++;
    await t.pump();
    expect(seen.length, 1);
  });

  testWidgets('partner page attaches the guide keys', (t) async {
    final k = PartnerGuideKeys();
    t.view.physicalSize = const Size(1080, 2220);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.current,
        home: Scaffold(
          body: PartnerPageView(
            vendor: const PublicVendor(id: 'v-1', name: 'Garage 21', type: 'workshop', placeId: 'pl-1', lat: 3.03, lng: 101.62),
            products: const <Product>[],
            vouchers: const <Voucher>[],
            posts: const <FeedPost>[],
            events: const [],
            onMessage: () {},
            following: false,
            onFollow: () {},
            guideKeys: k,
          ),
        ),
      ),
    ));
    await t.pump();
    expect(k.follow.currentContext, isNotNull);
    expect(k.tabs.currentContext, isNotNull);
    expect(k.directions.currentContext, isNotNull);
  });
}
