import 'package:flutter/material.dart';

/// Pops (scales up and settles) whenever [active] flips to true, so a like or
/// a save visibly "lands". Wrap the icon, not the button.
class PopIcon extends StatefulWidget {
  const PopIcon({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<PopIcon> createState() => _PopIconState();
}

class _PopIconState extends State<PopIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.45).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.45, end: 0.9).chain(CurveTween(curve: Curves.easeInOut)), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 25),
  ]).animate(_c);

  @override
  void didUpdateWidget(covariant PopIcon old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _scale, child: widget.child);
}
