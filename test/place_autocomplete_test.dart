import 'dart:async';

import 'package:car_meet/core/places/place_autocomplete.dart';
import 'package:car_meet/core/places/places_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every request and lets the test answer each one when it likes.
class _FakeSearch {
  final calls = <({String q, String token})>[];
  final pending = <Completer<List<PlaceSuggestion>>>[];

  Future<List<PlaceSuggestion>> call(String q, String token) {
    calls.add((q: q, token: token));
    final c = Completer<List<PlaceSuggestion>>();
    pending.add(c);
    return c.future;
  }

  static List<PlaceSuggestion> results(String q) => [PlaceSuggestion(placeId: 'id-$q', main: q, secondary: 'Kuala Lumpur')];
}

void main() {
  const wait = Duration(milliseconds: 350);

  // testWidgets runs on a fake clock: pump(d) moves time on by d.
  testWidgets('waits for a pause in typing, then asks once for the latest text', (t) async {
    final f = _FakeSearch();
    final a = PlaceAutocomplete(f.call);
    addTearDown(a.dispose);
    a.onChanged('Ma');
    await t.pump(const Duration(milliseconds: 200));
    a.onChanged('Mam');
    await t.pump(const Duration(milliseconds: 200));
    a.onChanged('Mamak ');
    expect(f.calls, isEmpty);
    await t.pump(wait);
    expect(f.calls.map((c) => c.q), ['Mamak']); // trimmed, and only the last one
    expect(a.loading, isTrue);
    f.pending.single.complete(_FakeSearch.results('Mamak'));
    await t.pump();
    expect(a.loading, isFalse);
    expect(a.items.single.main, 'Mamak');
  });

  testWidgets('under two letters: no request, the list clears', (t) async {
    final f = _FakeSearch();
    final a = PlaceAutocomplete(f.call);
    addTearDown(a.dispose);
    a.onChanged('Pe');
    await t.pump(wait);
    f.pending.single.complete(_FakeSearch.results('Pe'));
    await t.pump();
    expect(a.items, hasLength(1));
    a.onChanged('P');
    await t.pump(wait);
    expect(f.calls, hasLength(1));
    expect(a.items, isEmpty);
    expect(a.loading, isFalse);
  });

  testWidgets('an answer for older text never replaces a newer one', (t) async {
    final f = _FakeSearch();
    final a = PlaceAutocomplete(f.call);
    addTearDown(a.dispose);
    a.onChanged('Petr');
    await t.pump(wait);
    a.onChanged('Petronas TTDI');
    await t.pump(wait);
    expect(f.calls.map((c) => c.q), ['Petr', 'Petronas TTDI']);
    f.pending[1].complete(_FakeSearch.results('Petronas TTDI'));
    await t.pump();
    f.pending[0].complete(_FakeSearch.results('Petr')); // late, slow network
    await t.pump();
    expect(a.items.single.main, 'Petronas TTDI');
    expect(a.loading, isFalse);
  });

  testWidgets('clearing the box drops what is still on its way', (t) async {
    final f = _FakeSearch();
    final a = PlaceAutocomplete(f.call);
    addTearDown(a.dispose);
    a.onChanged('Sunway');
    await t.pump(wait);
    a.clear();
    f.pending.single.complete(_FakeSearch.results('Sunway'));
    await t.pump();
    expect(a.items, isEmpty);
    expect(a.query, '');
  });

  testWidgets('one session token from the first keystroke to the pick, a new one after', (t) async {
    final f = _FakeSearch();
    final a = PlaceAutocomplete(f.call);
    addTearDown(a.dispose);
    a.onChanged('Bang');
    await t.pump(wait);
    a.onChanged('Bangsar');
    await t.pump(wait);
    for (final c in f.pending) {
      c.complete(_FakeSearch.results('Bangsar'));
    }
    await t.pump();
    final first = f.calls.first.token;
    expect(f.calls.map((c) => c.token).toSet(), {first});
    expect(first, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));

    // The pick hands back the same token for the details call and empties the list.
    expect(a.pick(), first);
    expect(a.items, isEmpty);
    a.finish();

    a.onChanged('Damansara');
    await t.pump(wait);
    expect(f.calls.last.token, isNot(first));
  });

  testWidgets('a pick stops a search that was about to start', (t) async {
    final f = _FakeSearch();
    final a = PlaceAutocomplete(f.call);
    addTearDown(a.dispose);
    a.onChanged('Gombak');
    a.pick();
    await t.pump(wait);
    expect(f.calls, isEmpty);
  });

  testWidgets('a failed search says so and shows nothing', (t) async {
    final f = _FakeSearch();
    final a = PlaceAutocomplete(f.call);
    addTearDown(a.dispose);
    a.onChanged('Setia Alam');
    await t.pump(wait);
    f.pending.single.completeError(Exception('offline'));
    await t.pump();
    expect(a.failed, isTrue);
    expect(a.items, isEmpty);
    expect(a.loading, isFalse);
    a.onChanged('Setia Alam ');
    expect(a.failed, isFalse); // typing again clears the note
    a.clear(); // no timer left running
  });

  testWidgets('no notifications after dispose', (t) async {
    final f = _FakeSearch();
    final a = PlaceAutocomplete(f.call);
    a.onChanged('Klang');
    await t.pump(wait);
    a.dispose();
    f.pending.single.complete(_FakeSearch.results('Klang'));
    await t.pump(); // would throw "used after being disposed" if it notified
  });
}
