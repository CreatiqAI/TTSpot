import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/geo/latlng.dart';
import '../../../core/location/live_position.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../data/titi_repository.dart';
import '../domain/titi_message.dart';

/// The chat with TiTi as the screen draws it.
class TitiState {
  const TitiState({
    this.messages = const [],
    this.loading = true,
    this.loadError,
    this.streaming = false,
    this.thinking = false,
    this.status,
    this.tool,
  });

  /// Oldest first. While streaming, the last one is the answer being written.
  final List<TitiMessage> messages;

  /// History is loading (first open).
  final bool loading;
  final String? loadError;

  /// An answer is on its way; sending is off, Stop is on.
  final bool streaming;

  /// Waiting for words: TiTi's thinking animation shows.
  final bool thinking;

  /// What TiTi is checking right now, and with which tool (picks his pose).
  final String? status;
  final String? tool;

  TitiState copyWith({
    List<TitiMessage>? messages,
    bool? loading,
    String? loadError,
    bool? streaming,
    bool? thinking,
    String? status,
    String? tool,
    bool clearStatus = false,
  }) =>
      TitiState(
        messages: messages ?? this.messages,
        loading: loading ?? this.loading,
        loadError: loadError,
        streaming: streaming ?? this.streaming,
        thinking: thinking ?? this.thinking,
        status: clearStatus ? null : status ?? this.status,
        tool: clearStatus ? null : tool ?? this.tool,
      );
}

/// Sends questions, streams answers, keeps the chat. Lives as long as the
/// app (not the screen), so an answer keeps coming if you step away mid-way.
class TitiController extends Notifier<TitiState> {
  StreamSubscription<TitiEvent>? _sub;
  Timer? _flush;
  var _seq = 0;

  // The answer being written: finished parts, the bubble still growing, chips.
  final _parts = <TitiPart>[];
  final _text = StringBuffer();
  var _chips = const <String>[];
  String? _error;
  String? _question;

  @override
  TitiState build() {
    ref.watch(currentUserIdProvider); // a new account starts a fresh chat
    ref.onDispose(() {
      _sub?.cancel();
      _flush?.cancel();
    });
    Future.microtask(load);
    return const TitiState();
  }

  Future<void> load() async {
    if (state.streaming) return;
    state = state.copyWith(loading: true);
    try {
      final list = await ref.read(titiRepositoryProvider).history();
      if (!state.streaming) state = state.copyWith(messages: list, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, loadError: friendlyError(e));
    }
  }

  /// Ask something. Ignored while an answer is still coming.
  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || state.streaming) return;
    final mine = TitiMessage(key: 'local-${_seq++}', mine: true, parts: [TitiTextPart(q)]);
    await _start(q, [...state.messages, mine]);
  }

  /// Ask the last question again (after an error).
  Future<void> retry() async {
    if (state.streaming || state.messages.isEmpty) return;
    final last = state.messages.last;
    final q = last.mine ? last.text : last.question;
    if (q == null || q.trim().isEmpty) return;
    final keep = last.mine ? state.messages : state.messages.sublist(0, state.messages.length - 1);
    await _start(q, keep);
  }

  Future<void> _start(String q, List<TitiMessage> before) async {
    _parts.clear();
    _text.clear();
    _chips = const [];
    _error = null;
    _question = q;
    final answer = TitiMessage(key: 'local-${_seq++}', mine: false, parts: const [], question: q);
    state = state.copyWith(messages: [...before, answer], streaming: true, thinking: true, clearStatus: true);

    final here = await _where();
    if (!state.streaming) return; // stopped already
    _sub = ref.read(titiRepositoryProvider).ask(q, lat: here?.latitude, lng: here?.longitude).listen(
          _on,
          onError: (Object e) {
            _error = titiErrorText(e);
            _finish();
          },
          onDone: _finish,
          cancelOnError: true,
        );
  }

  void _on(TitiEvent ev) {
    switch (ev) {
      case TitiDelta(:final text):
        _text.write(text);
        if (text.trim().isNotEmpty && state.thinking) state = state.copyWith(thinking: false, clearStatus: true);
      case TitiBreak():
        _closeBubble();
      case TitiCardEvent(:final card):
        _closeBubble();
        _parts.add(TitiCardPart(card));
        if (state.thinking) state = state.copyWith(thinking: false, clearStatus: true);
      case TitiChips(:final options):
        _chips = options;
      case TitiStatus(:final text, :final tool):
        _closeBubble();
        state = state.copyWith(thinking: true, status: text, tool: tool);
      case TitiError(:final text):
        _error = text;
      case TitiDone():
        break;
    }
    // Words arrive every few ms; redraw at most every 40 ms so scrolling stays smooth.
    _flush ??= Timer(const Duration(milliseconds: 40), _publish);
  }

  void _closeBubble() {
    final t = _text.toString();
    if (t.trim().isNotEmpty) _parts.add(TitiTextPart(t));
    _text.clear();
  }

  List<TitiPart> _currentParts() => [..._parts, if (_text.toString().trim().isNotEmpty) TitiTextPart(_text.toString())];

  void _publish() {
    _flush?.cancel();
    _flush = null;
    if (state.messages.isEmpty || state.messages.last.mine) return;
    final last = state.messages.last;
    final updated = TitiMessage(key: last.key, mine: false, parts: _currentParts(), chips: _chips, error: _error, question: _question);
    state = state.copyWith(messages: [...state.messages.sublist(0, state.messages.length - 1), updated]);
  }

  void _finish() {
    _sub = null;
    if (!state.streaming) return;
    if (_currentParts().isEmpty && _error == null) _error = 'TiTi went quiet. Try again?';
    _publish();
    state = state.copyWith(streaming: false, thinking: false, clearStatus: true);
  }

  /// Stop generating. What has arrived stays (the server keeps it too).
  void stop() {
    if (!state.streaming) return;
    _sub?.cancel();
    _sub = null;
    _publish();
    final msgs = [...state.messages];
    if (msgs.isNotEmpty && !msgs.last.mine && msgs.last.isEmpty && msgs.last.error == null) msgs.removeLast();
    state = state.copyWith(messages: msgs, streaming: false, thinking: false, clearStatus: true);
  }

  Future<void> clear() async {
    stop();
    await ref.read(titiRepositoryProvider).clear();
    state = const TitiState(loading: false);
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
