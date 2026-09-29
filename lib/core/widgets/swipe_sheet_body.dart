import 'package:flutter/material.dart';

/// Scrolling body for a tall modal sheet (`isScrollControlled: true`). As tall
/// as its content, up to the screen; scrolls when it has to; and a swipe down
/// anywhere closes the sheet once the content is at the top, like iOS sheets.
/// A plain scroll view would take that swipe and only the handle would drag.
class SwipeSheetBody extends StatefulWidget {
  const SwipeSheetBody({super.key, required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsets padding;

  @override
  State<SwipeSheetBody> createState() => _SwipeSheetBodyState();
}

class _SwipeSheetBodyState extends State<SwipeSheetBody> {
  final _content = GlobalKey();
  double _room = 0;
  // Content height as a share of the room; full height until measured.
  double _fit = 1;

  void _measure() {
    if (!mounted) return;
    final box = _content.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || _room <= 0) return;
    final fit = ((box.size.height + widget.padding.vertical) / _room).clamp(0.05, 1.0);
    if ((fit - _fit).abs() > 0.002) setState(() => _fit = fit);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          _room = constraints.maxHeight;
          WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: _fit,
            maxChildSize: _fit,
            minChildSize: 0, // dragged all the way down: the sheet closes
            snap: true,
            builder: (context, scroll) => SingleChildScrollView(
              controller: scroll,
              padding: widget.padding,
              child: KeyedSubtree(key: _content, child: widget.child),
            ),
          );
        },
      );
}
