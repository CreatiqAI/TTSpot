import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/router/app_router.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/settings/application/settings_providers.dart';
import 'package:car_meet/features/settings/presentation/settings_screen.dart' show PushKind;
import 'package:car_meet/features/settings/presentation/titi_tips_switch.dart';
import 'package:car_meet/features/social/domain/notification.dart';
import 'package:car_meet/features/social/presentation/activity_screen.dart' show ActivityRow, activityText;
import 'package:car_meet/features/titi/application/titi_controller.dart';
import 'package:car_meet/features/titi/domain/titi_message.dart';

/// Settings without Supabase: starts from [initial], patches apply locally.
class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this.initial);
  final Map<String, dynamic> initial;
  @override
  AppSettings build() => AppSettings(initial);
}

class _FakeActions extends SettingsActions {
  _FakeActions(this.ref) : super(ref);
  final Ref ref;
  final saved = <Map<String, dynamic>>[];
  @override
  Future<void> patch(Map<String, dynamic> patch) async {
    saved.add(patch);
    ref.read(settingsProvider.notifier).apply(patch);
  }
}

void main() {
  group('TiTi tips setting', () {
    test('on by default, off only when saved off', () {
      expect(const AppSettings({}).titiTips, isTrue);
      expect(const AppSettings({'titi_tips': true}).titiTips, isTrue);
      expect(const AppSettings({'titi_tips': false}).titiTips, isFalse);
      expect(PushKind.titiTips.key, 'titi_tips');
      expect(PushKind.titiTips.isOn(const AppSettings({'titi_tips': false})), isFalse);
      expect(PushKind.titiTips.isOn(const AppSettings({})), isTrue);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('the switch saves titi_tips and fits at text scale $scale', (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.75;
        addTearDown(tester.view.reset);
        late _FakeActions actions;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsProvider.overrideWith(() => _FakeSettings(const {})),
              settingsActionsProvider.overrideWith((ref) => actions = _FakeActions(ref)),
            ],
            child: MaterialApp(
              theme: AppTheme.current,
              builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
              home: const Scaffold(body: Column(children: [TitiTipsSwitch()])),
            ),
          ),
        );
        expect(find.text('TiTi tips'), findsOneWidget);
        Switch sw() => tester.widget<Switch>(find.descendant(of: find.byKey(const Key('settings-titi-tips')), matching: find.byType(Switch)));
        expect(sw().value, isTrue);

        await tester.tap(find.byKey(const Key('settings-titi-tips')));
        await tester.pumpAndSettle();
        expect(actions.saved, [
          {'titi_tips': false},
        ]);
        expect(sw().value, isFalse);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('settings-titi-tips')));
        await tester.pumpAndSettle();
        expect(actions.saved.last, {'titi_tips': true});
      });
    }
  });

  group('titi_nudge notification', () {
    AppNotification n(String? body) => AppNotification.fromMap({
          'id': 'n1',
          'type': 'titi_nudge',
          'body': body,
          'read_at': null,
          'created_at': '2026-10-07T01:00:00Z',
        });

    test('parses and opens the TiTi chat', () {
      expect(NotificationType.fromDb('titi_nudge'), NotificationType.titiNudge);
      final row = n("Rain's rolling into PJ this afternoon ☔");
      expect(row.type, NotificationType.titiNudge);
      expect(activityText(row), ("TiTi: Rain's rolling into PJ this afternoon ☔", Routes.titi));
      expect(activityText(n(null)).$2, Routes.titi);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('the Activity row shows TiTi and fits at 320 wide, text x$scale', (tester) async {
        tester.view.physicalSize = const Size(320 * 3, 700 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            theme: AppTheme.current,
            builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: Scaffold(
              body: ListView(children: [
                ActivityRow(n: n("Rain's rolling into PJ this afternoon ☔ grab an umbrella and go easy on the corners, okay? Your Myvi wants to come home shiny."), badges: const [], me: 'me'),
              ]),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.textContaining('TiTi: Rain', findRichText: true), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    test("TiTi's line in his chat is a normal answer bubble", () {
      final m = TitiMessage.fromRow({
        'id': 'm1',
        'role': 'assistant',
        'content': 'Road tax for the Myvi runs out in 3 days 🙌',
        'parts': {
          'nudge': {'trigger': 'doc'},
        },
        'created_at': '2026-10-07T02:00:00Z',
      });
      expect(m.mine, isFalse);
      expect(m.text, 'Road tax for the Myvi runs out in 3 days 🙌');
      expect(m.chips, isEmpty);
    });
  });

  group('titiChatIsBehind', () {
    TitiSession latest(String id, DateTime at) => TitiSession(id: id, title: null, updatedAt: at);
    TitiMessage msg(DateTime? at) => TitiMessage(key: 'k$at', mine: false, parts: const [], at: at);
    final t = DateTime(2026, 10, 7, 9);

    test('another chat is newer: open it', () {
      expect(titiChatIsBehind(openId: 'a', messages: [msg(t)], latest: latest('b', t)), isTrue);
      expect(titiChatIsBehind(openId: null, messages: const [], latest: latest('b', t)), isTrue);
    });

    test('same chat: reload only when something landed after the newest message', () {
      expect(titiChatIsBehind(openId: 'a', messages: [msg(t)], latest: latest('a', t.add(const Duration(seconds: 20)))), isFalse);
      expect(titiChatIsBehind(openId: 'a', messages: [msg(t)], latest: latest('a', t.add(const Duration(hours: 3)))), isTrue);
      expect(titiChatIsBehind(openId: 'a', messages: const [], latest: latest('a', t)), isTrue);
      expect(titiChatIsBehind(openId: 'a', messages: [msg(null)], latest: latest('a', t)), isFalse);
    });
  });
}
