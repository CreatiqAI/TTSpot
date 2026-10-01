import 'dart:async';

import 'package:flutter/foundation.dart';

import 'places_service.dart';

/// Fetches suggestions for [query] inside the search session [sessionToken].
typedef SuggestionFetcher = Future<List<PlaceSuggestion>> Function(String query, String sessionToken);

/// The brain of a "search a place" box, kept apart from the widget so it can
/// be tested: waits for a pause in typing ([debounce]) before asking, keeps
/// one session token from the first keystroke to the pick (Google bills the
/// session once), and drops any answer to a query that is no longer what the
/// box says.
///
/// Feed it every change with [onChanged]; listen for [items] / [loading].
/// When a suggestion is picked call [pick] for the token to resolve it with,
/// then [finish] once that details call is done.
class PlaceAutocomplete extends ChangeNotifier {
  PlaceAutocomplete(this._fetch, {this.debounce = const Duration(milliseconds: 350), this.minChars = 2, PlaceSession? session})
      : session = session ?? PlaceSession();

  final SuggestionFetcher _fetch;
  final Duration debounce;

  /// Shorter queries clear the list instead of asking.
  final int minChars;
  final PlaceSession session;

  List<PlaceSuggestion> _items = const [];
  bool _loading = false;
  bool _failed = false;
  String _query = '';
  Timer? _timer;
  int _seq = 0;
  bool _disposed = false;

  /// Suggestions for [query], best first.
  List<PlaceSuggestion> get items => _items;

  /// A request for the current query is out.
  bool get loading => _loading;

  /// The last request failed (offline, quota): the list is empty because of that.
  bool get failed => _failed;

  /// What was last typed, trimmed.
  String get query => _query;

  /// The box changed: restart the wait, or clear when it is too short.
  void onChanged(String text) {
    _timer?.cancel();
    _query = text.trim();
    _failed = false;
    if (_query.length < minChars) {
      _seq++; // an answer still on its way is for older text
      _update(items: const [], loading: false);
      return;
    }
    final q = _query;
    _timer = Timer(debounce, () => _search(q));
  }

  Future<void> _search(String q) async {
    final my = ++_seq;
    _update(loading: true);
    try {
      final r = await _fetch(q, session.token);
      if (my == _seq) _update(items: r, loading: false);
    } catch (_) {
      if (my == _seq) {
        _failed = true;
        _update(items: const [], loading: false);
      }
    }
  }

  /// A suggestion was picked: stop waiting for answers, empty the list and
  /// return the session token its details call must carry. Call [finish]
  /// after that call.
  String pick() {
    _timer?.cancel();
    _seq++;
    _update(items: const [], loading: false);
    return session.token;
  }

  /// The pick is resolved: the next keystroke opens a new session.
  void finish() => session.end();

  /// The box was emptied by hand.
  void clear() {
    _timer?.cancel();
    _seq++;
    _query = '';
    _failed = false;
    _update(items: const [], loading: false);
  }

  void _update({List<PlaceSuggestion>? items, bool? loading}) {
    if (_disposed) return;
    if (items != null) _items = items;
    if (loading != null) _loading = loading;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
