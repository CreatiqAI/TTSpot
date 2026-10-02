import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/core/theme/titi.dart';
import 'package:car_meet/features/auth/data/auth_repository.dart';
import 'package:car_meet/features/map/application/map_providers.dart';
import 'package:car_meet/features/vendors/application/vendors_providers.dart';
import 'package:car_meet/features/vendors/domain/vendor.dart';
import 'package:car_meet/features/vendors/presentation/partner_apply_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _vendor = Vendor.fromMap({
  'id': '62e5d258-1a87-4104-a0d5-0694a8b374b9',
  'name': 'Auto Lab',
  'type': 'accessories',
  'active': true,
  'commission_rate': 0.01,
  'created_at': '2026-09-15T17:35:59Z',
});

final _approved = PartnerApplication.fromMap({
  'id': 'bc42cc50-9ad5-41d5-abc5-ad99d378fbfd',
  'kind': 'vendor',
  'business_name': 'Auto Lab',
  'status': 'approved',
  'created_at': '2026-09-15T17:34:03Z',
});

final _pending = PartnerApplication.fromMap({
  'id': 'a1',
  'kind': 'vendor',
  'business_name': 'Garage One',
  'status': 'pending',
  'created_at': '2026-10-01T10:00:00Z',
});

Future<void> _pump(WidgetTester t, {required Future<PartnerApplication?> Function() app, required Future<Vendor?> Function() vendor}) async {
  await t.pumpWidget(ProviderScope(
    overrides: [
      myPartnerApplicationProvider(ApplicationKind.vendor).overrideWith((ref) => app()),
      myVendorProvider.overrideWith((ref) => vendor()),
      currentProfileProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(theme: AppTheme.current, home: const PartnerApplyScreen()),
  ));
}

/// The empty form for [kind] on a 360 dp wide phone at [scale].
Future<void> _pumpForm(WidgetTester t, ApplicationKind kind, double scale) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      myPartnerApplicationProvider(kind).overrideWith((ref) async => null),
      myVendorProvider.overrideWith((ref) async => null),
      currentProfileProvider.overrideWith((ref) async => null),
      userLocationProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(
      theme: AppTheme.current,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: PartnerApplyScreen(kind: kind),
    ),
  ));
  await t.pump();
  await t.pump();
  // Let TiTi finish typing his line.
  await t.pump(const Duration(seconds: 5));
}

void main() {
  for (final scale in const [1.0, 1.3]) {
    testWidgets('club form: TiTi introduces clubs, four benefit rows, no overflow at $scale', (t) async {
      await _pumpForm(t, ApplicationKind.club, scale);
      expect(find.byType(TitiSays), findsOneWidget);
      expect(find.textContaining('Approved clubs get their own page'), findsWidgets); // the bubble lays its line out twice
      for (final title in ['Club page. ', 'Club map. ', 'Club admins. ', 'Post and host. ']) {
        await t.scrollUntilVisible(find.textContaining(title, findRichText: true), 200, scrollable: find.byType(Scrollable).first);
        expect(find.textContaining(title, findRichText: true), findsOneWidget);
      }
      // Down to the footer: every field on the way is laid out (an overflow fails the test).
      await t.scrollUntilVisible(find.textContaining('invite your members'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Add your club logo first'), findsOneWidget);
    });

    testWidgets('partner form: TiTi introduces partners, four benefit rows, no overflow at $scale', (t) async {
      await _pumpForm(t, ApplicationKind.vendor, scale);
      expect(find.byType(TitiSays), findsOneWidget);
      expect(find.textContaining('Approved partners get a shop page'), findsWidgets);
      for (final title in ['Shop on the map. ', 'Vouchers. ', 'Mini store. ', 'Posts, events, stats. ']) {
        await t.scrollUntilVisible(find.textContaining(title, findRichText: true), 200, scrollable: find.byType(Scrollable).first);
        expect(find.textContaining(title, findRichText: true), findsOneWidget);
      }
      await t.scrollUntilVisible(find.textContaining('monthly statement'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Send application'), findsOneWidget);
    });
  }

  testWidgets('pending application: TiTi on the phone, details card kept', (t) async {
    await _pump(t, app: () async => _pending, vendor: () async => null);
    await t.pump();
    await t.pump();
    expect(find.text('Application received'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Titi && w.pose == TitiPose.phone), findsOneWidget);
    expect(find.text('Garage One'), findsOneWidget);
  });

  testWidgets('already a partner: says so and links to the dashboard', (t) async {
    await _pump(t, app: () async => _approved, vendor: () async => _vendor);
    await t.pump();
    await t.pump();
    expect(find.text('Auto Lab is a partner'), findsOneWidget);
    expect(find.text('Open partner dashboard'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Titi && w.pose == TitiPose.celebrate), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed load shows Try again at once, not an endless spinner', (t) async {
    var calls = 0;
    var fail = true;
    await _pump(
      t,
      app: () async {
        calls++;
        if (fail) throw Exception('network down');
        return _pending;
      },
      vendor: () async => null,
    );
    await t.pump();
    await t.pump();
    // Riverpod is retrying in the background (that state reads as loading),
    // but the screen already says what happened.
    expect(find.text('Couldn\'t load this page'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    fail = false;
    final before = calls;
    await t.tap(find.text('Try again'));
    await t.pump();
    await t.pump();
    expect(calls, greaterThan(before));
    expect(find.text('Couldn\'t load this page'), findsNothing);
    // Not a partner yet, application waiting: its status.
    expect(find.text('Application received'), findsOneWidget);
    // Let Riverpod's pending retry timer run out.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });
}
