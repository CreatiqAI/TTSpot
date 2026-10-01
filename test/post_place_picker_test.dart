import 'package:car_meet/core/places/places_service.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/social/data/community_repository.dart';
import 'package:car_meet/features/social/domain/club.dart';
import 'package:car_meet/features/social/domain/post_place.dart';
import 'package:car_meet/features/social/presentation/widgets/post_place_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the fake search was asked, and with which session tokens.
final _asked = <String>[];
final _tokens = <String?>[];

class _FakePlaces extends PlacesService {
  _FakePlaces(super.ref);

  @override
  Future<List<PlaceSuggestion>> autocomplete(String input, {double? lat, double? lng, String? sessionToken}) async {
    _asked.add(input);
    _tokens.add(sessionToken);
    return const [
      PlaceSuggestion(placeId: 'g-mamak', main: 'Mamak Sri Melur', secondary: 'Jalan Datuk Sulaiman, Taman Tun Dr Ismail, Kuala Lumpur'),
      PlaceSuggestion(placeId: 'g-shell', main: 'Shell Taman Tun Dr Ismail', secondary: 'Jalan Burhanuddin Helmi, Taman Tun Dr Ismail, Kuala Lumpur'),
    ];
  }

  @override
  Future<PlaceDetails> details(String placeId, {String? sessionToken}) async {
    _tokens.add(sessionToken);
    return PlaceDetails(placeId: placeId, name: 'Shell Taman Tun Dr Ismail', address: 'Jalan Burhanuddin Helmi, Taman Tun Dr Ismail, 60000 Kuala Lumpur, Malaysia', lat: 3.14, lng: 101.63);
  }
}

class _FakeCommunity extends CommunityRepository {
  // Never called; no token refresh timer left running.
  _FakeCommunity() : super(SupabaseClient('http://localhost', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false)));

  @override
  Future<List<Place>> searchSpots(String query, {int limit = 3}) async =>
      [Place(id: 'spot-1', name: 'Mamak Sri Melur', kind: 'mamak', lat: 3.139, lng: 101.629, createdAt: DateTime(2026))];

  @override
  Future<List<Place>> nearestSpots({required double lat, required double lng, int limit = 5}) async => const [];
}

void main() {
  setUp(() {
    _asked.clear();
    _tokens.clear();
  });

  Future<ValueNotifier<PostPlace?>> pump(WidgetTester t, {double textScale = 1.0}) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    final value = ValueNotifier<PostPlace?>(null);
    addTearDown(value.dispose);
    await t.pumpWidget(ProviderScope(
      overrides: [
        placesServiceProvider.overrideWith(_FakePlaces.new),
        communityRepositoryProvider.overrideWithValue(_FakeCommunity()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(size: const Size(411, 914), textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<PostPlace?>(
                valueListenable: value,
                builder: (_, v, _) => PostPlacePicker(value: v, onChanged: (p) => value.value = p),
              ),
            ),
          ),
        ),
      ),
    ));
    return value;
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('type, see spots first then addresses, pick one, remove it (text x$scale)', (t) async {
      final value = await pump(t, textScale: scale);
      expect(find.text('Use my location'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'Mamak');
      await t.pump(const Duration(milliseconds: 100));
      expect(_asked, isEmpty); // still typing
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 250)); // the list slides open
      expect(_asked, ['Mamak']);
      // Our spot first; the same name from the search is not listed twice.
      expect(find.text('Mamak Sri Melur'), findsOneWidget);
      expect(find.text('TT Spot'), findsOneWidget);
      expect(find.text('Shell Taman Tun Dr Ismail'), findsOneWidget);
      expect(t.takeException(), isNull);

      // A search pick resolves with the same session token, and becomes the chip.
      await t.tap(find.text('Shell Taman Tun Dr Ismail'));
      await t.pumpAndSettle();
      expect(_tokens.toSet(), hasLength(1));
      expect(value.value?.name, 'Shell Taman Tun Dr Ismail');
      expect(value.value?.lat, 3.14);
      expect(value.value?.isSpot, isFalse);
      expect(find.byTooltip('Remove place'), findsOneWidget);
      expect(find.text('Jalan Burhanuddin Helmi, Taman Tun Dr Ismail'), findsOneWidget); // short address
      expect(find.byType(TextField), findsNothing);
      expect(t.takeException(), isNull);

      await t.tap(find.byTooltip('Remove place'));
      await t.pumpAndSettle();
      expect(value.value, isNull);
      expect(find.byType(TextField), findsOneWidget);
    });
  }

  testWidgets('picking a TT Spot links it without a details lookup', (t) async {
    final value = await pump(t);
    await t.enterText(find.byType(TextField), 'Sri Melur');
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 250)); // the list slides open
    await t.tap(find.text('TT Spot'));
    await t.pumpAndSettle();
    expect(value.value?.spotId, 'spot-1');
    expect(_tokens, hasLength(1)); // the autocomplete only
  });
}
