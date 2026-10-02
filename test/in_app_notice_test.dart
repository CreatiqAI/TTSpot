import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/push/in_app_notice.dart';
import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/core/theme/app_theme.dart';

InAppNotice _chat(String conv, {String title = 'Aiman', String body = 'TEST otw'}) =>
    InAppNotice(kind: 'chat', title: title, body: body, route: '/chat/$conv', conversationId: conv, seed: 'u1');

void main() {
  group('InAppNotice.fromPush', () {
    test('a chat message (Android data-only push)', () {
      final n = InAppNotice.fromPush({
        'kind': 'chat',
        'title': 'Boss',
        'body': 'TEST hello',
        'route': '/chat/c1',
        'conversation_id': 'c1',
        'sender_id': 'u1',
        'avatar': 'https://x/a.png',
        'group': '0',
        'msg_id': 'm:1',
      })!;
      expect(n.isChat, isTrue);
      expect(n.title, 'Boss');
      expect(n.body, 'TEST hello');
      expect(n.conversationId, 'c1');
      expect(n.route, '/chat/c1');
      expect(n.avatarUrl, 'https://x/a.png');
      expect(n.seed, 'u1');
      expect(n.id, 'm:1');
      expect(n.badge, isNull); // a one-to-one chat: just the face
    });

    test('falls back to the notification block (iOS, older server) and the chat id in the route', () {
      final n = InAppNotice.fromPush({'route': '/chat/c9'}, title: 'Aiman', body: 'hi', messageId: 'fcm-1')!;
      expect(n.conversationId, 'c9');
      expect(n.kind, 'chat');
      expect(n.id, 'fcm-1');
    });

    test('social notices get an icon badge; a meet chat gets the group badge', () {
      expect(InAppNotice.fromPush({'kind': 'post_like', 'title': 'Aiman', 'body': 'liked your post.', 'route': '/post/p1'})!.badge, AppIcons.heartFill);
      expect(InAppNotice.fromPush({'kind': 'friend_request', 'title': 'Aiman', 'body': 'wants to be friends.'})!.badge, AppIcons.userPlus);
      expect(InAppNotice.fromPush({'kind': 'chat', 'group': '1', 'title': 'TiTi Night', 'body': 'Aiman: TEST', 'conversation_id': 'c2'})!.badge, AppIcons.usersThree);
    });

    test('nothing to show without a title; routes must be app paths', () {
      expect(InAppNotice.fromPush({'body': 'x'}), isNull);
      expect(InAppNotice.fromPush({'title': 'A', 'route': 'https://evil.example'})!.route, isNull);
    });
  });

  group('shouldShowInAppNotice', () {
    test('not for the chat I am looking at', () {
      expect(shouldShowInAppNotice(_chat('c1'), viewingChatId: 'c1', mutedChatIds: const {}), isFalse);
    });
    test('not for a chat I muted', () {
      expect(shouldShowInAppNotice(_chat('c1'), viewingChatId: null, mutedChatIds: {'c1'}), isFalse);
    });
    test('yes for another chat, even while in a chat', () {
      expect(shouldShowInAppNotice(_chat('c2'), viewingChatId: 'c1', mutedChatIds: {'c3'}), isTrue);
    });
    test('social notices show unless I am already on that page', () {
      const like = InAppNotice(kind: 'post_like', title: 'Aiman', body: 'liked your post.', route: '/post/p1');
      expect(shouldShowInAppNotice(like, viewingChatId: 'c1', mutedChatIds: {'c1'}, currentPath: '/map'), isTrue);
      expect(shouldShowInAppNotice(like, viewingChatId: null, mutedChatIds: const {}, currentPath: '/post/p1'), isFalse);
    });
  });

  group('OpenChats', () {
    setUp(OpenChats.reset);
    test('the top chat counts only while the router shows it', () {
      OpenChats.enter('c1');
      expect(OpenChats.viewing('/chat/c1'), 'c1');
      expect(OpenChats.viewing('/chat/c1/info'), isNull); // chat info pushed on top
      expect(OpenChats.viewing('/profile/u1'), isNull);
      OpenChats.enter('c2'); // a second chat opened from the first
      expect(OpenChats.viewing('/chat/c2'), 'c2');
      OpenChats.leave('c2');
      expect(OpenChats.viewing('/chat/c1'), 'c1');
      OpenChats.leave('c1');
      expect(OpenChats.viewing('/chat/c1'), isNull);
    });
  });

  group('banner', () {
    tearDown(() {
      AppColors.dark = false;
      InAppNotices.hide();
    });

    Future<void> pumpHost(WidgetTester tester, {double scale = 1.0, double width = 360}) async {
      tester.view.physicalSize = Size(width * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), padding: const EdgeInsets.only(top: 24)),
          child: Stack(children: [Positioned.fill(child: child!), const InAppNoticeHost()]),
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ));
    }

    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('long name and preview fit (${dark ? 'dark' : 'light'}, font ×$scale, 320 wide)', (tester) async {
          AppColors.dark = dark;
          await pumpHost(tester, scale: scale, width: 320);
          InAppNotices.show(const InAppNotice(
            kind: 'chat',
            group: true,
            title: 'A very long meet name that goes on and on past the edge',
            body: 'Aiman Hakimi bin Abdullah: TEST this preview is much too long for one line on a small phone',
            seed: 'u1',
            conversationId: 'c1',
          ));
          await tester.pumpAndSettle(const Duration(milliseconds: 100));
          expect(find.byType(InAppNoticeCard), findsOneWidget);
          expect(tester.takeException(), isNull);
          InAppNotices.hide();
          await tester.pumpAndSettle();
        });
      }
    }

    testWidgets('slides in, hides itself after 4 s', (tester) async {
      await pumpHost(tester);
      InAppNotices.show(_chat('c1'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('Aiman'), findsOneWidget);
      expect(find.text('TEST otw'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.byType(InAppNoticeCard), findsNothing);
    });

    testWidgets('tap opens it; swipe up dismisses without opening', (tester) async {
      await pumpHost(tester);
      var opened = 0;
      InAppNotices.show(_chat('c1'), onTap: () => opened++);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      await tester.tap(find.byType(InAppNoticeCard));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.byType(InAppNoticeCard), findsNothing);

      InAppNotices.show(_chat('c2', title: 'Keith'), onTap: () => opened++);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      await tester.drag(find.byType(InAppNoticeCard), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.byType(InAppNoticeCard), findsNothing);
    });
  });
}
