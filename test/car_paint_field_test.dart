import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/profile/application/profile_providers.dart';
import 'package:car_meet/features/profile/application/toy_providers.dart';
import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/domain/car_toy.dart';
import 'package:car_meet/features/profile/presentation/car_form_screen.dart';
import 'package:car_meet/features/profile/presentation/widgets/car_color_picker.dart';
import 'package:car_meet/features/settings/application/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// "Paint colour" (was "Colour on the map"): picking a colour repaints the
// toy car (migration 0110). The note under the field says what Save does,
// and when the daily cap holds the repaint back.

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings({});
}

final _now = DateTime(2026, 10, 6, 20, 0);

void main() {
  group('paintFieldNote', () {
    test('add car: where the colour came from', () {
      expect(paintFieldNote(color: null, editing: false, repaints: false, picked: false, fromPhoto: false).text, 'Pick the closest colour below.');
      expect(paintFieldNote(color: 'silver', editing: false, repaints: false, picked: false, fromPhoto: true).text, 'Silver · from the photo');
      expect(paintFieldNote(color: 'silver', editing: false, repaints: false, picked: true, fromPhoto: false).text, 'Silver · picked by you');
    });

    test('edit: the toy\'s paint now, or what Save does to it', () {
      expect(paintFieldNote(color: 'red', editing: true, repaints: false, picked: false, fromPhoto: false).text, 'Red · your toy\'s paint now');
      expect(paintFieldNote(color: null, editing: true, repaints: false, picked: false, fromPhoto: false).text, contains('keeps the colour of your photo'));
      final repaint = paintFieldNote(color: 'blue', editing: true, repaints: true, picked: true, fromPhoto: false, quota: const ToyQuota(limit: 3, used: 1));
      expect(repaint.text, 'Blue · your toy is repainted when you save, about 2 minutes');
      expect(repaint.warn, isFalse);
      expect(paintFieldNote(color: 'blue', editing: true, repaints: true, picked: false, fromPhoto: false, repainting: true).text, 'Blue · your toy is being repainted now, about 2 minutes');
    });

    test('the daily cap and a pause read in amber, with when it goes on', () {
      final capped = paintFieldNote(
        color: 'blue',
        editing: true,
        repaints: true,
        picked: true,
        fromPhoto: false,
        quota: ToyQuota(limit: 3, used: 3, nextAt: DateTime(2026, 10, 6, 21, 40)),
        now: _now,
      );
      expect(capped.warn, isTrue);
      expect(capped.text, '3 toy renders a day per car, and today\'s are used. The new paint goes on after 9:40 PM.');
      final tomorrow = paintFieldNote(
        color: 'blue',
        editing: true,
        repaints: true,
        picked: true,
        fromPhoto: false,
        quota: ToyQuota(limit: 3, used: 3, nextAt: DateTime(2026, 10, 7, 8, 5)),
        now: _now,
      );
      expect(tomorrow.text, endsWith('after 8:05 AM tomorrow.'));
      final paused = paintFieldNote(color: 'blue', editing: true, repaints: true, picked: true, fromPhoto: false, quota: const ToyQuota(limit: 3, used: 0, enabled: false));
      expect(paused.warn, isTrue);
      expect(paused.text, contains('taking a break'));
    });
  });

  for (final scale in [1.0, 1.3]) {
    for (final dark in [false, true]) {
      final mode = '${dark ? 'dark' : 'light'} @$scale';

      testWidgets('the field on a small phone ($mode): label, hint, amber note, swatches', (tester) async {
        tester.view.physicalSize = const Size(1080, 2220);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        AppColors.dark = dark;
        addTearDown(() => AppColors.dark = false);
        String? picked;
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.current,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: StatefulBuilder(
                    builder: (context, setState) => CarMapColourSection(
                      value: picked ?? 'red',
                      hint: 'Your toy car is repainted in this colour.',
                      note: toyCapMessage(ToyQuota(limit: 3, used: 3, nextAt: DateTime(2026, 10, 7, 8, 5)), now: _now),
                      noteColor: const Color(0xFFB45309),
                      onChanged: (v) => setState(() => picked = v),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('PAINT COLOUR'), findsOneWidget);
        expect(find.text('Your toy car is repainted in this colour.'), findsOneWidget);
        expect(find.textContaining('today\'s are used'), findsOneWidget);
        expect(find.byType(MapCarPreview), findsOneWidget);
        await tester.tap(find.text('Blue'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(picked, 'blue');
        expect(tester.takeException(), isNull);
      });

      testWidgets('Edit car shows "Paint colour" and the toy\'s paint ($mode)', (tester) async {
        tester.view.physicalSize = const Size(1080, 2220);
        tester.view.devicePixelRatio = 3;
        tester.view.padding = const FakeViewPadding(top: 24 * 3, bottom: 16 * 3);
        addTearDown(tester.view.reset);
        AppColors.dark = dark;
        addTearDown(() => AppColors.dark = false);
        // No photos (no network in tests): the toy's paint is the saved colour.
        final car = Car(id: 'c1', ownerId: 'u1', make: 'Perodua', model: 'Myvi 1.5 AV', photoUrls: const [], createdAt: DateTime(2026, 9, 1), color: 'red');
        await tester.pumpWidget(ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            carProvider('c1').overrideWith((ref) async => car),
            carToyQuotaProvider('c1').overrideWith((ref) async => const ToyQuota(limit: 3, used: 1)),
          ],
          child: MaterialApp(
            theme: AppTheme.current,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: const CarFormScreen(carId: 'c1'),
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.scrollUntilVisible(find.text('PAINT COLOUR'), 150, scrollable: find.byType(Scrollable).first);
        await tester.pump();
        expect(find.text('Your toy car is made in this colour.'), findsOneWidget); // no toy yet
        expect(find.text('Red · your toy\'s paint now'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Orange'), 150, scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('Orange'));
        await tester.pump();
        // No photo, no toy to repaint: the note just says it was picked.
        expect(find.text('Orange · picked by you'), findsOneWidget);
        final list = find.byType(ListView).first;
        for (var i = 0; i < 6; i++) {
          await tester.drag(list, const Offset(0, -300), warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 80));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
