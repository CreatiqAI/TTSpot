import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/events/presentation/convoy_live_screen.dart';
import '../../features/events/presentation/create_event_screen.dart';
import '../../features/events/presentation/event_details_screen.dart';
import '../../features/events/presentation/my_events_screen.dart';
import '../../features/friends/presentation/friends_screen.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/profile/presentation/badges_screen.dart';
import '../../features/profile/presentation/car_detail_screen.dart';
import '../../features/profile/presentation/car_form_screen.dart';
import '../../features/profile/presentation/car_mod_form_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/follow_list_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/social/domain/post.dart';
import '../../features/social/presentation/activity_screen.dart';
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
import '../supabase/supabase_client.dart';
import 'app_shell.dart';

/// All route paths in one place so screens never hard-code strings.
abstract final class Routes {
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';

  // Shell tabs: Posts · Map · Chats · Me
  static const explore = '/posts';
  static const map = '/map';
  static const inbox = '/chats';
  static const garage = '/me';

  // Full-screen
  static const meets = '/meets';
  static const activity = '/activity';
  static const friends = '/friends';

  // Full-screen
  static const createEvent = '/create-event';
  static const editProfile = '/edit-profile';
  static const newCar = '/car/new';
  static const search = '/search';
  static const saved = '/saved';
  static const stories = '/stories';
  static const createStory = '/create/story';
  static const createClub = '/create/club';
  static const clubs = '/clubs';

  static String event(String id) => '/event/$id';
  static String convoy(String eventId) => '/event/$eventId/live';
  static String profile(String userId) => '/profile/$userId';
  static String followers(String userId) => '/profile/$userId/followers';
  static String following(String userId) => '/profile/$userId/following';
  static String badges(String userId) => '/profile/$userId/badges';
  static String car(String id) => '/car/$id';
  static String editCar(String id) => '/car/$id/edit';
  static String newCarMod(String carId) => '/car/$carId/mods/new';
  static String post(String id) => '/post/$id';
  static String createPost(PostKind kind, {String? eventId, String? carId, String? placeId, String? clubId}) {
    final q = <String, String>{
      'event': ?eventId,
      'car': ?carId,
      'place': ?placeId,
      'club': ?clubId,
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
  ref.listen(authStateProvider, (_, _) => refresh.poke());
  ref.listen(currentProfileProvider, (_, _) => refresh.poke());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.map,
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final signedIn = ref.read(currentUserIdProvider) != null;
      final path = state.uri.path;
      final onAuthPage = path == Routes.signIn;

      if (!signedIn) return onAuthPage ? null : Routes.signIn;

      final profile = ref.read(currentProfileProvider);
      if (profile.isLoading) return null;
      final onboarded = profile.value?.isOnboarded ?? false;

      final needsCar = profile.value?.needsCar ?? false;
      if (!onboarded || needsCar) return path == Routes.onboarding ? null : Routes.onboarding;
      if (onAuthPage || path == Routes.onboarding) return Routes.map;
      return null;
    },
    routes: [
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),

      // Full-screen routes (no bottom nav)
      GoRoute(path: Routes.meets, builder: (_, _) => const MyEventsScreen()),
      GoRoute(path: Routes.createEvent, builder: (_, _) => const CreateEventScreen()),
      GoRoute(
        path: '/event/:id',
        builder: (_, s) => EventDetailsScreen(eventId: s.pathParameters['id']!),
        routes: [
          GoRoute(path: 'live', builder: (_, s) => ConvoyLiveScreen(eventId: s.pathParameters['id']!)),
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
        ),
      ),
      GoRoute(
        path: Routes.createStory,
        builder: (_, s) => CreateStoryScreen(eventId: s.uri.queryParameters['event'], placeId: s.uri.queryParameters['place']),
      ),
      GoRoute(path: Routes.friends, builder: (_, _) => const FriendsScreen()),
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
          StatefulShellBranch(routes: [GoRoute(path: Routes.garage, builder: (_, _) => const ProfileScreen())]),
        ],
      ),
    ],
  );
});
