import 'package:car_meet/core/config/app_version.dart';
import 'package:car_meet/core/config/update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareVersions', () {
    test('numeric, not alphabetical', () {
      expect(compareVersions('0.3.9', '0.3.10'), lessThan(0));
      expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
      expect(compareVersions('1.0.0', '0.99.99'), greaterThan(0));
      expect(compareVersions('0.3.63', '0.3.63'), 0);
    });

    test('missing parts count as 0, suffixes are ignored', () {
      expect(compareVersions('0.3', '0.3.0'), 0);
      expect(compareVersions('0.3', '0.3.1'), lessThan(0));
      expect(compareVersions('0.3.63+73', '0.3.63'), 0);
      expect(compareVersions('0.3.63-beta', '0.3.63'), 0);
      expect(compareVersions(' 0.3.64 ', '0.3.63'), greaterThan(0));
    });

    test('junk reads as 0, never throws', () {
      expect(compareVersions('', '0.0.0'), 0);
      expect(compareVersions('abc', '0.0.1'), lessThan(0));
    });

    test('mustUpdate only when older', () {
      expect(mustUpdate('0.3.63', '0.0.0'), isFalse);
      expect(mustUpdate('0.3.63', '0.3.63'), isFalse);
      expect(mustUpdate('0.3.63', '0.3.64'), isTrue);
      expect(mustUpdate('0.3.63', '0.4'), isTrue);
      expect(mustUpdate(kAppVersion, '0.0.0'), isFalse);
    });

    test('store links', () {
      expect(updateStoreUrl(platform: TargetPlatform.iOS), 'https://apps.apple.com/app/id6815672400');
      expect(updateStoreUrl(platform: TargetPlatform.android), contains('id=my.ttspot.app'));
    });
  });

  group('UpdateGate', () {
    late DateTime now;
    late List<String> calls;

    ProviderContainer container(Future<String> Function() load, {String version = '0.3.63'}) {
      final c = ProviderContainer(overrides: [
        minAppVersionLoaderProvider.overrideWithValue(() {
          calls.add('load');
          return load();
        }),
        updateGateProvider.overrideWith(() => UpdateGate(version: version, clock: () => now)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      now = DateTime(2026, 10, 9, 12);
      calls = [];
    });

    test('blocks an older app, not a current one', () async {
      final old = container(() async => '0.3.70');
      await old.read(updateGateProvider.notifier).check();
      expect(old.read(updateGateProvider), isTrue);

      final ok = container(() async => '0.0.0');
      await ok.read(updateGateProvider.notifier).check();
      expect(ok.read(updateGateProvider), isFalse);
    });

    test('a network error never blocks', () async {
      final c = container(() async => throw Exception('offline'));
      await c.read(updateGateProvider.notifier).check();
      expect(c.read(updateGateProvider), isFalse);
    });

    test('checks at most every 10 minutes, and a lowered minimum unblocks', () async {
      var min = '0.4.0';
      final c = container(() async => min);
      final gate = c.read(updateGateProvider.notifier);
      await gate.check();
      expect(c.read(updateGateProvider), isTrue);
      min = '0.0.0';
      now = now.add(const Duration(minutes: 9));
      await gate.check();
      expect(calls, ['load']);
      expect(c.read(updateGateProvider), isTrue);
      now = now.add(const Duration(minutes: 2));
      await gate.check();
      expect(calls, ['load', 'load']);
      expect(c.read(updateGateProvider), isFalse);
    });

    test('a failed check is retried on the next resume', () async {
      var fail = true;
      final c = container(() async => fail ? throw Exception('offline') : '0.9.0');
      final gate = c.read(updateGateProvider.notifier);
      await gate.check();
      fail = false;
      await gate.check();
      expect(calls, ['load', 'load']);
      expect(c.read(updateGateProvider), isTrue);
    });
  });

  testWidgets('the update page fits a small phone at text scale 1.3', (t) async {
    t.view.physicalSize = const Size(320 * 3, 568 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.3)),
        child: const Scaffold(body: UpdateRequiredPage()),
      ),
    ));
    await t.pump();
    expect(find.text('Time for an update'), findsOneWidget);
    expect(find.text('This version of TT Spot is too old to keep working. Update to carry on.'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
