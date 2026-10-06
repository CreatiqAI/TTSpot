import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/data/auth_repository.dart' show currentProfileProvider;
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_images.dart';
import 'package:car_meet/features/social/application/club_members_providers.dart';
import 'package:car_meet/features/social/application/community_providers.dart';
import 'package:car_meet/features/social/data/club_tag_repository.dart';
import 'package:car_meet/features/social/domain/club.dart';
import 'package:car_meet/features/social/domain/club_member.dart';
import 'package:car_meet/features/social/domain/club_tag.dart';
import 'package:car_meet/features/social/presentation/club_members_screen.dart';
import 'package:car_meet/features/social/presentation/widgets/club_tag_chooser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 0.3.56 (migration 0111): a club's members page (View all on the club
// page: everyone with their role, club tag and default car) and the club
// tag chooser (Settings > Club tag on my name: one of my official clubs, or
// none; presidents choose too). At text x1.0 and x1.3, light and dark, on a
// 360 dp phone.

SupabaseClient _offline() => SupabaseClient('http://localhost', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false));

const _clubId = 'c-crew';
const _base = 'https://x.supabase.co/storage/v1/object/public/car-photos';

Map<String, dynamic> _car(String owner, String make, String model, {int? year, String? toy, String? body, List<String> photos = const []}) => {
      'id': 'car-$owner',
      'owner_id': owner,
      'make': make,
      'model': model,
      'year': year,
      'photo_urls': photos,
      'created_at': '2026-09-20T10:00:00+00:00',
      'is_default': true,
      'body_style': body,
      'toy_url': toy,
      'toy_status': toy == null ? null : 'ready',
    };

/// Rows as club_members_list returns them: officers first, then by join date.
List<ClubMemberEntry> _rows({int extra = 0}) => [
      for (final m in [
        {
          'user_id': 'u-boss',
          'username': 'aiman_fk8',
          'display_name': 'Muhammad Aiman Hakimi bin Abdul Rahman',
          'role': 'owner',
          'joined_at': '2026-09-01T00:00:00+00:00',
          'club_tag': {'club_id': _clubId, 'name': 'TT Spot Crew Official Club of Kuala Lumpur', 'handle': 'ttspot_crew', 'avatar_url': null, 'role': 'owner'},
          'car': _car('u-boss', 'Honda', 'Civic Type R FK8', year: 2019, toy: '$_base/u-boss/a_toy.png', body: 'hatchback'),
        },
        {
          'user_id': 'u-vp',
          'username': 'keith',
          'display_name': 'Keith Lim',
          'role': 'vp',
          'joined_at': '2026-09-02T00:00:00+00:00',
          'club_tag': null,
          'car': _car('u-vp', 'Proton', 'X70 1.8 TGDI Premium Edition with a very long name', body: 'SUV'),
        },
        {'user_id': 'u-sec', 'username': 'sec_amy', 'display_name': null, 'role': 'secretary', 'joined_at': '2026-09-03T00:00:00+00:00', 'club_tag': null, 'car': null},
        {
          'user_id': 'u-me',
          'username': 'testing',
          'display_name': 'App Review',
          'role': 'member',
          'joined_at': '2026-09-04T00:00:00+00:00',
          'club_tag': null,
          'car': _car('u-me', 'Perodua', 'Myvi', year: 2022, body: 'hatchback'),
        },
        for (var i = 0; i < extra; i++)
          {'user_id': 'u-$i', 'username': 'member_$i', 'display_name': 'Member $i', 'role': 'member', 'joined_at': '2026-09-10T00:00:00+00:00', 'car': null},
      ])
        ClubMemberEntry.fromMap(m),
    ];

Club _club(String id, String name, {bool official = true, String owner = 'u-boss', DateTime? created, DateTime? until}) => Club(
      id: id,
      name: name,
      handle: id.replaceAll('-', '_'),
      ownerId: owner,
      createdAt: created ?? DateTime(2026, 9, 1),
      memberCount: 4,
      tier: official ? 'official' : 'underground',
      officialUntil: until,
    );

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(360 * 3, 760 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Widget _app({required GoRouter router, required List overrides, double scale = 1.0}) => ProviderScope(
      retry: (_, _) => null,
      overrides: [currentUserIdProvider.overrideWithValue('u-me'), ...overrides.cast()],
      child: MaterialApp.router(
        theme: AppTheme.current,
        routerConfig: router,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      ),
    );

// ------------------------------------------------------------ members page ---

Future<void> _pumpMembers(WidgetTester t, List<ClubMemberEntry> rows, {double scale = 1.0, bool dark = false}) async {
  AppColors.dark = dark;
  _phone(t);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const ClubMembersScreen(clubId: _clubId)),
    GoRoute(path: '/profile/:id', builder: (_, s) => Scaffold(body: Text('profile ${s.pathParameters['id']}'))),
    GoRoute(path: '/club/:id', builder: (_, s) => Scaffold(body: Text('club ${s.pathParameters['id']}'))),
  ]);
  addTearDown(router.dispose);
  await t.pumpWidget(_app(
    router: router,
    scale: scale,
    overrides: [
      clubProvider(_clubId).overrideWith((ref) async => _club(_clubId, 'TT Spot Crew Official Club of Kuala Lumpur')),
      clubMembersListProvider(_clubId).overrideWith((ref) async => rows),
    ],
  ));
  await t.pumpAndSettle();
}

// --------------------------------------------------------------- chooser ---

/// The server's tag rules for me: president default, then my pick or none.
class _FakeTags extends ClubTagRepository {
  _FakeTags(this.mine, {this.fail = false}) : super(_offline());
  ClubTag? mine;
  final bool fail;
  final chosen = <String?>[];
  final clubs = <String, Club>{};

  @override
  Future<ClubTag?> tagOf(String userId) async => userId == 'u-me' ? mine : null;

  @override
  Future<ClubTag?> choose(String? clubId) async {
    if (fail) throw Exception('offline');
    chosen.add(clubId);
    final c = clubs[clubId];
    mine = c == null ? null : ClubTag(clubId: c.id, name: c.name, handle: c.handle, role: c.ownerId == 'u-me' ? 'owner' : 'member');
    return mine;
  }
}

final _mineOfficial = _club('c-mine', 'Weekend Wanderers', owner: 'u-me', created: DateTime(2026, 9, 1));
final _otherOfficial = _club('c-crew', 'TT Spot Crew Official Club of Kuala Lumpur', created: DateTime(2026, 9, 10), until: DateTime.now().add(const Duration(days: 30)));
final _lapsed = _club('c-lapsed', 'Lapsed Official', created: DateTime(2026, 8, 1), until: DateTime.now().subtract(const Duration(days: 1)));
final _underground = _club('c-ug', 'Night Owls', official: false, owner: 'u-me');

Future<_FakeTags> _pumpChooser(WidgetTester t, {List<Club>? clubs, ClubTag? mine, double scale = 1.0, bool dark = false, bool fail = false, bool asSheet = false}) async {
  AppColors.dark = dark;
  _phone(t);
  final all = clubs ?? [_otherOfficial, _underground, _mineOfficial, _lapsed];
  final tags = _FakeTags(mine ?? ClubTag(clubId: _mineOfficial.id, name: _mineOfficial.name, role: 'owner'), fail: fail);
  for (final c in all) {
    tags.clubs[c.id] = c;
  }
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => asSheet
          ? Scaffold(body: Builder(builder: (context) => Center(child: TextButton(onPressed: () => showClubTagChooser(context), child: const Text('open')))))
          : const Scaffold(body: ClubTagChooserSheet()),
    ),
  ]);
  addTearDown(router.dispose);
  await t.pumpWidget(_app(
    router: router,
    scale: scale,
    overrides: [
      myClubsProvider.overrideWith((ref) async => all),
      myClubRolesProvider.overrideWith((ref) async => {'c-mine': 'owner', 'c-crew': 'vp', 'c-ug': 'owner', 'c-lapsed': 'member'}),
      currentProfileProvider.overrideWith((ref) async => Profile(id: 'u-me', username: 'testing', displayName: 'App Review', createdAt: DateTime(2026))),
      clubTagRepositoryProvider.overrideWithValue(tags),
    ],
  ));
  await t.pumpAndSettle();
  if (asSheet) {
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }
  return tags;
}

Finder _preview(Finder f) => find.descendant(of: find.byKey(const Key('club-tag-preview')), matching: f);

void main() {
  setUp(() {
    // No network in tests: every URL is a bundled picture.
    garageImageFor = (url) => const AssetImage('assets/cars/sedan.png');
  });
  tearDown(() => AppColors.dark = false);

  group('ClubMemberEntry', () {
    test('reads club_members_list rows', () {
      final rows = _rows();
      final boss = rows.first;
      expect(boss.role, 'owner');
      expect(boss.isOfficer, isTrue);
      expect(boss.clubTag?.isPresident, isTrue);
      expect(boss.car?.toyUrl, endsWith('a_toy.png'));
      expect(boss.carLine, '2019 Honda Civic Type R FK8');
      expect(rows[2].name, '@sec_amy');
      expect(rows[2].car, isNull);
      expect(rows[2].carLine, isNull);
      expect(rows[3].isOfficer, isFalse);
    });

    test('search matches name, handle or car', () {
      final rows = _rows();
      expect(rows.where((r) => r.matches('x70')).map((r) => r.userId), ['u-vp']);
      expect(rows.where((r) => r.matches('aiman')).map((r) => r.userId), ['u-boss']);
      expect(rows.where((r) => r.matches('sec_')).map((r) => r.userId), ['u-sec']);
      expect(rows.where((r) => r.matches('')).length, rows.length);
    });

    test('a car row it cannot read: the person still shows, without a car', () {
      final e = ClubMemberEntry.fromMap({'user_id': 'u-x', 'username': 'x', 'role': 'member', 'car': {'id': 'c'}});
      expect(e.car, isNull);
    });
  });

  for (final dark in const [false, true]) {
    for (final scale in const [1.0, 1.3]) {
      final mode = '${dark ? 'dark' : 'light'}, x$scale';

      testWidgets('members page: roles, tags and cars, no overflow ($mode)', (t) async {
        await _pumpMembers(t, _rows(), scale: scale, dark: dark);
        expect(t.takeException(), isNull);
        expect(find.text('Members · 4'), findsOneWidget);
        expect(find.text('TT Spot Crew Official Club of Kuala Lumpur'), findsWidgets);
        // Officers first, in the server's order.
        final ys = [for (final id in ['u-boss', 'u-vp', 'u-sec', 'u-me']) t.getTopLeft(find.byKey(Key('club-member-$id'))).dy];
        for (var i = 1; i < ys.length; i++) {
          expect(ys[i], greaterThan(ys[i - 1]));
        }
        expect(find.text('President'), findsOneWidget);
        expect(find.text('Vice President'), findsOneWidget);
        expect(find.text('Secretary'), findsOneWidget);
        expect(find.text('Member'), findsOneWidget);
        // The president's club tag beside the name.
        expect(find.byKey(const ValueKey('club-tag-$_clubId')), findsOneWidget);
        // Cars: the toy where there is one, else the photo/body art; make + model.
        expect(find.text('2019 Honda Civic Type R FK8'), findsOneWidget);
        expect(find.text('2022 Perodua Myvi'), findsOneWidget);
        expect(find.byKey(const ValueKey('member-car-toy')), findsOneWidget);
        expect(find.byType(MemberCarThumb), findsNWidgets(3)); // the secretary has no car
        expect(find.text('App Review (you)'), findsOneWidget);
        // Few members: no search box.
        expect(find.byKey(const Key('club-members-search')), findsNothing);
      });

      testWidgets('members page: search with a big club ($mode)', (t) async {
        await _pumpMembers(t, _rows(extra: 12), scale: scale, dark: dark);
        expect(find.byKey(const Key('club-members-search')), findsOneWidget);
        await t.enterText(find.byKey(const Key('club-members-search')), 'x70');
        await t.pumpAndSettle();
        expect(find.byKey(const Key('club-member-u-vp')), findsOneWidget);
        expect(find.byKey(const Key('club-member-u-boss')), findsNothing);
        await t.enterText(find.byKey(const Key('club-members-search')), 'zzz');
        await t.pumpAndSettle();
        expect(find.text('Nobody matches "zzz"'), findsOneWidget);
        await t.tap(find.text('Clear search'));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('club-member-u-boss')), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('chooser: my official clubs + None, a pick moves the radio ($mode)', (t) async {
        final tags = await _pumpChooser(t, scale: scale, dark: dark);
        expect(t.takeException(), isNull);
        expect(find.text('Club tag on my name'), findsOneWidget);
        // Official clubs only (oldest first), not underground or lapsed ones.
        expect(find.byKey(const Key('club-tag-option-c-mine')), findsOneWidget);
        expect(find.byKey(const Key('club-tag-option-c-crew')), findsOneWidget);
        expect(find.byKey(const Key('club-tag-option-none')), findsOneWidget);
        expect(find.byKey(const Key('club-tag-option-c-ug')), findsNothing);
        expect(find.byKey(const Key('club-tag-option-c-lapsed')), findsNothing);
        expect(t.getTopLeft(find.byKey(const Key('club-tag-option-c-mine'))).dy, lessThan(t.getTopLeft(find.byKey(const Key('club-tag-option-c-crew'))).dy));
        expect(find.text('President'), findsOneWidget);
        expect(find.text('Vice President'), findsOneWidget);
        // As president I wear my own club's by default.
        expect(_preview(find.byKey(const ValueKey('club-tag-c-mine'))), findsOneWidget);
        // Pick the other club: saved, and the preview follows.
        await t.tap(find.byKey(const Key('club-tag-option-c-crew')));
        await t.pumpAndSettle();
        expect(tags.chosen, ['c-crew']);
        expect(_preview(find.byKey(const ValueKey('club-tag-c-crew'))), findsOneWidget);
        // None: no tag at all, presidents included.
        await t.tap(find.byKey(const Key('club-tag-option-none')));
        await t.pumpAndSettle();
        expect(tags.chosen, ['c-crew', null]);
        expect(_preview(find.text('No tag')), findsOneWidget);
        // Tapping the one already picked does nothing.
        await t.tap(find.byKey(const Key('club-tag-option-none')));
        await t.pumpAndSettle();
        expect(tags.chosen, ['c-crew', null]);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('members page: tap a member opens their profile', (t) async {
    await _pumpMembers(t, _rows());
    await t.tap(find.byKey(const Key('club-member-u-vp')));
    await t.pumpAndSettle();
    expect(find.text('profile u-vp'), findsOneWidget);
  });

  testWidgets('members page: nobody yet', (t) async {
    await _pumpMembers(t, const []);
    expect(find.text('No members yet'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('chooser: a member of no official club is told why there is nothing to pick', (t) async {
    await _pumpChooser(t, clubs: [_underground], mine: const ClubTag(clubId: 'x', name: 'x'));
    expect(find.textContaining('You\'re not in an official club yet'), findsOneWidget);
    expect(find.byKey(const Key('club-tag-option-none')), findsNothing);
  });

  testWidgets('chooser: a failed save goes back to what the server has', (t) async {
    await _pumpChooser(t, fail: true);
    await t.tap(find.byKey(const Key('club-tag-option-c-crew')));
    await t.pumpAndSettle();
    // The snackbar says what went wrong; the pick snaps back to the server's.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(_preview(find.byKey(const ValueKey('club-tag-c-mine'))), findsOneWidget);
  });

  testWidgets('chooser: opens as a sheet over the page, with a close button', (t) async {
    await _pumpChooser(t, asSheet: true, scale: 1.3);
    expect(find.text('Club tag on my name'), findsOneWidget);
    expect(find.byKey(const Key('club-tag-option-c-crew')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.bySemanticsLabel('Close'));
    await t.pumpAndSettle();
    expect(find.text('Club tag on my name'), findsNothing);
  });
}
