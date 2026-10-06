import 'package:firebase_messaging/firebase_messaging.dart' show AuthorizationStatus;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:car_meet/core/location/background_location.dart';
import 'package:car_meet/core/location/location_gate.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/onboarding/application/permissions_step.dart';
import 'package:car_meet/features/onboarding/presentation/permissions_screen.dart';
import 'package:car_meet/features/settings/application/background_location_controller.dart';

/// The permissions step after onboarding: each card's button is Enable, On
/// or Settings from what the phone says; Enable runs the phone's prompt (or
/// the background disclosure first); a blocked permission goes to phone
/// settings; coming back to the app re-reads everything; Continue always
/// works, asking once to be sure when location is off. No overflow at
/// 360 px wide with text at 1.0 and 1.3.
void main() {
  const offBg = BgLocationState(native: NativeBgStatus(supported: true, foreground: true), loaded: true);
  const onBg = BgLocationState(native: NativeBgStatus(supported: true, enabled: true, running: true, background: true, foreground: true), loaded: true, shareMode: 'friends');
  const needsAlwaysBg = BgLocationState(native: NativeBgStatus(supported: true, enabled: true, foreground: true), loaded: true, shareMode: 'friends');

  late _FakeDevice device;
  late _FakeBg bg;
  late List<MethodCall> platformCalls;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    BgLocationState bgState = offBg,
    BgEnableOutcome bgOutcome = BgEnableOutcome.on,
    double scale = 1.0,
    double width = 360,
    bool still = true,
    Future<bool?> Function(BuildContext)? confirm,
  }) async {
    tester.view.physicalSize = Size(width * 2, 740 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    platformCalls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final container = ProviderContainer(overrides: [
      permissionsDeviceProvider.overrideWithValue(device),
      backgroundLocationProvider.overrideWith(() => bg = _FakeBg(bgState, bgOutcome)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.current,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: still),
          child: child!,
        ),
        home: PermissionsScreen(confirmBackground: confirm ?? (_) async => true),
      ),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  /// The pill inside the card titled [title].
  Finder pillIn(String title, String label) => find.descendant(
        of: find.ancestor(of: find.textContaining(title), matching: find.byType(PermissionCard)),
        matching: find.text(label),
      );

  Future<void> tapPill(WidgetTester tester, Finder pill) async {
    await tester.ensureVisible(pill);
    await tester.pumpAndSettle();
    await tester.tap(pill);
  }

  int haptics() => platformCalls.where((c) => c.method == 'HapticFeedback.vibrate').length;

  setUp(() => device = _FakeDevice());

  testWidgets('everything off: three Enable pills, the title, the line and the Optional tag', (tester) async {
    await pump(tester);
    expect(find.text('TURN ON PERMISSIONS'), findsOneWidget);
    expect(find.text('So the map works for you.'), findsOneWidget);
    expect(pillIn('Location', 'Enable'), findsOneWidget);
    expect(pillIn('Notifications', 'Enable'), findsOneWidget);
    expect(pillIn('Share when', 'Enable'), findsOneWidget);
    expect(find.text('OPTIONAL'), findsOneWidget);
    // Android wording of the phone's own prompts.
    expect(find.text('Tap "While using the app".'), findsOneWidget);
    expect(find.text('Tap "Allow" for meets, friends and messages.'), findsOneWidget);
    expect(find.text('Choose "Allow all the time".'), findsOneWidget);
    expect(device.stepShownCalls, 1);
  });

  testWidgets('everything on: three green On pills and nothing to tap', (tester) async {
    device
      ..perm = LocationPermission.whileInUse
      ..notif = AuthorizationStatus.authorized;
    await pump(tester, bgState: onBg);
    expect(pillIn('Location', 'On'), findsOneWidget);
    expect(pillIn('Notifications', 'On'), findsOneWidget);
    expect(pillIn('Share when', 'On'), findsOneWidget);
    expect(find.text('Enable'), findsNothing);
    expect(device.registers, greaterThan(0), reason: 'allowed notifications register this phone for push');
    await tapPill(tester, pillIn('Location', 'On'));
    await tester.pumpAndSettle();
    expect(device.locationRequests, 0);
  });

  testWidgets('blocked before: Settings pills that open phone settings (iPhone)', (tester) async {
    device
      ..perm = LocationPermission.deniedForever
      ..notif = AuthorizationStatus.denied;
    await pump(tester, bgState: needsAlwaysBg);
    expect(pillIn('Location', 'Settings'), findsOneWidget);
    expect(pillIn('Notifications', 'Settings'), findsOneWidget);
    expect(pillIn('Share when', 'Settings'), findsOneWidget);
    expect(find.text('Tap "Allow While Using App".'), findsNothing);
    expect(find.text('Turned off · fix in Settings'), findsNWidgets(2));

    await tapPill(tester, pillIn('Location', 'Settings'));
    await tester.pumpAndSettle();
    expect(device.appSettings, 1);
    expect(device.locationRequests, 0, reason: 'the phone would not show its prompt again');
    await tapPill(tester, pillIn('Notifications', 'Settings'));
    await tester.pumpAndSettle();
    expect(device.notificationSettings, 1);
    expect(device.notificationRequests, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iPhone wording for the three prompts', (tester) async {
    device.notif = AuthorizationStatus.notDetermined;
    await pump(tester);
    expect(find.text('Tap "Allow While Using App".'), findsOneWidget);
    expect(find.text('Tap "Allow" for meets, friends and messages.'), findsOneWidget);
    expect(find.text('Tap "Change to Always Allow".'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Android: "denied" before the first prompt still says Enable', (tester) async {
    device.notif = AuthorizationStatus.denied;
    await pump(tester);
    expect(pillIn('Notifications', 'Enable'), findsOneWidget);
  });

  testWidgets('Location Enable: the prompt, then a green On and a light tap', (tester) async {
    device.onRequestLocation = LocationPermission.whileInUse;
    await pump(tester);
    await tapPill(tester, pillIn('Location', 'Enable'));
    await tester.pumpAndSettle();
    expect(device.locationRequests, 1);
    expect(pillIn('Location', 'On'), findsOneWidget);
    expect(haptics(), 1);
  });

  testWidgets('Location Enable when the phone refuses at once: Settings, and phone settings open', (tester) async {
    device.onRequestLocation = LocationPermission.deniedForever;
    await pump(tester);
    await tapPill(tester, pillIn('Location', 'Enable'));
    await tester.pumpAndSettle();
    expect(device.appSettings, 1);
    expect(pillIn('Location', 'Settings'), findsOneWidget);
    expect(haptics(), 0);
  });

  testWidgets('Notifications Enable: the prompt, then On', (tester) async {
    device.onRequestNotifications = (status: AuthorizationStatus.authorized, prompted: true);
    await pump(tester);
    await tapPill(tester, pillIn('Notifications', 'Enable'));
    await tester.pumpAndSettle();
    expect(device.notificationRequests, 1);
    expect(pillIn('Notifications', 'On'), findsOneWidget);
    expect(haptics(), 1);
  });

  testWidgets('Notifications Enable answered at once with no: Settings, and phone settings open', (tester) async {
    device.onRequestNotifications = (status: AuthorizationStatus.denied, prompted: false);
    await pump(tester);
    await tapPill(tester, pillIn('Notifications', 'Enable'));
    await tester.pumpAndSettle();
    expect(device.notificationSettings, 1);
    expect(pillIn('Notifications', 'Settings'), findsOneWidget);
  });

  testWidgets('Android: a second "Don\'t allow" turns the pill into Settings', (tester) async {
    device.onRequestNotifications = (status: AuthorizationStatus.denied, prompted: true);
    await pump(tester);
    await tapPill(tester, pillIn('Notifications', 'Enable'));
    await tester.pumpAndSettle();
    expect(pillIn('Notifications', 'Enable'), findsOneWidget);
    expect(device.notificationSettings, 0);
    await tapPill(tester, pillIn('Notifications', 'Enable'));
    await tester.pumpAndSettle();
    expect(pillIn('Notifications', 'Settings'), findsOneWidget);
  });

  testWidgets('back from phone settings: the pills are read again', (tester) async {
    device.perm = LocationPermission.deniedForever;
    await pump(tester);
    expect(pillIn('Location', 'Settings'), findsOneWidget);
    device
      ..perm = LocationPermission.whileInUse
      ..notif = AuthorizationStatus.authorized;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(pillIn('Location', 'On'), findsOneWidget);
    expect(pillIn('Notifications', 'On'), findsOneWidget);
    expect(haptics(), 1);
  });

  testWidgets('Share my spot: nothing turns on unless the disclosure says Turn on', (tester) async {
    var asked = 0;
    await pump(tester, confirm: (_) async {
      asked++;
      return false;
    });
    await tapPill(tester, pillIn('Share when', 'Enable'));
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(bg.enables, 0);
    expect(pillIn('Share when', 'Enable'), findsOneWidget);
  });

  testWidgets('Share my spot: Turn on in the disclosure runs the opt-in, then On', (tester) async {
    await pump(tester);
    await tapPill(tester, pillIn('Share when', 'Enable'));
    await tester.pumpAndSettle();
    expect(bg.enables, 1);
    expect(pillIn('Share when', 'On'), findsOneWidget);
    expect(haptics(), 1);
  });

  testWidgets('Share my spot: "Always" not given yet shows Settings and says what to choose', (tester) async {
    await pump(tester, bgOutcome: BgEnableOutcome.needsAlways);
    await tapPill(tester, pillIn('Share when', 'Enable'));
    await tester.pumpAndSettle();
    expect(pillIn('Share when', 'Settings'), findsOneWidget);
    expect(find.text('Needs "Allow all the time"'), findsOneWidget);
  });

  testWidgets('Continue with location on goes straight to the map', (tester) async {
    device.perm = LocationPermission.whileInUse;
    final c = await pump(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Use TT Spot without location?'), findsNothing);
    expect(c.read(permissionsStepDoneProvider), isTrue);
  });

  testWidgets('Continue without location asks first; Not now lets the member in', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Use TT Spot without location?'), findsOneWidget);
    expect(c.read(permissionsStepDoneProvider), isFalse);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(c.read(permissionsStepDoneProvider), isTrue);
    expect(device.locationRequests, 0);
  });

  testWidgets('Continue without location: Turn on asks for it and goes on once allowed', (tester) async {
    device.onRequestLocation = LocationPermission.whileInUse;
    final c = await pump(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(device.locationRequests, 1);
    expect(c.read(permissionsStepDoneProvider), isTrue);
  });

  testWidgets('Continue without location: Turn on refused stays on the page; a dismissed confirm too', (tester) async {
    device.onRequestLocation = LocationPermission.denied;
    final c = await pump(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(c.read(permissionsStepDoneProvider), isFalse);
    expect(find.text('TURN ON PERMISSIONS'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // outside the dialog
    await tester.pumpAndSettle();
    expect(find.text('Use TT Spot without location?'), findsNothing);
    expect(c.read(permissionsStepDoneProvider), isFalse);
  });

  testWidgets('the cards rise in, and all of them end up fully shown', (tester) async {
    await pump(tester, still: false);
    final opacities = tester.widgetList<Opacity>(find.ancestor(of: find.byType(PermissionCard), matching: find.byType(Opacity))).map((o) => o.opacity);
    expect(opacities, everyElement(1.0));
  });

  // Overflow: every pill state at 360 px, text at 1.0 and 1.3.
  for (final scale in [1.0, 1.3]) {
    for (final (name, loc, notif, bgState) in [
      ('off', LocationPermission.denied, AuthorizationStatus.notDetermined, offBg),
      ('on', LocationPermission.whileInUse, AuthorizationStatus.authorized, onBg),
      ('settings', LocationPermission.deniedForever, AuthorizationStatus.denied, needsAlwaysBg),
    ]) {
      testWidgets('no overflow at 360 px, text x$scale, pills $name', (tester) async {
        device
          ..perm = loc
          ..notif = notif;
        await pump(tester, bgState: bgState, scale: scale);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Continue'), findsOneWidget);
        if (name == 'off') {
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();
          expect(find.text('Use TT Spot without location?'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }, variant: name == 'settings' ? TargetPlatformVariant.only(TargetPlatform.iOS) : TargetPlatformVariant.only(TargetPlatform.android));
    }
  }

  group('pill rules', () {
    test('location', () {
      expect(locationPill(LocationPermission.whileInUse, serviceOn: true, blocked: false), PermPill.on);
      expect(locationPill(LocationPermission.always, serviceOn: true, blocked: false), PermPill.on);
      expect(locationPill(LocationPermission.whileInUse, serviceOn: false, blocked: false), PermPill.settings);
      expect(locationPill(LocationPermission.denied, serviceOn: true, blocked: false), PermPill.enable);
      expect(locationPill(LocationPermission.denied, serviceOn: true, blocked: true), PermPill.settings);
      expect(locationPill(LocationPermission.deniedForever, serviceOn: true, blocked: false), PermPill.settings);
      expect(locationPill(null, serviceOn: true, blocked: false), PermPill.enable);
    });

    test('notifications', () {
      expect(notificationsPill(AuthorizationStatus.authorized, blocked: false, ios: true), PermPill.on);
      expect(notificationsPill(AuthorizationStatus.provisional, blocked: false, ios: true), PermPill.on);
      expect(notificationsPill(AuthorizationStatus.notDetermined, blocked: false, ios: true), PermPill.enable);
      expect(notificationsPill(AuthorizationStatus.denied, blocked: false, ios: true), PermPill.settings);
      expect(notificationsPill(AuthorizationStatus.denied, blocked: false, ios: false), PermPill.enable);
      expect(notificationsPill(AuthorizationStatus.denied, blocked: true, ios: false), PermPill.settings);
      expect(notificationsPill(null, blocked: false, ios: false), PermPill.enable);
    });

    test('share while closed', () {
      expect(backgroundPill(offBg), PermPill.enable);
      expect(backgroundPill(onBg), PermPill.on);
      expect(backgroundPill(needsAlwaysBg), PermPill.settings);
      expect(backgroundPill(const BgLocationState(native: NativeBgStatus(supported: true), loaded: true, waitingForAlways: true)), PermPill.settings);
      expect(backgroundPill(const BgLocationState(native: NativeBgStatus(supported: true, enabled: true, background: true), loaded: true, shareMode: 'ghost')), PermPill.on);
      expect(backgroundPill(const BgLocationState(loaded: true)), isNull, reason: 'no card where the phone cannot do it');
      expect(backgroundPill(const BgLocationState()), PermPill.enable, reason: 'still loading: the card shows, its button waits');
    });
  });
}

class _FakeDevice implements PermissionsDevice {
  LocationPermission perm = LocationPermission.denied;
  bool serviceOn = true;
  AuthorizationStatus? notif = AuthorizationStatus.notDetermined;
  LocationPermission onRequestLocation = LocationPermission.whileInUse;
  ({AuthorizationStatus status, bool prompted})? onRequestNotifications = (status: AuthorizationStatus.authorized, prompted: true);

  int stepShownCalls = 0;
  int locationRequests = 0;
  int notificationRequests = 0;
  int appSettings = 0;
  int locationSettings = 0;
  int notificationSettings = 0;
  int registers = 0;
  int backgroundRequests = 0;

  @override
  void stepShown() => stepShownCalls++;

  @override
  Future<LocationPermission> location() async => perm;

  @override
  Future<bool> locationServiceOn() async => serviceOn;

  @override
  Future<LocationPermission> requestLocation() async {
    locationRequests++;
    return perm = onRequestLocation;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettings++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettings++;
    return true;
  }

  @override
  Future<AuthorizationStatus?> notifications() async => notif;

  @override
  Future<({AuthorizationStatus status, bool prompted})?> requestNotifications() async {
    notificationRequests++;
    final r = onRequestNotifications;
    if (r != null) notif = r.status;
    return r;
  }

  @override
  Future<void> registerPush() async => registers++;

  @override
  Future<bool> openNotificationSettings() async {
    notificationSettings++;
    return true;
  }

  @override
  Future<bool> requestBackground() async {
    backgroundRequests++;
    return false;
  }
}

class _FakeBg extends BackgroundLocationController {
  _FakeBg(this.initial, this.outcome);
  final BgLocationState initial;
  final BgEnableOutcome outcome;
  int enables = 0;

  @override
  BgLocationState build() => initial;

  @override
  Future<void> sync({bool fromResume = false}) async {}

  @override
  Future<BgEnableOutcome> enable() async {
    enables++;
    switch (outcome) {
      case BgEnableOutcome.on:
        state = const BgLocationState(
          native: NativeBgStatus(supported: true, enabled: true, running: true, background: true, foreground: true),
          loaded: true,
          shareMode: 'friends',
        );
      case BgEnableOutcome.needsAlways:
        state = state.copyWith(waitingForAlways: true);
      default:
        break;
    }
    return outcome;
  }
}
