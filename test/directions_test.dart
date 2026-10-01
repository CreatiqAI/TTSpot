import 'package:car_meet/core/directions/directions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const waze = DirectionsApp.waze, google = DirectionsApp.google, apple = DirectionsApp.apple;

  DirectionsPlan plan(String? saved, Set<DirectionsApp> installed, {bool iOS = false, bool choose = false}) =>
      planDirections(saved: saved, installed: installed, iOS: iOS, choose: choose);

  group('planDirections: remembered app', () {
    test('first use (nothing saved): chooser with the installed apps', () {
      final p = plan(null, {waze, google});
      expect(p.open, isNull);
      expect(p.options, [waze, google]);
      expect(p.web, isFalse);
      expect(p.missing, isNull);
    });

    test('"ask" behaves like nothing saved', () {
      expect(plan(kDirectionsAsk, {google}).options, [google]);
      expect(plan(kDirectionsAsk, {google}).open, isNull);
    });

    test('a remembered, installed app opens straight away', () {
      expect(plan('waze', {waze, google}).open, waze);
      expect(plan('google', {waze, google}).open, google);
      expect(plan('apple', {waze, apple}, iOS: true).open, apple);
    });

    test('long-press (choose) always shows the chooser, even with a remembered app', () {
      final p = plan('waze', {waze, google}, choose: true);
      expect(p.open, isNull);
      expect(p.options, [waze, google]);
      expect(p.missing, isNull);
    });

    test('remembered app no longer installed: chooser that says so', () {
      final p = plan('waze', {google});
      expect(p.open, isNull);
      expect(p.options, [google]);
      expect(p.missing, waze);
    });

    test('Apple Maps saved on an iPhone is ignored on Android', () {
      final p = plan('apple', {waze, google});
      expect(p.open, isNull);
      expect(p.options, [waze, google]);
      expect(p.missing, isNull);
    });

    test('an unknown saved value falls back to the chooser', () {
      expect(plan('in_app', {waze}).open, isNull);
      expect(plan('in_app', {waze}).options, [waze]);
    });
  });

  group('planDirections: platforms and fallbacks', () {
    test('Apple Maps is offered on iPhone only, last', () {
      expect(plan(null, {waze, google, apple}, iOS: true).options, [waze, google, apple]);
      expect(plan(null, {waze, google, apple}).options, [waze, google]);
    });

    test('nothing installed: Waze and Google Maps as web links', () {
      final p = plan(null, const {});
      expect(p.web, isTrue);
      expect(p.options, [waze, google]);
    });

    test('nothing installed with a remembered app: web links, flagged missing', () {
      final p = plan('google', const {});
      expect(p.open, isNull);
      expect(p.web, isTrue);
      expect(p.missing, google);
    });
  });

  group('directionsUrls', () {
    test('Waze: app scheme with navigate, web fallback', () {
      final u = directionsUrls(waze, 3.1, 101.6, iOS: false);
      expect(u.app, 'waze://?ll=3.1,101.6&navigate=yes');
      expect(u.web, 'https://waze.com/ul?ll=3.1,101.6&navigate=yes');
    });

    test('Google Maps: platform scheme, web fallback', () {
      expect(directionsUrls(google, 3.1, 101.6, iOS: true).app, startsWith('comgooglemaps://?daddr=3.1,101.6'));
      expect(directionsUrls(google, 3.1, 101.6, iOS: false).app, 'google.navigation:q=3.1,101.6&mode=d');
      expect(directionsUrls(google, 3.1, 101.6, iOS: false).web, contains('destination=3.1,101.6'));
    });

    test('Apple Maps: the maps.apple.com link only', () {
      final u = directionsUrls(apple, 3.1, 101.6, iOS: true);
      expect(u.app, isNull);
      expect(u.web, 'https://maps.apple.com/?daddr=3.1,101.6&dirflg=d');
    });
  });

  test('keys round-trip', () {
    for (final a in DirectionsApp.values) {
      expect(DirectionsApp.fromKey(a.key), a);
    }
    expect(DirectionsApp.fromKey(kDirectionsAsk), isNull);
    expect(DirectionsApp.fromKey(null), isNull);
  });
}
