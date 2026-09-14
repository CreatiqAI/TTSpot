import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialPage;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/events/presentation/convoy_live_screen.dart';
import '../../features/events/presentation/create_event_screen.dart';
import '../../features/events/presentation/event_details_screen.dart';
import '../../features/events/presentation/my_events_screen.dart';
import '../../features/friends/presentation/friends_screen.dart';
import '../../features/points/presentation/admin_review_screen.dart';
import '../../features/vendors/presentation/admin_commission_screen.dart';
import '../../features/vendors/presentation/admin_partners_screen.dart';
import '../../features/vendors/domain/vendor.dart';
import '../../features/vendors/presentation/partner_apply_screen.dart';
import '../../features/vendors/presentation/redeem_screen.dart';
import '../../features/vendors/presentation/rewards_screen.dart';
import '../../features/vendors/presentation/vendor_dashboard_screen.dart';
import '../../features/vendors/presentation/vendor_edit_screen.dart';
import '../../features/vendors/presentation/vendor_report_screen.dart';
import '../../features/vendors/presentation/voucher_form_screen.dart';
import '../../features/vendors/presentation/voucher_qr_screen.dart';
import '../../features/points/presentation/event_qr_screen.dart';
import '../../features/points/presentation/my_qr_screen.dart';
import '../../features/points/presentation/points_screen.dart';
import '../../features/points/presentation/scan_screen.dart';
import '../../features/points/presentation/spot_verify_screen.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/profile/presentation/badges_screen.dart';
import '../../features/profile/presentation/car_detail_screen.dart';
import '../../features/profile/presentation/car_form_screen.dart';
import '../../features/profile/presentation/car_mod_form_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/follow_list_screen.dart';
import '../../features/accounts/presentation/me_tab.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/social/domain/post.dart';
import '../../features/social/presentation/activity_screen.dart';
import '../../features/social/presentation/album_editor_screen.dart';
import '../../features/social/presentation/my_moments_screen.dart';
import '../../features/social/presentation/chat_info_screen.dart';
import '../../features/social/presentation/chat_screen.dart';
import '../../features/social/presentation/club_screen.dart';
import '../../features/social/presentation/create_club_screen.dart';
import '../../features/social/presentation/create_post_screen.dart';
import '../../features/social/presentation/create_story_screen.dart';
import '../../features/social/presentation/explore_screen.dart';
import '../../features/social/presentation/inbox_screen.dart';
import '../../features/social/presentation/place_screen.dart';
import '../../features/social/presentation/post_detail_screen.dart';
import '../../features/social/presentation/saved_posts_screen.dart';
import '../../features/social/presentation/search_screen.dart';
import '../../features/social/presentation/story_viewer_screen.dart';
import '../location/location_gate.dart';
import '../supabase/supabase_client.dart';
import 'app_shell.dart';

/// All route paths in one place so screens never hard-code strings.
abstract final class Routes {
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';
  static const resetPassword = '/reset-password';

  // Shell tabs: Posts · Map · Chats · Me
  static const explore = '/posts';
  static const map = '/map';
  static const inbox = '/chats';
  static const garage = '/me';

  // Full-screen
  static const meets = '/meets';
  static const activity = '/activity';
  static const friends = '/friends';
  static const scan = '/scan';
  static const myQr = '/me/qr';
  static const points = '/me/points';
  static const adminReview = '/admin/review';
  static const adminPartners = '/admin/partners';
  static const adminCommission = '/admin/commission';

  // Partners (vendors) + rewards
  static const partnerApply = '/partner/apply';
  static const clubApply = '/club/apply';
  static const locationGate = '/location';
  static const vendor = '/vendor';
  static const vendorEdit = '/vendor/edit';
  static const vendorReport = '/vendor/report';
  static const voucherNew = '/vendor/voucher/new';
  static String voucherEdit(String id) => '/vendor/voucher/$id/edit';
  static String redeem(String claimId, String code) => '/vendor/redeem/$claimId?code=$code';
  static const rewards = '/rewards';
  static const myVouchers = '/rewards?tab=vouchers';
  static String voucherQr(String claimId) => '/voucher/$claimId';

  // Full-screen
  static const createEvent = '/create-event';
  static String createEventAs({String? clubId}) => clubId == null ? createEvent : '$createEvent?club=$clubId';
  static const editProfile = '/edit-profile';
  static const newCar = '/car/new';
  static const search = '/search';
  static const saved = '/saved';
  static const stories = '/stories';
  static const createStory = '/create/story';
  static const createClub = '/create/club';
  static const newAlbum = '/me/albums/new';
  static String newAlbumWith(String storyId) => '/me/albums/new?with=$storyId';
  static const myMoments = '/me/moments';
  static String editAlbum(String id) => '/me/albums/$id/edit';
  static const clubs = '/clubs';

  static String event(String id) => '/event/$id';
  static String convoy(String eventId) => '/event/$eventId/live';
  static String eventQr(String eventId) => '/event/$eventId/qr';
  static String profile(String userId) => '/profile/$userId';
  static String followers(String userId) => '/profile/$userId/followers';
  static String following(String userId) => '/profile/$userId/following';
  static String badges(String userId) => '/profile/$userId/badges';
  static String car(String id) => '/car/$id';
  static String editCar(String id) => '/car/$id/edit';
  static String newCarMod(String carId) => '/car/$carId/mods/new';
  static String post(String id) => '/post/$id';
  static String createPost(PostKind kind, {String? eventId, String? carId, String? placeId, String? clubId, bool asClub = false}) {
    final q = <String, String>{
      'event': ?eventId,
      'car': ?carId,
      'place': ?placeId,
      'club': ?clubId,
      if (asClub && clubId != null) 'as': 'club',
    };
    return Uri(path: '/create/post/${kind.db}', queryParameters: q.isEmpty ? null : q).toString();
  }

  /// A moment tagged to the meet / place it was taken at.
  static String createMoment({String? eventId, String? placeId}) {
    final q = <String, String>{'event': ?eventId, 'place': ?placeId};
    return Uri(path: createStory, queryParameters: q.isEmpty ? null : q).toString();
  }

  static String chat(String conversationId) => '/chat/$conversationId';
  static String chatInfo(String conversationId) => '/chat/$conversationId/info';
  static String club(String id) => '/club/$id';
  static String place(String id) => '/place/$id';
}

/// Explicit Material page for every route. go_router 18 only recognises
/// `package:material_ui`'s MaterialApp, not `package:flutter/material.dart`'s,
/// so left to itself it builds NoTransitionPages: no slide, no iOS swipe-back.
Page<void> page(GoRouterState s, Widget child) => MaterialPage<void>(key: s.pageKey, name: s.name ?? s.path, child: child);

/// Pokes GoRouter to re-run `redirect` whenever auth or profile state changes.
class _RouterRefresh extends ChangeNotifier {
  void poke() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  late final GoRouter router;
  ref.listen(authStateProvider, (_, next) {
    refresh.poke();
    // The reset link signs the member in and fires this event: go set a new password.
    if (next.value?.event == AuthChangeEvent.passwordRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) => router.go(Routes.resetPassword));
    }
  });
  ref.listen(currentProfileProvider, (_, _) => refresh.poke());
  ref.listen(locationGrantedProvider, (_, _) => refresh.poke());
  ref.listen(locationGateSkippedProvider, (_, _) => refresh.poke());
  ref.onDispose(refresh.dispose);

  router = GoRouter(
    initialLocation: Routes.map,
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final signedIn = ref.read(currentUserIdProvider) != null;
      final path = state.uri.path;
      final onAuthPage = path == Routes.signIn;

      if (!signedIn) return onAuthPage ? null : Routes.signIn;
      if (path == Routes.resetPassword) return null;

      final profile = ref.read(currentProfileProvider);
      if (profile.isLoading) return null;
      final onboarded = profile.value?.isOnboarded ?? false;

      final needsCar = profile.value?.needsCar ?? false;
      if (!onboarded || needsCar) return path == Routes.onboarding ? null : Routes.onboarding;

      // Location first: the app is a map. Ask once per launch, with context.
      final granted = ref.read(locationGrantedProvider);
      final skipped = ref.read(locationGateSkippedProvider);
      if (granted.hasValue && !granted.value! && !skipped) return path == Routes.locationGate ? null : Routes.locationGate;

      if (onAuthPage || path == Routes.onboarding || path == Routes.locationGate) return Routes.map;
      return null;
    },
    routes: [
      GoRoute(path: Routes.signIn, pageBuilder: (_, s) => page(s, const SignInScreen())),
      GoRoute(path: Routes.onboarding, pageBuilder: (_, s) => page(s, const OnboardingScreen())),
      GoRoute(path: Routes.resetPassword, pageBuilder: (_, s) => page(s, const ResetPasswordScreen())),

      // Full-screen routes (no bottom nav)
      GoRoute(path: Routes.meets, pageBuilder: (_, s) => page(s, const MyEventsScreen())),
      GoRoute(path: Routes.createEvent, pageBuilder: (_, s) => page(s, CreateEventScreen(clubId: s.uri.queryParameters['club']))),
      GoRoute(
        path: '/event/:id',
        pageBuilder: (_, s) => page(s, EventDetailsScreen(eventId: s.pathParameters['id']!)),
        routes: [
          GoRoute(path: 'live', pageBuilder: (_, s) => page(s, ConvoyLiveScreen(eventId: s.pathParameters['id']!))),
          GoRoute(path: 'qr', pageBuilder: (_, s) => page(s, EventQrScreen(eventId: s.pathParameters['id']!))),
        ],
      ),
      GoRoute(
        path: '/profile/:userId',
        pageBuilder: (_, s) => page(s, ProfileScreen(userId: s.pathParameters['userId'])),
        routes: [
          GoRoute(path: 'followers', pageBuilder: (_, s) => page(s, FollowListScreen(userId: s.pathParameters['userId']!, followers: true))),
          GoRoute(path: 'following', pageBuilder: (_, s) => page(s, FollowListScreen(userId: s.pathParameters['userId']!, followers: false))),
          GoRoute(path: 'badges', pageBuilder: (_, s) => page(s, BadgesScreen(userId: s.pathParameters['userId']!))),
        ],
      ),
      GoRoute(path: Routes.editProfile, pageBuilder: (_, s) => page(s, const EditProfileScreen())),
      GoRoute(path: Routes.newCar, pageBuilder: (_, s) => page(s, const CarFormScreen())),
      GoRoute(
        path: '/car/:id',
        pageBuilder: (_, s) => page(s, CarDetailScreen(carId: s.pathParameters['id']!)),
        routes: [
          GoRoute(path: 'edit', pageBuilder: (_, s) => page(s, CarFormScreen(carId: s.pathParameters['id']!))),
          GoRoute(path: 'mods/new', pageBuilder: (_, s) => page(s, CarModFormScreen(carId: s.pathParameters['id']!))),
        ],
      ),
      GoRoute(path: '/post/:id', pageBuilder: (_, s) => page(s, PostDetailScreen(postId: s.pathParameters['id']!))),
      GoRoute(
        path: '/create/post/:kind',
        pageBuilder: (_, s) => page(s, CreatePostScreen(
          kind: PostKind.fromDb(s.pathParameters['kind']!),
          eventId: s.uri.queryParameters['event'],
          carId: s.uri.queryParameters['car'],
          placeId: s.uri.queryParameters['place'],
          clubId: s.uri.queryParameters['club'],
          asClub: s.uri.queryParameters['as'] == 'club',
        )),
      ),
      GoRoute(
        path: Routes.createStory,
        pageBuilder: (_, s) => page(s, CreateStoryScreen(eventId: s.uri.queryParameters['event'], placeId: s.uri.queryParameters['place'])),
      ),
      GoRoute(path: Routes.newAlbum, pageBuilder: (_, s) => page(s, AlbumEditorScreen(preselect: s.uri.queryParameters['with']))),
      GoRoute(path: Routes.myMoments, pageBuilder: (_, s) => page(s, const MyMomentsScreen())),
      GoRoute(path: '/me/albums/:id/edit', pageBuilder: (_, s) => page(s, AlbumEditorScreen(albumId: s.pathParameters['id']!))),
      GoRoute(path: Routes.friends, pageBuilder: (_, s) => page(s, const FriendsScreen())),
      GoRoute(path: Routes.scan, pageBuilder: (_, s) => page(s, const ScanScreen())),
      GoRoute(path: Routes.myQr, pageBuilder: (_, s) => page(s, const MyQrScreen())),
      GoRoute(path: Routes.points, pageBuilder: (_, s) => page(s, const PointsScreen())),
      GoRoute(path: Routes.adminReview, pageBuilder: (_, s) => page(s, const AdminReviewScreen())),
      GoRoute(path: Routes.adminPartners, pageBuilder: (_, s) => page(s, const AdminPartnersScreen())),
      GoRoute(path: Routes.adminCommission, pageBuilder: (_, s) => page(s, const AdminCommissionScreen())),
      GoRoute(path: Routes.partnerApply, pageBuilder: (_, s) => page(s, const PartnerApplyScreen())),
      GoRoute(path: Routes.clubApply, pageBuilder: (_, s) => page(s, const PartnerApplyScreen(kind: ApplicationKind.club))),
      GoRoute(path: Routes.locationGate, pageBuilder: (_, s) => page(s, const LocationGateScreen())),
      GoRoute(path: Routes.vendor, pageBuilder: (_, s) => page(s, const VendorDashboardScreen())),
      GoRoute(path: Routes.vendorEdit, pageBuilder: (_, s) => page(s, const VendorEditScreen())),
      GoRoute(path: Routes.vendorReport, pageBuilder: (_, s) => page(s, const VendorReportScreen())),
      GoRoute(path: Routes.voucherNew, pageBuilder: (_, s) => page(s, const VoucherFormScreen())),
      GoRoute(path: '/vendor/voucher/:id/edit', pageBuilder: (_, s) => page(s, VoucherFormScreen(voucherId: s.pathParameters['id']!))),
      GoRoute(
        path: '/vendor/redeem/:claim',
        pageBuilder: (_, s) => page(s, RedeemScreen(claimId: s.pathParameters['claim']!, code: s.uri.queryParameters['code'] ?? '')),
      ),
      GoRoute(path: Routes.rewards, pageBuilder: (_, s) => page(s, RewardsScreen(initialTab: s.uri.queryParameters['tab'] == 'vouchers' ? 1 : 0))),
      GoRoute(path: '/voucher/:claim', pageBuilder: (_, s) => page(s, VoucherQrScreen(claimId: s.pathParameters['claim']!))),
      GoRoute(
        path: '/spot/:id/verify',
        pageBuilder: (_, s) => page(s, SpotVerifyScreen(placeId: s.pathParameters['id']!, code: s.uri.queryParameters['code'] ?? '')),
      ),
      GoRoute(path: Routes.activity, pageBuilder: (_, s) => page(s, const ActivityScreen())),
      GoRoute(
        path: Routes.stories,
        pageBuilder: (_, s) => CustomTransitionPage(
          child: StoryViewerScreen(args: s.extra as StoryViewerArgs),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
        ),
      ),
      GoRoute(path: Routes.search, pageBuilder: (_, s) => page(s, const SearchScreen())),
      GoRoute(
        path: '/chat/:id',
        pageBuilder: (_, s) => page(s, ChatScreen(conversationId: s.pathParameters['id']!)),
        routes: [GoRoute(path: 'info', pageBuilder: (_, s) => page(s, ChatInfoScreen(conversationId: s.pathParameters['id']!)))],
      ),
      GoRoute(path: Routes.saved, pageBuilder: (_, s) => page(s, const SavedPostsScreen())),
      GoRoute(path: Routes.createClub, pageBuilder: (_, s) => page(s, const CreateClubScreen())),
      GoRoute(path: '/club/:id', pageBuilder: (_, s) => page(s, ClubScreen(clubId: s.pathParameters['id']!))),
      GoRoute(path: '/place/:id', pageBuilder: (_, s) => page(s, PlaceScreen(placeId: s.pathParameters['id']!))),

      // Tabbed shell: Posts · Map · Chats · Me
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.explore, pageBuilder: (_, s) => page(s, const ExploreScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.map, pageBuilder: (_, s) => page(s, const MapScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.inbox, pageBuilder: (_, s) => page(s, const InboxScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.garage, pageBuilder: (_, s) => page(s, const MeTab()))]),
        ],
      ),
    ],
  );
  return router;
});
