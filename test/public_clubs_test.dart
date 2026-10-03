import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/events/presentation/plan_steps/wizard_parts.dart';
import 'package:car_meet/features/social/application/social_providers.dart';
import 'package:car_meet/features/social/data/community_repository.dart';
import 'package:car_meet/features/social/domain/club.dart';
import 'package:car_meet/features/social/presentation/club_screen.dart';
import 'package:car_meet/features/social/presentation/create_club_screen.dart';
import 'package:car_meet/features/vendors/application/vendors_providers.dart';
import 'package:car_meet/features/vendors/domain/vendor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _clubId = 'club-1';
const _ownerId = 'owner-1';
const _meId = 'me-1';

Club _club({String policy = 'public'}) => Club(
      id: _clubId,
      name: 'Myvi Owners KL',
      handle: 'myvi_kl',
      description: 'Daily drivers, weekend meets.',
      homeState: 'Kuala Lumpur',
      ownerId: _ownerId,
      createdAt: DateTime(2026, 9, 1),
      memberCount: 1,
      joinPolicy: policy,
    );

/// The club in memory: joins, requests and the who-can-join setting change it.
class _FakeCommunity extends CommunityRepository {
  _FakeCommunity({required this.theClub, this.member = false, this.request, this.requests = const []})
      : super(SupabaseClient('http://localhost', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false)));

  Club theClub;
  bool member;
  String? request;
  List<ClubJoinRequest> requests;
  int joins = 0;
  final policies = <String>[];

  @override
  Future<Club?> club(String id) async => theClub;
  @override
  Future<bool> isMember(String clubId, String me) async => member;
  @override
  Future<List<Profile>> clubMembers(String clubId) async => [Profile(id: _ownerId, username: 'bigboss', displayName: 'Big Boss', createdAt: DateTime(2026))];
  @override
  Future<Map<String, String>> clubMemberRoles(String clubId) async => {_ownerId: 'owner'};
  @override
  Future<String?> myClubInvite(String clubId) async => null;
  @override
  Future<String?> myClubInviteRole(String clubId) async => null;
  @override
  Future<bool> myClubShare(String clubId) async => true;
  @override
  Future<List<ClubLeader>> clubLeaderboard(String clubId) async => const [];
  @override
  Future<String?> myClubRequest(String clubId) async => request;
  @override
  Future<List<ClubJoinRequest>> clubJoinRequests(String clubId) async => requests;
  @override
  Future<List<Club>> myClubs(String me) async => const [];
  @override
  Future<Map<String, String>> myClubRoles() async => const {};
  @override
  Future<List<Club>> clubs({String? query, int limit = 50}) async => [theClub];

  @override
  Future<bool> joinClub(String clubId) async {
    if (!theClub.isPublic) throw const PostgrestException(message: 'This club is private now. Ask to join instead.');
    joins++;
    member = true;
    return true;
  }

  @override
  Future<void> requestClubJoin(String clubId, String? message) async => request = 'pending';

  @override
  Future<void> setClubJoinPolicy(String clubId, String policy) async {
    policies.add(policy);
    theClub = _club(policy: policy);
  }
}

/// The club page on a 360 dp wide phone at [scale], signed in as [me].
Future<void> _pumpClub(WidgetTester t, _FakeCommunity repo, {required double scale, String me = _meId}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      communityRepositoryProvider.overrideWithValue(repo),
      currentUserIdProvider.overrideWith((ref) => me),
      postsWhereProvider((column: 'club_id', value: _clubId)).overrideWith((ref) async => const []),
    ],
    child: MaterialApp(
      theme: AppTheme.current,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: const ClubScreen(clubId: _clubId),
    ),
  ));
  await t.pumpAndSettle();
}

ChoiceCard _card(WidgetTester t, String key) => t.widget<ChoiceCard>(find.byKey(Key(key)));

void main() {
  for (final scale in const [1.0, 1.3]) {
    testWidgets('public club, not a member: Join club joins at once ($scale)', (t) async {
      final repo = _FakeCommunity(theClub: _club());
      await _pumpClub(t, repo, scale: scale);
      expect(find.descendant(of: find.byKey(const Key('club-join-label')), matching: find.text('Public club')), findsOneWidget);
      expect(find.text('Join club'), findsOneWidget);
      expect(find.text('Ask to join'), findsNothing);

      await t.tap(find.byKey(const Key('club-join')));
      await t.pumpAndSettle();
      expect(repo.joins, 1);
      expect(find.text("You're in. Welcome to Myvi Owners KL."), findsOneWidget);
      // The page reloads as a member.
      expect(find.text('Join club'), findsNothing);
      expect(find.text('Member'), findsOneWidget);
      expect(find.text('Show me on the club map'), findsOneWidget);
    });

    testWidgets('private club, not a member: Ask to join, then Requested ($scale)', (t) async {
      final repo = _FakeCommunity(theClub: _club(policy: 'private'));
      await _pumpClub(t, repo, scale: scale);
      expect(find.descendant(of: find.byKey(const Key('club-join-label')), matching: find.text('Private club')), findsOneWidget);
      expect(find.text('Ask to join'), findsOneWidget);
      expect(find.text('Join club'), findsNothing);

      await t.tap(find.byKey(const Key('club-ask')));
      await t.pumpAndSettle();
      expect(find.text('Send request'), findsOneWidget);
      await t.tap(find.text('Send request'));
      await t.pumpAndSettle();
      expect(repo.request, 'pending');
      expect(repo.joins, 0);
      expect(find.text('Requested'), findsOneWidget);
      expect(find.text('Ask to join'), findsNothing);
    });

    testWidgets('private club, already asked: Requested ($scale)', (t) async {
      await _pumpClub(t, _FakeCommunity(theClub: _club(policy: 'private'), request: 'pending'), scale: scale);
      expect(find.text('Requested'), findsOneWidget);
      expect(find.text('Ask to join'), findsNothing);
    });

    testWidgets('a public club ignores an old pending request: Join club ($scale)', (t) async {
      await _pumpClub(t, _FakeCommunity(theClub: _club(), request: 'pending'), scale: scale);
      expect(find.text('Join club'), findsOneWidget);
      expect(find.text('Requested'), findsNothing);
    });

    for (final policy in const ['public', 'private']) {
      testWidgets('$policy club, member: no join button ($scale)', (t) async {
        await _pumpClub(t, _FakeCommunity(theClub: _club(policy: policy), member: true), scale: scale);
        expect(find.text('Member'), findsOneWidget);
        expect(find.text('Join club'), findsNothing);
        expect(find.text('Ask to join'), findsNothing);
        expect(find.byKey(const Key('club-join-policy')), findsNothing); // members don't get the setting
      });
    }

    testWidgets('officer: who-can-join tile switches the club to private ($scale)', (t) async {
      final repo = _FakeCommunity(theClub: _club());
      await _pumpClub(t, repo, scale: scale, me: _ownerId);
      final tile = find.byKey(const Key('club-join-policy'));
      await t.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).first);
      await t.ensureVisible(tile);
      await t.pumpAndSettle();
      expect(find.descendant(of: tile, matching: find.text('Public club')), findsOneWidget);
      expect(find.text('Join club'), findsNothing);

      await t.tap(find.descendant(of: tile, matching: find.text('Change')));
      await t.pumpAndSettle();
      expect(find.text('Who can join'), findsOneWidget);
      expect(_card(t, 'club-join-public').selected, isTrue);
      expect(_card(t, 'club-join-private').selected, isFalse);

      await t.tap(find.byKey(const Key('club-join-private')));
      await t.pumpAndSettle();
      expect(repo.policies, ['private']);
      expect(find.text('Who can join'), findsNothing); // closed
      expect(find.text('Private club. People ask to join, you approve.'), findsOneWidget);
      expect(find.descendant(of: tile, matching: find.text('Private club')), findsOneWidget);
    });

    testWidgets('officer of a public club: old requests come with a note ($scale)', (t) async {
      final repo = _FakeCommunity(
        theClub: _club(),
        requests: [ClubJoinRequest(id: 'r1', userId: 'u2', createdAt: DateTime.now().subtract(const Duration(hours: 2)), username: 'mingshun', displayName: 'Ming Shun', message: 'Myvi daily, TTDI regular')],
      );
      await _pumpClub(t, repo, scale: scale, me: _ownerId);
      await t.scrollUntilVisible(find.text('Approve'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('WANT TO JOIN · 1'), findsOneWidget);
      expect(find.textContaining('Your club is public, so new people join right away.'), findsOneWidget);
    });

    testWidgets('officer of a private club: requests without the note ($scale)', (t) async {
      final repo = _FakeCommunity(
        theClub: _club(policy: 'private'),
        requests: [ClubJoinRequest(id: 'r1', userId: 'u2', createdAt: DateTime.now(), username: 'mingshun')],
      );
      await _pumpClub(t, repo, scale: scale, me: _ownerId);
      await t.scrollUntilVisible(find.text('Approve'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('WANT TO JOIN · 1'), findsOneWidget);
      expect(find.textContaining('Your club is public'), findsNothing);
    });

    testWidgets('new club: who can join starts on Public, Private can be picked ($scale)', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [myPartnerApplicationProvider(ApplicationKind.club).overrideWith((ref) async => null)],
        child: MaterialApp(
          theme: AppTheme.current,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: const CreateClubScreen(),
        ),
      ));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('club-join-private')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('WHO CAN JOIN'), findsOneWidget);
      expect(find.text('Anyone can join right away.'), findsOneWidget);
      expect(find.text('People ask to join, you approve.'), findsOneWidget);
      expect(_card(t, 'club-join-public').selected, isTrue);
      expect(_card(t, 'club-join-private').selected, isFalse);

      await t.ensureVisible(find.byKey(const Key('club-join-private')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('club-join-private')));
      await t.pump();
      expect(_card(t, 'club-join-public').selected, isFalse);
      expect(_card(t, 'club-join-private').selected, isTrue);
      await t.scrollUntilVisible(find.byKey(const Key('club-create-bottom')), 200, scrollable: find.byType(Scrollable).first);
    });
  }

  test('clubs read their join policy, public when the column is missing', () {
    Club parse(Map<String, dynamic> extra) =>
        Club.fromMap({'id': 'c', 'name': 'Crew', 'handle': 'crew', 'owner_id': 'o', 'created_at': '2026-09-01T00:00:00Z', ...extra});
    expect(parse({}).isPublic, isTrue);
    expect(parse({'join_policy': 'public'}).isPublic, isTrue);
    expect(parse({'join_policy': 'private'}).isPublic, isFalse);
  });
}
