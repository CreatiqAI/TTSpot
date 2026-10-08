import 'dart:async';

import 'package:flutter/gestures.dart' show kLongPressTimeout, kTouchSlop;
import 'package:flutter/widgets.dart';

/// App-wide keyboard habits, wrapped once around the whole app:
///  * a tap anywhere outside a text field closes the keyboard (Flutter only
///    does this for mouse clicks on phones). Text fields, their selection
///    toolbar and anything in a [TextFieldTapRegion] (chat bars, @ lists)
///    count as inside. Nothing is stolen: the tap still lands where it fell.
///    Only a real tap counts, so a swipe-to-reply, a long-press menu or a
///    map pan doesn't drop the keyboard;
///  * dragging any vertical list or page closes it, like
///    [ScrollViewKeyboardDismissBehavior.onDrag] everywhere. A long field
///    scrolling its own text doesn't count, and sideways swipes (tabs,
///    carousels) leave it alone.
class KeyboardDismissal extends StatefulWidget {
  const KeyboardDismissal({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardDismissal> createState() => _KeyboardDismissalState();
}

class _KeyboardDismissalState extends State<KeyboardDismissal> {
  /// Where each finger went down outside the focused field, with a timer
  /// that runs out when the press becomes a long press.
  final _downs = <int, (PointerDownEvent, Timer)>{};

  @override
  void dispose() {
    for (final d in _downs.values) {
      d.$2.cancel();
    }
    super.dispose();
  }

  static bool _isTextField(FocusNode? f) => f?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.dragDetails == null || n.metrics.axis != Axis.vertical) return false;
    final f = FocusManager.instance.primaryFocus;
    if (!_isTextField(f)) return false;
    // A multi-line field scrolling its own lines: keep typing.
    if (n.context?.findAncestorWidgetOfExactType<EditableText>() != null) return false;
    f!.unfocus();
    return false;
  }

  void _down(EditableTextTapOutsideIntent i) {
    final e = i.pointerDownEvent;
    // A cancelled pointer never sends its up: don't let those pile up.
    if (_downs.length > 4) {
      for (final d in _downs.values) {
        d.$2.cancel();
      }
      _downs.clear();
    }
    _downs[e.pointer] = (e, Timer(kLongPressTimeout, () {}));
  }

  void _up(EditableTextTapUpOutsideIntent i) {
    final up = i.pointerUpEvent;
    final down = _downs.remove(up.pointer);
    if (down == null) return;
    final (e, timer) = down;
    final tap = timer.isActive && (up.position - e.position).distance <= kTouchSlop;
    timer.cancel();
    if (tap && i.focusNode.hasFocus) i.focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: _onScroll,
      child: Actions(
        actions: <Type, Action<Intent>>{
          EditableTextTapOutsideIntent: CallbackAction<EditableTextTapOutsideIntent>(onInvoke: _down),
          EditableTextTapUpOutsideIntent: CallbackAction<EditableTextTapUpOutsideIntent>(onInvoke: _up),
        },
        child: widget.child,
      ),
    );
  }
}
