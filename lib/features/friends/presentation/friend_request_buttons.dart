import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// What the member did with a friend request on this visit.
enum RequestAnswer { accepted, removed }

/// Friend requests answered on the current screen, Instagram style: the row
/// stays where it was and changes ("Message" after Accept, "Request removed"
/// after Delete) instead of vanishing, until the member leaves the screen.
///
/// Optimistic: [answer] shows the new state at once and puts the row back if
/// the server says no.
class FriendRequestAnswers extends ChangeNotifier {
  final _answers = <String, RequestAnswer>{};

  /// [key] names one request (a notification id, or person + time).
  RequestAnswer? of(String key) => _answers[key];

  bool get isEmpty => _answers.isEmpty;

  /// Shows [answer] for request [key] right away, then runs [send]. If [send]
  /// fails the request goes back to waiting and the error is rethrown.
  /// A second tap while one is under way (or done) is ignored.
  Future<void> answer(String key, RequestAnswer answer, Future<void> Function() send) async {
    if (_answers.containsKey(key)) return;
    _answers[key] = answer;
    notifyListeners();
    try {
      await send();
    } catch (_) {
      _answers.remove(key);
      notifyListeners();
      rethrow;
    }
  }
}

/// The right-hand side of a friend request row: Accept + Delete while it
/// waits, an outlined Message once accepted, muted "Request removed" once
/// deleted. Compact, so the row's text keeps its room at large text sizes.
class FriendRequestButtons extends StatelessWidget {
  const FriendRequestButtons({super.key, required this.answer, required this.onAccept, required this.onDelete, required this.onMessage});

  /// Null while the request waits.
  final RequestAnswer? answer;
  final VoidCallback onAccept;
  final VoidCallback onDelete;
  final VoidCallback onMessage;

  static const _textStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const _padding = EdgeInsets.symmetric(horizontal: 12);
  static const _minSize = Size(0, 32);

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));
    final child = switch (answer) {
      null => Row(
          key: const ValueKey('waiting'),
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: onAccept,
              style: FilledButton.styleFrom(minimumSize: _minSize, padding: _padding, textStyle: _textStyle, shape: shape, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('Accept'),
            ),
            const SizedBox(width: 6),
            ElevatedButton(
              onPressed: onDelete,
              style: ElevatedButton.styleFrom(minimumSize: _minSize, padding: _padding, textStyle: _textStyle, shape: shape, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('Delete'),
            ),
          ],
        ),
      RequestAnswer.accepted => OutlinedButton(
          key: const ValueKey('accepted'),
          onPressed: onMessage,
          style: OutlinedButton.styleFrom(minimumSize: _minSize, padding: _padding, textStyle: _textStyle, shape: shape, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: const Text('Message'),
        ),
      RequestAnswer.removed => ConstrainedBox(
          key: const ValueKey('removed'),
          constraints: const BoxConstraints(maxWidth: 96),
          child: Text('Request removed', textAlign: TextAlign.end, maxLines: 2, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
        ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerRight, children: [...previous, ?current]),
      child: child,
    );
  }
}

/// Keeps rows the member answered on this visit in a list the server has
/// since dropped them from (an accepted request's notification is deleted, a
/// declined request is gone): [fresh] plus every [kept] row not in it, in
/// [fresh]'s order with kept rows slotted back by [newerFirst].
List<T> keepAnsweredRows<T>(List<T> fresh, Iterable<T> kept, {required Object Function(T) id, required int Function(T a, T b) newerFirst}) {
  final ids = {for (final f in fresh) id(f)};
  final missing = [for (final k in kept) if (!ids.contains(id(k))) k];
  if (missing.isEmpty) return fresh;
  final out = [...fresh];
  for (final m in missing) {
    var at = out.indexWhere((x) => newerFirst(m, x) < 0);
    if (at < 0) at = out.length;
    out.insert(at, m);
  }
  return out;
}
