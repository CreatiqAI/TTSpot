import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/settings/application/settings_providers.dart';
import 'package:car_meet/features/social/presentation/widgets/chat_wallpaper.dart';

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
  test('every wallpaper has a light and a dark picture, each under 150 KB', () {
    for (final w in ChatWallpaper.values) {
      for (final dark in [false, true]) {
        final f = File(w.asset(dark: dark));
        expect(f.existsSync(), isTrue, reason: '${f.path} is missing');
        expect(f.lengthSync(), lessThan(150 * 1024), reason: '${f.path} is too big');
      }
    }
  });

  test('chat_wallpaper defaults to TT Spot and ignores unknown values', () {
    expect(const AppSettings({}).chatWallpaper, 'ttspot');
    expect(const AppSettings({'chat_wallpaper': 'night'}).chatWallpaper, 'night');
    expect(const AppSettings({'chat_wallpaper': 'titi'}).chatWallpaper, 'titi');
    expect(const AppSettings({'chat_wallpaper': 'vaporwave'}).chatWallpaper, 'ttspot');
    expect(const AppSettings({'chat_wallpaper': 3}).chatWallpaper, 'ttspot');
    expect(ChatWallpaper.fromId('night'), ChatWallpaper.night);
    expect(ChatWallpaper.fromId('nope'), ChatWallpaper.ttspot);
  });

  test('tiles repeat, Night drive covers', () {
    for (final w in ChatWallpaper.values) {
      final img = w.image(dark: false);
      expect(img.repeat, w.tiled ? ImageRepeat.repeat : ImageRepeat.noRepeat);
      expect(img.fit, w.tiled ? isNull : BoxFit.cover);
    }
    expect(ChatWallpaper.night.tiled, isFalse);
  });

  test('bubbles stand off every ground and their text reads, light and dark', () {
    double lum(Color c) => c.computeLuminance();
    double contrast(Color a, Color b) {
      final (x, y) = (lum(a), lum(b));
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }

    for (final dark in [false, true]) {
      AppColors.dark = dark;
      for (final w in ChatWallpaper.values) {
        final st = ChatWallpaperStyle.forWallpaper(w);
        for (final mine in [true, false]) {
          expect(contrast(AppColors.textPrimary, st.bubbleFill(mine)), greaterThan(7), reason: '$w dark=$dark mine=$mine text');
          expect(contrast(AppColors.textSecondary, st.bubbleFill(mine)), greaterThan(3), reason: '$w dark=$dark mine=$mine time');
        }
        // Light mode's own bubble must not melt into the warm grounds.
        if (!dark && w != ChatWallpaper.night) {
          expect(contrast(st.mineFill, w.ground(dark: false)), greaterThan(1.04), reason: '$w mine vs ground');
        }
      }
    }
    AppColors.dark = false;
  });

  for (final scale in [1.0, 1.3]) {
    for (final dark in [false, true]) {
      testWidgets('picker lays out at text x$scale (${dark ? 'dark' : 'light'}) and saves a pick', (tester) async {
        AppColors.dark = dark;
        addTearDown(() => AppColors.dark = false);
        tester.view.physicalSize = const Size(1080, 2340); // a 393 x 851 phone at 2.75x
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
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(child: TextButton(onPressed: () => showChatWallpaperPicker(context), child: const Text('open'))),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text('Chat background'), findsOneWidget);
        for (final w in ChatWallpaper.values) {
          expect(find.text(w.label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Night drive'));
        await tester.pumpAndSettle();
        expect(actions.saved, [
          {'chat_wallpaper': 'night'},
        ]);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Chat background'), findsNothing);
      });
    }
  }

  testWidgets('the background hands its bubble colours down', (tester) async {
    late ChatWallpaperStyle seen;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(() => _FakeSettings(const {'chat_wallpaper': 'night'}))],
        child: MaterialApp(
          home: ChatWallpaperBackground(
            child: Builder(builder: (context) {
              seen = ChatWallpaperStyle.of(context);
              return const SizedBox.expand();
            }),
          ),
        ),
      ),
    );
    expect(seen.theirsEdge, isNull); // night, light mode: no outline on their bubbles
    expect(seen.mineFill, ChatWallpaperStyle.forWallpaper(ChatWallpaper.night).mineFill);
  });
}
