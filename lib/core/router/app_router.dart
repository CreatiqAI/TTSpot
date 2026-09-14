import 'package:flutter/foundation.dart';
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
  static String club(String id) => '/club/$id';
  static String place(String id) => '/place/$id';
}

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
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: Routes.resetPassword, builder: (_, _) => const ResetPasswordScreen()),

      // Full-screen routes (no bottom nav)
      GoRoute(path: Routes.meets, builder: (_, _) => const MyEventsScreen()),
      GoRoute(path: Routes.createEvent, builder: (_, s) => CreateEventScreen(clubId: s.uri.queryParameters['club'])),
      GoRoute(
        path: '/event/:id',
        builder: (_, s) => EventDetailsScreen(eventId: s.pathParameters['id']!),
        routes: [
          GoRoute(path: 'live', builder: (_, s) => ConvoyLiveScreen(eventId: s.pathParameters['id']!)),
          GoRoute(path: 'qr', builder: (_, s) => EventQrScreen(eventId: s.pathParameters['id']!)),
        ],
      ),
      GoRoute(
        path: '/profile/:userId',
        builder: (_, s) => ProfileScreen(userId: s.pathParameters['userId']),
        routes: [
          GoRoute(path: 'followers', builder: (_, s) => FollowListScreen(userId: s.pathParameters['userId']!, followers: true)),
          GoRoute(path: 'following', builder: (_, s) => FollowListScreen(userId: s.pathParameters['userId']!, followers: false)),
          GoRoute(path: 'badges', builder: (_, s) => BadgesScreen(userId: s.pathParameters['userId']!)),
        ],
      ),
      GoRoute(path: Routes.editProfile, builder: (_, _) => const EditProfileScreen()),
      GoRoute(path: Routes.newCar, builder: (_, _) => const CarFormScreen()),
      GoRoute(
        path: '/car/:id',
        builder: (_, s) => CarDetailScreen(carId: s.pathParameters['id']!),
        routes: [
          GoRoute(path: 'edit', builder: (_, s) => CarFormScreen(carId: s.pathParameters['id']!)),
          GoRoute(path: 'mods/new', builder: (_, s) => CarModFormScreen(carId: s.pathParameters['id']!)),
        ],
      ),
      GoRoute(path: '/post/:id', builder: (_, s) => PostDetailScreen(postId: s.pathParameters['id']!)),
      GoRoute(
        path: '/create/post/:kind',
        builder: (_, s) => CreatePostScreen(
          kind: PostKind.fromDb(s.pathParameters['kind']!),
          eventId: s.uri.queryParameters['event'],
          carId: s.uri.queryParameters['car'],
          placeId: s.uri.queryParameters['place'],
          clubId: s.uri.queryParameters['club'],
          asClub: s.uri.queryParameters['as'] == 'club',
        ),
      ),
      GoRoute(
        path: Routes.createStory,
        builder: (_, s) => CreateStoryScreen(eventId: s.uri.queryParameters['event'], placeId: s.uri.queryParameters['place']),
      ),
      GoRoute(path: Routes.newAlbum, builder: (_, _) => const AlbumEditorScreen()),
      GoRoute(path: '/me/albums/:id/edit', builder: (_, s) => AlbumEditorScreen(albumId: s.pathParameters['id']!)),
      GoRoute(path: Routes.friends, builder: (_, _) => const FriendsScreen()),
      GoRoute(path: Routes.scan, builder: (_, _) => const ScanScreen()),
      GoRoute(path: Routes.myQr, builder: (_, _) => const MyQrScreen()),
      GoRoute(path: Routes.points, builder: (_, _) => const PointsScreen()),
      GoRoute(path: Routes.adminReview, builder: (_, _) => const AdminReviewScreen()),
      GoRoute(path: Routes.adminPartners, builder: (_, _) => const AdminPartnersScreen()),
      GoRoute(path: Routes.adminCommission, builder: (_, _) => const AdminCommissionScreen()),
      GoRoute(path: Routes.partnerApply, builder: (_, _) => const PartnerApplyScreen()),
      GoRoute(path: Routes.clubApply, builder: (_, _) => const PartnerApplyScreen(kind: ApplicationKind.club)),
      GoRoute(path: Routes.locationGate, builder: (_, _) => const LocationGateScreen()),
      GoRoute(path: Routes.vendor, builder: (_, _) => const VendorDashboardScreen()),
      GoRoute(path: Routes.vendorEdit, builder: (_, _) => const VendorEditScreen()),
      GoRoute(path: Routes.vendorReport, builder: (_, _) => const VendorReportScreen()),
      GoRoute(path: Routes.voucherNew, builder: (_, _) => const VoucherFormScreen()),
      GoRoute(path: '/vendor/voucher/:id/edit', builder: (_, s) => VoucherFormScreen(voucherId: s.pathParameters['id']!)),
      GoRoute(
        path: '/vendor/redeem/:claim',
        builder: (_, s) => RedeemScreen(claimId: s.pathParameters['claim']!, code: s.uri.queryParameters['code'] ?? ''),
      ),
      GoRoute(path: Routes.rewards, builder: (_, s) => RewardsScreen(initialTab: s.uri.queryParameters['tab'] == 'vouchers' ? 1 : 0)),
      GoRoute(path: '/voucher/:claim', builder: (_, s) => VoucherQrScreen(claimId: s.pathParameters['claim']!)),
      GoRoute(
        path: '/spot/:id/verify',
        builder: (_, s) => SpotVerifyScreen(placeId: s.pathParameters['id']!, code: s.uri.queryParameters['code'] ?? ''),
      ),
      GoRoute(path: Routes.activity, builder: (_, _) => const ActivityScreen()),
      GoRoute(
        path: Routes.stories,
        pageBuilder: (_, s) => CustomTransitionPage(
          child: StoryViewerScreen(args: s.extra as StoryViewerArgs),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
        ),
      ),
      GoRoute(path: Routes.search, builder: (_, _) => const SearchScreen()),
      GoRoute(path: '/chat/:id', builder: (_, s) => ChatScreen(conversationId: s.pathParameters['id']!)),
      GoRoute(path: Routes.saved, builder: (_, _) => const SavedPostsScreen()),
      GoRoute(path: Routes.createClub, builder: (_, _) => const CreateClubScreen()),
      GoRoute(path: '/club/:id', builder: (_, s) => ClubScreen(clubId: s.pathParameters['id']!)),
      GoRoute(path: '/place/:id', builder: (_, s) => PlaceScreen(placeId: s.pathParameters['id']!)),

      // Tabbed shell: Posts · Map · Chats · Me
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.explore, builder: (_, _) => const ExploreScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.map, builder: (_, _) => const MapScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.inbox, builder: (_, _) => const InboxScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.garage, builder: (_, _) => const MeTab())]),
        ],
      ),
    ],
  );
  return router;
});
