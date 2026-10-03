import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/friends/domain/friend.dart';
import 'package:car_meet/features/friends/domain/presence.dart';
import 'package:car_meet/features/social/presentation/inbox_screen.dart';

/// "On the map now" means a position at most a minute old, in Chats and on
/// the map; anything under a day old still shows on the map as last seen.

final _now = DateTime(2026, 10, 3, 21);

FriendPin _pin({required Duration age, String? place}) => FriendPin(
      user: Profile(id: 'ali', username: 'ali_civic', createdAt: _now),
      lat: 3.1,
      lng: 101.6,
      updatedAt: DateTime.now().subtract(age),
      placeName: place,
    );

void main() {
  group('presence windows', () {
    test('live for one minute', () {
      expect(isLiveAt(_now.subtract(const Duration(seconds: 59)), _now), isTrue);
      expect(isLiveAt(_now.subtract(const Duration(seconds: 60)), _now), isTrue);
      expect(isLiveAt(_now.subtract(const Duration(seconds: 61)), _now), isFalse);
      // The phone's clock a little behind the server's: still live.
      expect(isLiveAt(_now.add(const Duration(seconds: 5)), _now), isTrue);
    });

    test('shown on the map for a day', () {
      expect(isShownAt(_now.subtract(const Duration(seconds: 61)), _now), isTrue);
      expect(isShownAt(_now.subtract(const Duration(hours: 23)), _now), isTrue);
      expect(isShownAt(_now.subtract(const Duration(hours: 24)), _now), isFalse);
      expect(isShownAt(_now.subtract(const Duration(hours: 25)), _now), isFalse);
    });

    test('three states', () {
      expect(presenceAt(_now.subtract(const Duration(seconds: 59)), _now), Presence.live);
      expect(presenceAt(_now.subtract(const Duration(seconds: 61)), _now), Presence.seen);
      expect(presenceAt(_now.subtract(const Duration(hours: 23)), _now), Presence.seen);
      expect(presenceAt(_now.subtract(const Duration(hours: 25)), _now), Presence.gone);
    });

    test('the heartbeat keeps a still phone live', () {
      expect(kPresenceHeartbeat * 2, lessThanOrEqualTo(kLiveWindow));
    });
  });

  group('labels', () {
    test('"now" while live, then how long ago', () {
      expect(presenceLabel(_now.subtract(const Duration(seconds: 59)), _now), 'now');
      expect(presenceLabel(_now.subtract(const Duration(seconds: 61)), _now), '1 min ago');
      expect(presenceLabel(_now.subtract(const Duration(minutes: 5)), _now), '5 min ago');
      expect(presenceLabel(_now.subtract(const Duration(minutes: 59)), _now), '59 min ago');
      expect(presenceLabel(_now.subtract(const Duration(hours: 3, minutes: 20)), _now), '3 h ago');
    });
  });

  group('when the next live pin turns last seen', () {
    test('the soonest live one, a second past its minute', () {
      final left = untilLiveEnds([
        _now.subtract(const Duration(seconds: 10)),
        _now.subtract(const Duration(seconds: 40)),
        _now.subtract(const Duration(minutes: 5)), // already last seen
      ], _now);
      expect(left, const Duration(seconds: 21));
    });

    test('none live, nothing to wait for', () {
      expect(untilLiveEnds([_now.subtract(const Duration(minutes: 2))], _now), isNull);
      expect(untilLiveEnds(const [], _now), isNull);
    });
  });

  group('FriendPin', () {
    test('isLive follows the one-minute rule', () {
      expect(_pin(age: const Duration(seconds: 20)).isLive, isTrue);
      expect(_pin(age: const Duration(minutes: 3)).isLive, isFalse);
    });
  });

  group('Chats line under a friend', () {
    Future<void> pump(WidgetTester tester, FriendPin? pin) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: FriendMapLine(pin: pin, username: 'ali_civic')))),
        );

    Color colourOf(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style!.color!;

    testWidgets('live: "On the map now" in green', (tester) async {
      await pump(tester, _pin(age: const Duration(seconds: 20)));
      expect(find.text('On the map now'), findsOneWidget);
      expect(colourOf(tester, 'On the map now'), AppColors.success);
    });

    testWidgets('live at a place: "On the map · place"', (tester) async {
      await pump(tester, _pin(age: const Duration(seconds: 20), place: 'Wheels Cafe'));
      expect(find.text('On the map · Wheels Cafe'), findsOneWidget);
    });

    testWidgets('over a minute old: no live wording, just when they were seen', (tester) async {
      await pump(tester, _pin(age: const Duration(minutes: 5, seconds: 10), place: 'Wheels Cafe'));
      expect(find.textContaining('On the map'), findsNothing);
      expect(find.text('Seen 5 min ago'), findsOneWidget);
      expect(colourOf(tester, 'Seen 5 min ago'), AppColors.textSecondary);
    });

    testWidgets('not on the map: their handle', (tester) async {
      await pump(tester, null);
      expect(find.text('@ali_civic'), findsOneWidget);
    });
  });
}
