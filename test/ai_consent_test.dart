import 'package:car_meet/core/consent/ai_consent.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/presentation/car_page/car_hero.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_images.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_studio.dart' show MakeToyChip;
import 'package:car_meet/features/profile/presentation/widgets/toy_car_image.dart';
import 'package:car_meet/features/settings/application/settings_providers.dart';
import 'package:car_meet/features/titi/presentation/titi_screen.dart' show TitiConsentBanner;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// AI consent (Apple 5.1.2(i)): the settings getters, the sheet at large text,
// the TiTi banner, and the toy states that depend on the OK.

const _base = 'https://x.supabase.co/storage/v1/object/public/car-photos/u1';

Car _car({String? toyUrl, String? toyStatus}) => Car(
      id: 'a',
      ownerId: 'u1',
      make: 'Perodua',
      model: 'Myvi',
      photoUrls: const ['$_base/a.jpg'],
      createdAt: DateTime(2026, 9, 1),
      bodyStyle: 'hatchback',
      toyUrl: toyUrl,
      toyStatus: toyStatus,
    );

/// A small phone at [scale], so any overflow shows.
Future<void> _pump(WidgetTester t, Widget child, {double scale = 1.3, Size size = const Size(320, 640)}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, w) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: w!,
    ),
    home: Scaffold(body: child),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  group('AppSettings.aiConsent', () {
    test('nothing saved: no consent of any kind', () {
      const s = AppSettings({});
      expect(s.aiConsent, isEmpty);
      expect(s.titiConsent, isFalse);
      expect(s.toyConsent, isFalse);
      expect(s.safetyConsent, isFalse);
      expect(s.aiConsentAt('titi'), isNull);
    });

    test('each key is read on its own, with its date', () {
      const s = AppSettings({
        'ai_consent': {'titi': '2026-10-08T03:00:00.000Z', 'safety': '2026-10-09T01:02:03Z'},
      });
      expect(s.titiConsent, isTrue);
      expect(s.toyConsent, isFalse);
      expect(s.safetyConsent, isTrue);
      expect(s.aiConsentAt('titi'), DateTime.utc(2026, 10, 8, 3));
      expect(s.aiConsentAt('toy'), isNull);
    });

    test('junk reads as no: empty strings, nulls, other types, not a map', () {
      const s = AppSettings({
        'ai_consent': {'titi': '', 'toy': null, 'safety': true},
      });
      expect(s.aiConsent, isEmpty);
      expect(s.titiConsent || s.toyConsent || s.safetyConsent, isFalse);
      expect(const AppSettings({'ai_consent': 'yes'}).titiConsent, isFalse);
      expect(const AppSettings({'ai_consent': ['titi']}).titiConsent, isFalse);
    });

    test('hasAiConsent maps each kind to its key', () {
      const s = AppSettings({
        'ai_consent': {'toy': '2026-10-08T00:00:00Z'},
      });
      expect(hasAiConsent(s, AiConsentKind.toy), isTrue);
      expect(hasAiConsent(s, AiConsentKind.titi), isFalse);
      expect(hasAiConsent(s, AiConsentKind.safety), isFalse);
      expect(AiConsentKind.values.map((k) => k.key), ['titi', 'toy', 'safety']);
    });

    test('withAiConsent: the whole object goes up, the first date stands', () {
      final at = DateTime.utc(2026, 10, 9, 8, 30);
      final next = withAiConsent(const {'toy': '2026-10-01T00:00:00Z'}, 'titi', at);
      expect(next, {'toy': '2026-10-01T00:00:00Z', 'titi': '2026-10-09T08:30:00.000Z'});
      expect(withAiConsent(next, 'titi', DateTime.utc(2027))['titi'], '2026-10-09T08:30:00.000Z');
      // Saved as UTC whatever the phone's zone.
      expect(withAiConsent(const {}, 'safety', at.toLocal())['safety'], '2026-10-09T08:30:00.000Z');
    });
  });

  group('the sheet', () {
    for (final kind in AiConsentKind.values) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('${kind.key}: title, what is sent, Privacy Policy, two buttons; no overflow (text $scale)', (t) async {
          var agreed = 0, declined = 0, privacy = 0;
          await _pump(
            t,
            AiConsentSheet(kind: kind, onAgree: () => agreed++, onDecline: () => declined++, onPrivacy: () => privacy++),
            scale: scale,
          );
          expect(t.takeException(), isNull);
          final copy = kAiConsentCopy[kind]!;
          expect(find.text(copy.title), findsOneWidget);
          for (final (_, line) in copy.lines) {
            expect(find.text(line), findsOneWidget);
          }
          expect(find.text("It isn't used to train their models."), findsOneWidget);
          // The company is named.
          expect(copy.lines.any((l) => l.$2.contains(kind == AiConsentKind.toy ? 'Kie.ai' : 'OpenAI')), isTrue);

          await t.ensureVisible(find.byKey(const ValueKey('ai-consent-privacy')));
          await t.tap(find.byKey(const ValueKey('ai-consent-privacy')));
          await t.ensureVisible(find.byKey(const ValueKey('ai-consent-agree')));
          await t.tap(find.byKey(const ValueKey('ai-consent-agree')));
          await t.ensureVisible(find.byKey(const ValueKey('ai-consent-decline')));
          await t.tap(find.byKey(const ValueKey('ai-consent-decline')));
          expect((privacy, agreed, declined), (1, 1, 1));
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('the exact copy', (t) async {
      expect(kAiConsentCopy[AiConsentKind.titi]!.title, 'Chat with TiTi?');
      expect(kAiConsentCopy[AiConsentKind.toy]!.title, 'Use AI on your car photos?');
      expect(kAiConsentCopy[AiConsentKind.safety]!.lines.first.$2, 'Posts are checked by an automated safety filter (OpenAI) to keep TT Spot safe.');
      expect(kAiConsentCopy[AiConsentKind.safety]!.agree, 'OK');
      expect(kAiConsentCopy[AiConsentKind.titi]!.agree, 'Agree');
      expect(kAiConsentCopy[AiConsentKind.toy]!.decline, 'Not now');
    });

    testWidgets('showAiConsentSheet: Agree → true, Not now → false, swiped away → false', (t) async {
      t.view.physicalSize = const Size(360, 740) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, w) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)), child: w!),
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        })),
      ));

      Future<bool?> ask(Future<void> Function() act) async {
        bool? result;
        showAiConsentSheet(ctx, AiConsentKind.titi).then((v) => result = v);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Chat with TiTi?'), findsOneWidget);
        await act();
        await t.pumpAndSettle();
        expect(find.text('Chat with TiTi?'), findsNothing);
        return result;
      }

      Future<void> tapKey(String key) async {
        await t.ensureVisible(find.byKey(ValueKey(key)));
        await t.pumpAndSettle();
        await t.tap(find.byKey(ValueKey(key)));
      }

      expect(await ask(() => tapKey('ai-consent-agree')), isTrue);
      expect(await ask(() => tapKey('ai-consent-decline')), isFalse);
      // Swiped away / back button: the route pops with no answer.
      expect(await ask(() async => Navigator.of(ctx, rootNavigator: true).pop()), isFalse);
    });
  });

  group('TiTi banner', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('one line and Allow, no overflow (text $scale)', (t) async {
        var allowed = 0;
        await _pump(t, Align(alignment: Alignment.bottomCenter, child: TitiConsentBanner(onAllow: () => allowed++)), scale: scale);
        expect(t.takeException(), isNull);
        expect(find.text('TiTi needs your OK to use OpenAI'), findsOneWidget);
        await t.tap(find.text('Allow'));
        expect(allowed, 1);
      });
    }
  });

  group('toy cars without the OK', () {
    setUp(() {
      garageImageFor = (url) => const AssetImage('assets/portrait_samples/showroom.webp');
    });

    test('a car never asked for is "on its way" only once toy cars are allowed', () {
      final fresh = _car();
      expect(ToyCarImage.stateFor(fresh, mine: true), 'pending');
      expect(ToyCarImage.stateFor(fresh, mine: true, toyConsent: false), 'fallback');
      // A toy that already exists stays, OK or not.
      final made = _car(toyUrl: '$_base/a_toy.png', toyStatus: 'ready');
      expect(ToyCarImage.stateFor(made, mine: true, toyConsent: false), 'toy');
    });

    testWidgets('ToyConsentScope(false): no "Building your toy car…" caption', (t) async {
      await _pump(t, Center(child: ToyConsentScope(allowed: false, child: ToyCarImage(car: _car(), width: 280, mine: true))), scale: 1.0);
      expect(find.textContaining('Building your toy car'), findsNothing);
      await _pump(t, Center(child: ToyCarImage(car: _car(), width: 280, mine: true)), scale: 1.0);
      expect(find.textContaining('Building your toy car'), findsOneWidget);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('"Make my toy car" chip, no overflow (text $scale)', (t) async {
        var taps = 0;
        await _pump(t, Center(child: MakeToyChip(onTap: () => taps++)), scale: scale);
        expect(t.takeException(), isNull);
        await t.tap(find.text('Make my toy car'));
        expect(taps, 1);
      });

      testWidgets('car page: "No toy car yet." with Make my toy car (text $scale)', (t) async {
        var taps = 0;
        await _pump(
          t,
          SingleChildScrollView(
            child: ToyConsentScope(
              allowed: false,
              child: CarHero(car: _car(), mine: true, topInset: 0, onMakeToy: () => taps++),
            ),
          ),
          scale: scale,
          size: const Size(320, 900),
        );
        expect(t.takeException(), isNull);
        expect(find.text('No toy car yet.'), findsOneWidget);
        await t.tap(find.text('Make my toy car'));
        expect(taps, 1);
      });
    }

    testWidgets('car page: no note once allowed (onMakeToy null)', (t) async {
      await _pump(t, SingleChildScrollView(child: CarHero(car: _car(), mine: true, topInset: 0)), scale: 1.0, size: const Size(320, 900));
      expect(find.text('No toy car yet.'), findsNothing);
    });
  });
}
