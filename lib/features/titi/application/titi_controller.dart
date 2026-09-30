import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/geo/latlng.dart';
import '../../../core/location/live_position.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../data/titi_repository.dart';
import '../domain/titi_message.dart';

/// The chat with TiTi as the screen draws it.
class TitiState {
  const TitiState({
    this.sessionId,
    this.title,
    this.view = 0,
    this.messages = const [],
    this.base = 0,
    this.loading = true,
    this.loadError,
    this.streaming = false,
    this.thinking = false,
  });

  /// The open chat; null for a new one until its first answer starts.
  final String? sessionId;
  final String? title;

  /// Bumped whenever another chat opens (or a new one starts), so the screen
  /// starts a fresh list at the bottom. Not bumped when a new chat gets its id.
  final int view;

  /// Oldest first. While streaming, the last one is the answer being written.
  final List<TitiMessage> messages;

  /// How many of [messages] were loaded when the chat opened; the rest arrived
  /// since. The screen anchors the list between the two, so new words grow
  /// downwards without moving what was already there.
  final int base;

  /// History is loading (first open).
  final bool loading;
  final String? loadError;

  /// An answer is on its way; sending is off, Stop is on.
  final bool streaming;

  /// Waiting for words (the app bar says "Thinking…").
  final bool thinking;

  TitiState copyWith({
    String? sessionId,
    String? title,
    List<TitiMessage>? messages,
    bool? loading,
    String? loadError,
    bool? streaming,
    bool? thinking,
  }) =>
      TitiState(
        sessionId: sessionId ?? this.sessionId,
        title: title ?? this.title,
        view: view,
        messages: messages ?? this.messages,
        base: base,
        loading: loading ?? this.loading,
        loadError: loadError,
        streaming: streaming ?? this.streaming,
        thinking: thinking ?? this.thinking,
      );
}

/// My chats with TiTi, latest first. Invalidated when one starts, gets its
/// title or is deleted.
final titiSessionsProvider = FutureProvider.autoDispose<List<TitiSession>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(titiRepositoryProvider).sessions();
});

/// Sends questions (with photos), streams answers, switches chats. Lives as
/// long as the app (not the screen), so an answer keeps coming if you step
/// away mid-way, and TiTi reopens where you left off.
class TitiController extends Notifier<TitiState> {
  StreamSubscription<TitiEvent>? _sub;
  var _seq = 0;
  var _view = 0;

  // The answer being written.
  TitiLive? _live;
  String? _error;

  @override
  TitiState build() {
    ref.watch(currentUserIdProvider); // a new account starts fresh
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(openLatest);
    return const TitiState();
  }

  TitiRepository get _repo => ref.read(titiRepositoryProvider);

  /// The latest chat, or a new one when there is none. Where the Chats row
  /// and "Ask TiTi" land.
  Future<void> openLatest() async {
    if (state.streaming) return;
    state = TitiState(view: ++_view);
    try {
      final list = await _repo.sessions(limit: 1);
      if (list.isEmpty) {
        state = TitiState(view: _view, loading: false);
      } else {
        await open(list.first.id, title: list.first.title);
      }
    } catch (e) {
      state = TitiState(view: _view, loading: false, loadError: friendlyError(e));
    }
  }

  /// The screen opens (Chats row, "Ask TiTi"): back to the latest chat if
  /// another one is showing. Leaves an answer that is still coming alone.
  Future<void> ensureLatest() async {
    if (state.streaming || state.loading) return;
    try {
      final list = await _repo.sessions(limit: 1);
      if (list.isEmpty || list.first.id == state.sessionId || state.streaming) return;
      await open(list.first.id, title: list.first.title);
    } catch (_) {
      // Offline: stay on what's showing.
    }
  }

  /// Opens a chat. An answer still coming in stops (the server saves it).
  Future<void> open(String id, {String? title}) async {
    stop();
    final view = ++_view;
    state = TitiState(sessionId: id, title: title, view: view);
    try {
      final list = await _repo.history(id);
      if (state.view != view) return; // another chat opened meanwhile
      state = TitiState(sessionId: id, title: title, view: view, messages: list, base: list.length, loading: false);
    } catch (e) {
      if (state.view == view) state = TitiState(sessionId: id, title: title, view: view, loading: false, loadError: friendlyError(e));
    }
  }

  /// Reloads the open chat (after a failed load).
  Future<void> reload() async {
    final id = state.sessionId;
    if (id == null) return openLatest();
    return open(id, title: state.title);
  }

  /// A clean page; the chat itself is made with the first question.
  void newChat() {
    stop();
    state = TitiState(view: ++_view, loading: false);
  }

  /// Deletes a chat and its photos. Deleting the open one opens the latest left.
  Future<void> deleteSession(String id) async {
    await _repo.deleteSession(id);
    ref.invalidate(titiSessionsProvider);
    if (state.sessionId == id) await openLatest();
  }

  /// Ask something, with up to 4 photos. Ignored while an answer is coming.
  Future<void> send(String text, {List<XFile> photos = const []}) async {
    final q = text.trim();
    if ((q.isEmpty && photos.isEmpty) || state.streaming) return;
    final images = [for (final f in photos) TitiImage(bytes: await f.readAsBytes())];
    final mine = TitiMessage(key: 'local-${_seq++}', mine: true, parts: q.isEmpty ? const [] : [TitiTextPart(q)], images: images, at: DateTime.now());
    await _start(mine, [...state.messages, mine]);
  }

  /// Ask the last question again (after an error), photos and all.
  Future<void> retry() async {
    if (state.streaming) return;
    final i = state.messages.lastIndexWhere((m) => m.mine);
    if (i < 0) return;
    await _start(state.messages[i], state.messages.sublist(0, i + 1));
  }

  Future<void> _start(TitiMessage question, List<TitiMessage> before) async {
    _error = null;
    final live = _live = TitiLive();
    final answer = TitiMessage(key: 'local-${_seq++}', mine: false, parts: const [], live: live);
    state = state.copyWith(messages: [...before, answer], streaming: true, thinking: true);

    try {
      // Photos go up first (in parallel); a retry reuses what already went up.
      var images = question.images;
      if (images.any((i) => i.path == null)) {
        final me = ref.read(currentUserIdProvider);
        if (me == null) throw const AppException('Sign in again to chat with TiTi.');
        images = await Future.wait([
          for (final i in images) i.path != null ? Future.value(i) : _repo.uploadPhoto(me: me, bytes: i.bytes!).then(i.withPath),
        ]);
        _replace(question.key, (m) => m.copyWith(images: images));
      }
      if (!state.streaming || _live != live) return; // stopped meanwhile
      final here = await _where();
      if (!state.streaming || _live != live) return;
      _sub = _repo
          .ask(question.text, sessionId: state.sessionId, images: [for (final i in images) i.path!], lat: here?.latitude, lng: here?.longitude)
          .listen(
            (ev) => _on(ev, live),
            onError: (Object e) {
              _error = titiErrorText(e);
              _finish(live);
            },
            onDone: () => _finish(live),
            cancelOnError: true,
          );
    } catch (e) {
      _error = titiErrorText(e);
      _finish(live);
    }
  }

  void _on(TitiEvent ev, TitiLive live) {
    if (_live != live) return;
    switch (ev) {
      case TitiSessionStarted(:final id):
        state = state.copyWith(sessionId: id);
        ref.invalidate(titiSessionsProvider);
      case TitiDelta(:final text):
        live.addText(text);
        if (state.thinking && !live.waiting) state = state.copyWith(thinking: false);
      case TitiBreak():
        live.closeBubble();
      case TitiCardEvent(:final card):
        live.addPart(TitiCardPart(card));
        if (state.thinking) state = state.copyWith(thinking: false);
      case TitiActionEvent(:final action):
        live.addPart(TitiActionPart(action));
        if (state.thinking) state = state.copyWith(thinking: false);
      case TitiChips(:final options):
        live.chips = options;
      case TitiStatus(:final text, :final tool):
        live.setStatus(text, tool);
        if (!state.thinking) state = state.copyWith(thinking: true);
      case TitiError(:final text):
        _error = text;
      case TitiDone(:final title):
        if (title != null && title.isNotEmpty) {
          state = state.copyWith(title: title);
          ref.invalidate(titiSessionsProvider);
        }
    }
  }

  /// The stream ended. The answer keeps its [TitiLive] until it has typed out.
  void _finish(TitiLive live) {
    if (_live != live) return;
    _sub = null;
    _live = null;
    if (live.isEmpty && _error == null) _error = 'TiTi went quiet. Try again?';
    live.error = _error;
    live.finish();
    final msgs = [...state.messages];
    final i = msgs.lastIndexWhere((m) => m.live == live);
    if (i >= 0) msgs[i] = msgs[i].copyWith(parts: live.parts, chips: live.chips, error: _error, at: DateTime.now());
    state = state.copyWith(messages: msgs, streaming: false, thinking: false);
  }

  /// Stop generating. What has arrived stays (the server keeps it too).
  void stop() {
    final live = _live;
    if (live == null) return;
    _sub?.cancel();
    _sub = null;
    _live = null;
    live.finish();
    final msgs = [...state.messages];
    final i = msgs.lastIndexWhere((m) => m.live == live);
    if (i >= 0) {
      if (live.isEmpty) {
        msgs.removeAt(i);
      } else {
        msgs[i] = msgs[i].copyWith(parts: live.parts, chips: live.chips, at: DateTime.now());
      }
    }
    state = state.copyWith(messages: msgs, streaming: false, thinking: false);
  }

  /// An action card was done or waved off: the card changes at once, and the
  /// server remembers (a moment later if the answer isn't saved yet).
  Future<void> markAction(TitiAction a, TitiActionStatus status, {String? resultRoute}) async {
    final updated = a.copyWith(status: status, resultRoute: resultRoute);
    final msgs = [
      for (final m in state.messages)
        if (m.parts.any((p) => p is TitiActionPart && p.action.id == a.id))
          m.copyWith(parts: [for (final p in m.parts) p is TitiActionPart && p.action.id == a.id ? TitiActionPart(updated) : p])
        else
          m,
    ];
    for (final m in msgs) {
      m.live?.replaceAction(updated);
    }
    state = state.copyWith(messages: msgs);
    final db = status == TitiActionStatus.done ? 'done' : 'dismissed';
    try {
      if (!await _repo.setActionStatus(a.id, db, route: resultRoute)) {
        await Future<void>.delayed(const Duration(seconds: 3));
        await _repo.setActionStatus(a.id, db, route: resultRoute);
      }
    } catch (_) {
      // The card shows it done here; worst case it reloads as not tapped.
    }
  }

  void _replace(String key, TitiMessage Function(TitiMessage) f) {
    state = state.copyWith(messages: [for (final m in state.messages) m.key == key ? f(m) : m]);
  }

  /// Where I am, if the phone already knows: the live fix, else the last
  /// known one. Never asks for permission (the location gate does that).
  Future<LatLng?> _where() async {
    final live = ref.read(livePositionProvider);
    if (live != null) return live.latLng;
    try {
      final p = await Geolocator.getLastKnownPosition().timeout(const Duration(milliseconds: 600));
      if (p != null) return LatLng(p.latitude, p.longitude);
    } catch (_) {}
    return null;
  }
}

final titiControllerProvider = NotifierProvider<TitiController, TitiState>(TitiController.new);
