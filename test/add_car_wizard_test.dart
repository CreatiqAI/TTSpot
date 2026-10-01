import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/profile/presentation/car_form_screen.dart';
import 'package:car_meet/features/profile/presentation/widgets/car_color_picker.dart';
import 'package:car_meet/features/settings/application/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// No profile in tests: settings are the defaults (Hide my number plate off).
class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings({});
}

/// A small Android phone (360 x 740 dp) at [scale] text size.
Future<void> _pump(WidgetTester tester, {required double scale, required bool dark}) async {
  tester.view.physicalSize = const Size(1080, 2220);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 24 * 3, bottom: 16 * 3);
  addTearDown(tester.view.reset);
  AppColors.dark = dark;
  addTearDown(() => AppColors.dark = false);
  await tester.pumpWidget(ProviderScope(
    overrides: [settingsProvider.overrideWith(_Settings.new)],
    child: MaterialApp(
      theme: AppTheme.current,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: const CarFormScreen(),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Scrolls the step to the bottom and back, failing on any layout error
/// (overflow stripes throw in tests).
Future<void> _sweep(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  final list = find.byType(ListView).first;
  for (var i = 0; i < 6; i++) {
    await tester.drag(list, const Offset(0, -300), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
  }
  for (var i = 0; i < 7; i++) {
    await tester.drag(list, const Offset(0, 300), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
  }
}

/// Scrolls the step until [f] is built and on screen.
Future<void> _reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
  await tester.pump();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final scale in [1.0, 1.3]) {
    for (final dark in [false, true]) {
      testWidgets('Add car walks Photos → Your car → Papers → Park it with no overflow (text ${scale}x, ${dark ? 'dark' : 'light'})', (tester) async {
        await _pump(tester, scale: scale, dark: dark);

        // 1. Photos
        expect(find.textContaining('Show me your ride'), findsOneWidget);
        await _reveal(tester, find.text('Hide my number plate'));
        await _sweep(tester);
        await _tapButton(tester, 'Next without a photo');

        // 2. Your car: make and model are required.
        await _tapButton(tester, 'Next');
        expect(find.text('Required'), findsNWidgets(2));
        await tester.enterText(find.widgetWithText(TextField, 'Make'), 'Perodua');
        await tester.enterText(find.widgetWithText(TextField, 'Model'), 'Myvi 1.5 AV');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await _reveal(tester, find.text('Silver'));
        expect(find.text('COLOUR ON THE MAP'), findsOneWidget);
        expect(find.text('This is how your car shows on the map.'), findsOneWidget);
        expect(find.byType(MapCarPreview), findsOneWidget);
        await tester.tap(find.text('Silver'));
        await tester.pump();
        expect(find.text('Silver · picked by you'), findsOneWidget);
        await _sweep(tester);
        await _tapButton(tester, 'Next');

        // 3. Papers: optional, Skip for now while empty.
        expect(find.textContaining('Papers, if you have them handy'), findsOneWidget);
        expect(find.text('Skip for now'), findsOneWidget);
        await _sweep(tester);

        // Back keeps the draft.
        await _tapButton(tester, 'Back');
        expect(find.text('Perodua'), findsWidgets);
        await _reveal(tester, find.text('Silver · picked by you'));
        await _tapButton(tester, 'Next');
        await _tapButton(tester, 'Skip for now');

        // 4. Park it: the summary and the button.
        expect(find.text('Park it in my garage'), findsOneWidget);
        await _reveal(tester, find.text('Silver on the map'));
        await _reveal(tester, find.text('Papers skipped'));
        await _reveal(tester, find.text('GARAGE LOOK'));
        await _sweep(tester);
      });
    }
  }
}
