import 'dart:io';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/admin/application/admin_providers.dart';
import 'package:car_meet/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:car_meet/features/friends/domain/presence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The admin dashboard's "Live now" and "Seen today" count on the server
/// (admin_stats) with the app's presence windows. The SQL and presence.dart
/// must agree, and the tiles must fit at text 1.0 and 1.3.

const _migration = 'supabase/migrations/20261005000104_presence_admin_fixes.sql';

void main() {
  group('admin_stats uses the presence windows', () {
    final sql = File(_migration).readAsStringSync();

    test('live now: at most kLiveWindow old', () {
      final m = RegExp(r"updated_at >= now\(\) - interval '(\d+) minutes?'").firstMatch(sql);
      expect(m, isNotNull, reason: 'admin_stats should count live as updated_at >= now() - interval');
      expect(Duration(minutes: int.parse(m!.group(1)!)), kLiveWindow);
    });

    test('seen today: under kShowWindow old', () {
      final m = RegExp(r"updated_at > now\(\) - interval '(\d+) hours?'").firstMatch(sql);
      expect(m, isNotNull, reason: 'admin_stats should count seen as updated_at > now() - interval');
      expect(Duration(hours: int.parse(m!.group(1)!)), kShowWindow);
    });

    test('ghosts and expired rows are off the map, so off the count', () {
      expect(sql, contains('where not ghost and expires_at > now()'));
    });

    test('old dashboards (on_map_now) get the live number, not 20 minutes', () {
      expect(sql, contains("'on_map_now', v_live"));
      expect(sql.contains("interval '20 minutes'"), isFalse);
    });
  });

  group('Right now tiles', () {
    const stats = AdminStats({
      'live_now': 3,
      'seen_today': 128,
      'on_map_now': 3,
      'users': 1240,
      'users_today': 0,
      'users_7d': 41,
      'meets_live': 2,
      'tt_today': 5,
      'checkins_today': 37,
      'meets_upcoming': 12,
      'meets_7d': 9,
    });

    Future<void> pump(WidgetTester t, {required double width, required double scale}) async {
      t.view.physicalSize = Size(width * 3, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        retry: (_, _) => null,
        overrides: [
          adminStatsProvider.overrideWith((ref) async => stats),
          platformSettingsProvider.overrideWith((ref) async => const <String, dynamic>{}),
          adminUsersProvider.overrideWith((ref) async => const <AdminUser>[]),
        ],
        child: MaterialApp(
          theme: AppTheme.current,
          builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
          home: const AdminDashboardScreen(),
        ),
      ));
      await t.pump();
      await t.pump();
    }

    for (final width in [360.0, 411.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('${width.round()} wide at text $scale: Live now and Seen today, no overflow', (t) async {
          await pump(t, width: width, scale: scale);
          expect(t.takeException(), isNull);
          expect(find.text('Live now'), findsOneWidget);
          expect(find.text('Seen today'), findsOneWidget);
          expect(find.text('3'), findsOneWidget);
          expect(find.text('128'), findsOneWidget);
          // 128 of 1240 members.
          expect(find.text('10% of members'), findsOneWidget);
          // The old 20-minute tile is gone.
          expect(find.text('On the map'), findsNothing);
          expect(find.text('Active · 24 h'), findsNothing);
        });
      }
    }
  });
}
