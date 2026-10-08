import 'package:firebase_messaging/firebase_messaging.dart' show AuthorizationStatus;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:car_meet/core/location/background_location.dart';
import 'package:car_meet/core/location/location_gate.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/core/widgets/picker_field.dart';
import 'package:car_meet/features/auth/application/account_basics.dart';
import 'package:car_meet/features/auth/application/username_suggestion.dart';
import 'package:car_meet/features/auth/data/auth_repository.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/auth/presentation/onboarding_screen.dart';
import 'package:car_meet/features/auth/presentation/widgets/onboarding_progress.dart';
import 'package:car_meet/features/cards/domain/cards.dart';
import 'package:car_meet/features/onboarding/application/permissions_step.dart';
import 'package:car_meet/features/safety/application/name_check.dart';
import 'package:car_meet/features/onboarding/presentation/permissions_screen.dart';
import 'package:car_meet/features/settings/application/background_location_controller.dart';

/// Onboarding 0.3.59: a thin progress bar (ride → you → permissions → gift),
/// home state in one picker field, the username suggested from the name
/// (with a number when taken, never over the member's own), and the
/// permissions page inside the flow before the gift. 360 px wide, text at
/// 1.0 and 1.3, no overflow.
void main() {
  group('step order', () {
    test('ride → you → permissions → gift, four steps', () {
      expect(onboardingPageAfter(OnboardingPage.ride, hasGift: true), OnboardingPage.you);
      expect(onboardingPageAfter(OnboardingPage.you, hasGift: true), OnboardingPage.permissions);
      expect(onboardingPageAfter(OnboardingPage.permissions, hasGift: true), OnboardingPage.gift);
      expect(onboardingPageAfter(OnboardingPage.gift, hasGift: true), isNull);
      expect(kOnboardingSteps, 4);
      expect([for (final p in OnboardingPage.values) onboardingStepOf(p)], [1, 2, 3, 4]);
    });

    test('no gift waiting: permissions is the last page', () {
      expect(onboardingPageAfter(OnboardingPage.permissions, hasGift: false), isNull);
    });
  });

  group('username from the name', () {
    test('lowercase words joined by _', () {
      expect(usernameFromName('Aiman Hakim'), 'aiman_hakim');
      expect(usernameFromName('  Wei  Jie  '), 'wei_jie');
      expect(usernameFromName('Ah Meng\'s GT-R'), 'ah_mengs_gt_r');
      expect(usernameFromName('José'), 'jose');
      expect(usernameFromName('Muhammad Aiman Hakim bin Abdullah'), 'muhammad_aiman_hakim');
      expect(usernameFromName('Abcdefghijklmnopqrstuvwxyz'), 'abcdefghijklmnopqrst');
    });

    test('nothing usable: null', () {
      expect(usernameFromName(''), isNull);
      expect(usernameFromName('Al'), isNull);
      expect(usernameFromName('陈伟杰'), isNull);
    });

    test('a number goes on the end, within 20', () {
      expect(withSuffix('aiman_hakim', 7), 'aiman_hakim7');
      expect(withSuffix('abcdefghijklmnopqrst', 42), 'abcdefghijklmnopqr42');
      expect(withSuffix('abcdefghijklmnopqr_t', 42), 'abcdefghijklmnopqr42');
    });

    test('taken → short number suffix; all taken or check failing → null', () async {
      expect(await suggestUsername('Aiman Hakim', (_) async => true), 'aiman_hakim');
      final asked = <String>[];
      final s = await suggestUsername('Aiman Hakim', (u) async {
        asked.add(u);
        return u != 'aiman_hakim';
      });
      expect(asked.first, 'aiman_hakim');
      expect(s, matches(RegExp(r'^aiman_hakim\d{1,2}$')));
      expect(await suggestUsername('Aiman Hakim', (_) async => false), isNull);
      expect(await suggestUsername('Aiman Hakim', (_) async => throw Exception('offline')), isNull);
    });
  });

  group('progress bar', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('fills one quarter per step, no overflow (text $scale)', (t) async {
        await _size(t);
        for (final step in [1, 2, 3, 4]) {
          await t.pumpWidget(_app(
            scale: scale,
            child: Scaffold(
              body: Column(children: [
                OnboardingProgress(step: step, total: 4, onBack: step > 1 ? () {} : null, onClose: () {}),
                OnboardingProgress(step: step, total: 4, dark: true, onBack: () {}),
              ]),
            ),
          ));
          await t.pumpAndSettle();
          final bars = t.widgetList<FractionallySizedBox>(find.descendant(of: find.byType(OnboardingProgress), matching: find.byType(FractionallySizedBox)));
          for (final b in bars) {
            expect(b.widthFactor, closeTo(step / 4, 1e-9));
          }
          expect(find.bySemanticsLabel('Step $step of 4'), findsNWidgets(2));
          expect(find.byKey(const ValueKey('onboarding-back')), findsNWidgets(step > 1 ? 2 : 1));
          expect(t.getSize(find.byType(OnboardingProgress).first).height, OnboardingProgress.height);
          expect(t.takeException(), isNull);
        }
      });
    }
  });

  group('screen', () {
    late _Checker checker;
    late _FakeDevice device;
    setUp(() {
      checker = _Checker();
      device = _FakeDevice();
    });

    Future<ProviderContainer> pump(WidgetTester t, {double scale = 1.0, OnboardingPage? startAt, CardBox? gift, Profile? profile}) async {
      await _size(t);
      final container = ProviderContainer(overrides: [
        currentProfileProvider.overrideWith((ref) async => profile ?? _newMember()),
        accountBasicsProvider.overrideWith((ref) async => null),
        usernameAvailabilityProvider.overrideWithValue(checker.call),
        nameCheckProvider.overrideWithValue(_fakeNameCheck),
        permissionsDeviceProvider.overrideWithValue(device),
        backgroundLocationProvider.overrideWith(_FakeBg.new),
      ]);
      addTearDown(container.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: _app(scale: scale, child: OnboardingScreen(debugStartAt: startAt, debugGift: gift)),
      ));
      await t.pumpAndSettle();
      return container;
    }

    Finder nameField() => find.descendant(of: find.byType(TextFormField), matching: find.byType(EditableText)).first;
    String usernameText(WidgetTester t) => t.widget<EditableText>(find.descendant(of: find.byType(TextFormField), matching: find.byType(EditableText)).at(1)).controller.text;

    for (final scale in [1.0, 1.3]) {
      testWidgets('"your ride": step 1 of 4, no back arrow, no overflow (text $scale)', (t) async {
        await pump(t, scale: scale, profile: Profile(id: 'me', createdAt: DateTime(2026, 10, 7), carCount: 0));
        expect(find.bySemanticsLabel('Step 1 of 4'), findsOneWidget);
        expect(find.byKey(const ValueKey('onboarding-back')), findsNothing);
        expect(find.byTooltip('Sign out'), findsOneWidget);
        expect(find.text('WHAT DO YOU DRIVE?'), findsOneWidget);
        // The old 1-2-3 road is gone.
        expect(find.text('A GIFT'), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('"you": step 2 of 4, one Home state field, no overflow (text $scale)', (t) async {
        await pump(t, scale: scale);
        expect(find.bySemanticsLabel('Step 2 of 4'), findsOneWidget);
        expect(find.text('Home state'), findsOneWidget);
        // No chip grid any more.
        expect(find.text('Selangor'), findsNothing);
        expect(find.text('More…'), findsNothing);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('Home state opens a list of all 16; the pick shows in the field; empty = "Choose your state"', (t) async {
      await pump(t, scale: 1.3);
      // Continue without a state: the same message as before.
      await t.ensureVisible(find.text('Continue'));
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.text('Choose your state'), findsOneWidget);

      await t.ensureVisible(find.byType(PickerField<String>));
      await t.tap(find.byType(PickerField<String>));
      await t.pumpAndSettle();
      expect(find.text('Johor'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Terengganu'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('Terengganu'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Penang'), -200, scrollable: find.byType(Scrollable).last);
      await t.tap(find.text('Penang'));
      await t.pumpAndSettle();
      expect(find.text('Penang'), findsOneWidget);
      expect(find.text('Choose your state'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('typing a name fills the username; taken → a number on the end', (t) async {
      checker.taken = {'aiman_hakim'};
      await pump(t);
      await t.enterText(nameField(), 'Aiman Hakim');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(usernameText(t), matches(RegExp(r'^aiman_hakim\d{1,2}$')));
      // The live check under the field agrees.
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.text('@${usernameText(t)} is yours.'), findsOneWidget);
    });

    testWidgets('a rude name and a reserved handle are refused under their fields', (t) async {
      await pump(t);
      await t.enterText(nameField(), 'Cibai King');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      // Under the name, and under the handle suggested from it.
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.text(_notAllowed), findsNWidgets(2));

      await t.enterText(nameField(), 'Wei Ling');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.text(_notAllowed), findsNothing);

      final userField = find.descendant(of: find.byType(TextFormField), matching: find.byType(EditableText)).at(1);
      await t.enterText(userField, 'admin123');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.text(_reserved), findsOneWidget);
      expect(find.text('@admin123 is yours.'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('a free name goes in as it is, and follows the name until the member edits it', (t) async {
      await pump(t);
      await t.enterText(nameField(), 'Aiman Hakim');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(usernameText(t), 'aiman_hakim');

      await t.enterText(nameField(), 'Wei Jie');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(usernameText(t), 'wei_jie');

      // The member types their own: suggestions stop.
      final userField = find.descendant(of: find.byType(TextFormField), matching: find.byType(EditableText)).at(1);
      await t.enterText(userField, 'speedy_wj');
      await t.pumpAndSettle();
      await t.enterText(nameField(), 'Tan Wei Jie');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(usernameText(t), 'speedy_wj');
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('permissions sit inside onboarding as step 3, then the gift as step 4 (text $scale)', (t) async {
        device.perm = LocationPermission.whileInUse;
        final c = await pump(t, scale: scale, startAt: OnboardingPage.permissions, gift: _box);
        expect(find.byType(PermissionsScreen), findsOneWidget);
        expect(find.bySemanticsLabel('Step 3 of 4'), findsOneWidget);
        expect(find.text('TURN ON PERMISSIONS'), findsOneWidget);
        expect(t.takeException(), isNull);
        expect(c.read(permissionsStepDoneProvider), isFalse);

        await t.ensureVisible(find.text('Continue'));
        await t.tap(find.text('Continue'));
        await t.pumpAndSettle();
        // Done for this launch: the router won't send them to /location again.
        expect(c.read(permissionsStepDoneProvider), isTrue);
        expect(find.byType(PermissionsScreen), findsNothing);
        expect(find.bySemanticsLabel('Step 4 of 4'), findsOneWidget);
        expect(find.text('Open my box'), findsOneWidget);
        expect(t.takeException(), isNull);

        // Back goes to permissions again.
        await t.tap(find.byKey(const ValueKey('onboarding-back')));
        await t.pumpAndSettle();
        expect(find.bySemanticsLabel('Step 3 of 4'), findsOneWidget);
      });
    }

    testWidgets('no gift waiting: Continue on permissions ends onboarding', (t) async {
      device.perm = LocationPermission.whileInUse;
      final c = await pump(t, startAt: OnboardingPage.permissions);
      await t.ensureVisible(find.text('Continue'));
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(c.read(permissionsStepDoneProvider), isTrue);
      expect(find.text('Open my box'), findsNothing);
    });

    testWidgets('back from permissions shows "you" again (step 2)', (t) async {
      await pump(t, startAt: OnboardingPage.permissions, gift: _box);
      await t.tap(find.byKey(const ValueKey('onboarding-back')));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Step 2 of 4'), findsOneWidget);
      expect(find.text('WHO\'S DRIVING?'), findsOneWidget);
    });
  });
}

final _box = CardBox(id: 'box-1', source: 'signup', status: 'sealed', pointsSpent: 0, createdAt: DateTime(2026, 10, 7));

/// Has a car, no username yet: the "you" page.
Profile _newMember() => Profile(id: 'me', createdAt: DateTime(2026, 10, 7), carCount: 1);

Future<void> _size(WidgetTester t) async {
  t.view.physicalSize = const Size(360 * 2, 740 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
}

Widget _app({required Widget child, double scale = 1.0}) => MaterialApp(
      theme: AppTheme.current,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: c!,
      ),
      home: child,
    );

class _Checker {
  Set<String> taken = {};
  Future<bool> call(String u) async => !taken.contains(u);
}

class _FakeBg extends BackgroundLocationController {
  @override
  BgLocationState build() => const BgLocationState(native: NativeBgStatus(supported: true, foreground: true), loaded: true);

  @override
  Future<void> sync({bool fromResume = false}) async {}

  @override
  Future<BgEnableOutcome> enable() async => BgEnableOutcome.on;
}

class _FakeDevice implements PermissionsDevice {
  LocationPermission perm = LocationPermission.denied;
  AuthorizationStatus? notif = AuthorizationStatus.notDetermined;

  @override
  void stepShown() {}
  @override
  Future<LocationPermission> location() async => perm;
  @override
  Future<bool> locationServiceOn() async => true;
  @override
  Future<LocationPermission> requestLocation() async => perm = LocationPermission.whileInUse;
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<bool> openLocationSettings() async => true;
  @override
  Future<AuthorizationStatus?> notifications() async => notif;
  @override
  Future<({AuthorizationStatus status, bool prompted})?> requestNotifications() async => (status: notif = AuthorizationStatus.authorized, prompted: true);
  @override
  Future<void> registerPush() async {}
  @override
  Future<bool> openNotificationSettings() async => true;
  @override
  Future<bool> requestBackground() async => true;
}

const _notAllowed = "That name isn't allowed. Try another.";
const _reserved = 'That name is reserved.';

/// Stands in for check_name: "cibai" is rude, "admin…" is reserved.
Future<String?> _fakeNameCheck(String text, NameKind kind) async {
  final t = text.toLowerCase();
  if (t.contains('cibai')) return _notAllowed;
  if (kind != NameKind.title && t.startsWith('admin')) return _reserved;
  return null;
}
