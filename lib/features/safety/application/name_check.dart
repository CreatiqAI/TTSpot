import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';

/// What a public name is for. Matches the kinds of `check_name` on the server:
/// handle = usernames and club handles, name = display and club names (both
/// also refuse reserved names like "admin" or "ttspot"), title = group, event
/// and business names (rude words only).
enum NameKind { handle, name, title }

/// Null when the name is fine, else a short reason to show under the field.
typedef NameCheck = Future<String?> Function(String text, NameKind kind);

/// The live `check_name` RPC (anon too: it runs before onboarding is done).
/// Tests stand in for it.
final nameCheckProvider = Provider<NameCheck>((ref) {
  return (text, kind) async =>
      await ref.read(supabaseProvider).rpc('check_name', params: {'p_text': text, 'p_kind': kind.name}) as String?;
});

/// Checks a text field while the member types, [delay] after the last key,
/// and keeps the reason in [problem] for the field's errorText. Call
/// [verify] before saving: it checks right away if the last text hasn't been
/// checked yet. A failed check (offline) counts as fine; the server still
/// refuses the name on save.
class LiveNameCheck extends ChangeNotifier {
  LiveNameCheck({
    required this.controller,
    required this.kind,
    required this.check,
    this.saved,
    this.delay = const Duration(milliseconds: 400),
  }) {
    _seen = _text;
    controller.addListener(_onChanged);
  }

  final TextEditingController controller;
  final NameKind kind;
  /// The name already saved; keeping it is always fine (old names don't block edits).
  String? saved;
  final Duration delay;
  /// The checker, usually `ref.read(nameCheckProvider)`.
  final NameCheck check;

  String? _problem;
  /// The text [_problem] belongs to (null = nothing checked yet).
  String? _checked;
  String _seen = '';
  Timer? _timer;
  bool _disposed = false;

  /// Why the current name can't be used, or null.
  String? get problem => _problem;

  String get _text => controller.text.trim();

  bool _skip(String t) => t.isEmpty || (saved != null && t == saved!.trim());

  void _onChanged() {
    final t = _text;
    if (t == _seen) return; // cursor moves fire too
    _seen = t;
    _timer?.cancel();
    if (_skip(t)) {
      _set(null, t);
      return;
    }
    _timer = Timer(delay, () => _run(t));
  }

  Future<String?> _run(String t) async {
    String? p;
    try {
      p = await check(t, kind);
    } catch (_) {
      return null;
    }
    if (_disposed || _text != t) return p;
    _set(p, t);
    return p;
  }

  void _set(String? p, String t) {
    _checked = t;
    if (_problem == p) return;
    _problem = p;
    if (!_disposed) notifyListeners();
  }

  /// The reason the current text can't be saved, checking now if needed.
  Future<String?> verify() async {
    _timer?.cancel();
    final t = _text;
    if (_skip(t)) {
      _set(null, t);
      return null;
    }
    if (_checked == t) return _problem;
    return _run(t);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    controller.removeListener(_onChanged);
    super.dispose();
  }
}
