import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/cards/presentation/widgets/get_box_banner.dart';
import 'package:car_meet/features/profile/presentation/widgets/profile_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget child, {double scale = 1, bool dark = false}) async {
  AppColors.dark = dark;
  addTearDown(() => AppColors.dark = false);
  t.view.physicalSize = const Size(1080, 2340); // a 393 x 851 phone
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.current,
    builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    home: Scaffold(body: child),
  ));
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('profile tabs: a red underline under the selected tab, bold label (${dark ? 'dark' : 'light'})', (t) async {
      var selected = 0;
      late StateSetter set;
      await _pump(
        t,
        StatefulBuilder(builder: (context, setState) {
          set = setState;
          return CustomScrollView(slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: ProfileTabBar(tabs: const [(AppIcons.squaresFour, 'Posts'), (AppIcons.cards, 'Cards')], selected: selected, onSelect: (i) => set(() => selected = i)),
            ),
          ]);
        }),
        dark: dark,
      );
      final bar = find.byKey(const ValueKey('profile-tab-indicator'));
      final box = t.widget<DecoratedBox>(bar).decoration as BoxDecoration;
      expect(box.color, AppColors.brand);
      expect(t.getSize(bar).height, ProfileTabBar.indicatorHeight);
      final left0 = t.getTopLeft(bar).dx;

      TextStyle styleOf(String label) => t.widget<DefaultTextStyle>(find.ancestor(of: find.text(label), matching: find.byType(DefaultTextStyle)).first).style;
      expect(styleOf('Posts').fontWeight, FontWeight.w800);
      expect(styleOf('Cards').fontWeight, FontWeight.w500);
      expect(styleOf('Cards').color, AppColors.textMuted);

      await t.tap(find.text('Cards'));
      await t.pumpAndSettle();
      expect(selected, 1);
      expect(t.getTopLeft(bar).dx, greaterThan(left0 + 100), reason: 'the underline slides to Cards');
      expect(styleOf('Cards').fontWeight, FontWeight.w800);
      expect(styleOf('Cards').color, AppColors.textPrimary);
      // Phosphor cards, not the sparkle.
      expect(find.byIcon(AppIcons.cards), findsOneWidget);
      expect(find.byIcon(AppIcons.sparkle), findsNothing);
    });
  }

  for (final scale in [1.0, 1.3]) {
    for (final waiting in [0, 1, 3]) {
      testWidgets('box banner lays out at text x$scale with $waiting waiting', (t) async {
        var taps = 0;
        await _pump(t, Padding(padding: const EdgeInsets.all(16), child: GetBoxBanner(waiting: waiting, cost: 100, onTap: () => taps++)), scale: scale);
        await t.pump(const Duration(milliseconds: 900));
        expect(t.takeException(), isNull);
        expect(find.text(waiting > 0 ? 'OPEN YOUR BLIND BOX' : 'GET A BLIND BOX'), findsOneWidget);
        if (waiting == 0) expect(find.text('100 points · 1 of 7 TiTi cards'), findsOneWidget);
        if (waiting == 1) expect(find.text('1 free box waiting'), findsOneWidget);
        if (waiting == 3) expect(find.text('3 free boxes waiting'), findsOneWidget);
        await t.tap(find.byType(GetBoxBanner));
        await t.pump(const Duration(milliseconds: 300));
        expect(taps, 1);
        await t.pumpWidget(const SizedBox()); // stop the loop
      });
    }
  }
}
