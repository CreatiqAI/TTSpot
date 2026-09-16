import 'package:flutter/material.dart';

/// The tab branches, kept alive like an IndexedStack, but the incoming tab
/// fades and lifts in (220 ms) instead of snapping.
class AnimatedBranchStack extends StatefulWidget {
  const AnimatedBranchStack({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<AnimatedBranchStack> createState() => _AnimatedBranchStackState();
}

class _AnimatedBranchStackState extends State<AnimatedBranchStack> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<Offset> _lift = Tween(begin: const Offset(0, 0.012), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void didUpdateWidget(covariant AnimatedBranchStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            Offstage(
              offstage: i != widget.index,
              child: TickerMode(
                enabled: i == widget.index,
                child: i == widget.index
                    ? FadeTransition(opacity: _fade, child: SlideTransition(position: _lift, child: widget.children[i]))
                    : widget.children[i],
              ),
            ),
        ],
      );
}
