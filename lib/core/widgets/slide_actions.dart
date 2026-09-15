import 'package:flutter/material.dart';

/// One action revealed behind a row when you swipe it.
class SlideAction {
  const SlideAction({required this.icon, required this.label, required this.color, required this.onTap, this.fg = Colors.white});
  final IconData icon;
  final String label;
  final Color color;
  final Color fg;
  final VoidCallback onTap;
}

/// Swipe a row to reveal buttons (WhatsApp / iOS Mail style). The row never
/// dismisses on its own: swipe right for [left] actions, left for [right]
/// actions, tap a button to act, tap the row or swipe back to close.
class SlideActions extends StatefulWidget {
  const SlideActions({super.key, required this.child, this.left = const [], this.right = const [], this.actionWidth = 84});
  final Widget child;
  final List<SlideAction> left;
  final List<SlideAction> right;
  final double actionWidth;

  @override
  State<SlideActions> createState() => _SlideActionsState();
}

class _SlideActionsState extends State<SlideActions> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200), lowerBound: -1, upperBound: 1, value: 0);

  double get _leftW => widget.left.length * widget.actionWidth;
  double get _rightW => widget.right.length * widget.actionWidth;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onStart(DragStartDetails d) {}

  void _onUpdate(DragUpdateDetails d) {
    final span = d.primaryDelta! >= 0 || _ctrl.value > 0 ? _leftW : _rightW;
    if (span == 0 && ((d.primaryDelta! > 0 && _ctrl.value <= 0) || (d.primaryDelta! < 0 && _ctrl.value >= 0))) return;
    final next = (_ctrl.value + d.primaryDelta! / (span == 0 ? 1 : span)).clamp(_rightW == 0 ? 0.0 : -1.0, _leftW == 0 ? 0.0 : 1.0);
    _ctrl.value = next;
  }

  void _onEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final target = v > 300 ? (_ctrl.value >= 0 ? 1.0 : 0.0) : v < -300 ? (_ctrl.value <= 0 ? -1.0 : 0.0) : (_ctrl.value.abs() > 0.5 ? _ctrl.value.sign : 0.0);
    _ctrl.animateTo(target, curve: Curves.easeOut);
  }

  void close() => _ctrl.animateTo(0, curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) {
          final v = _ctrl.value;
          final dx = v >= 0 ? v * _leftW : v * _rightW;
          return Stack(
            children: [
              if (v > 0)
                Positioned.fill(
                  child: Row(children: [
                    for (final a in widget.left) _Btn(a: a, width: widget.actionWidth, onTap: () { close(); a.onTap(); }),
                    const Spacer(),
                  ]),
                ),
              if (v < 0)
                Positioned.fill(
                  child: Row(children: [
                    const Spacer(),
                    for (final a in widget.right) _Btn(a: a, width: widget.actionWidth, onTap: () { close(); a.onTap(); }),
                  ]),
                ),
              Transform.translate(
                offset: Offset(dx, 0),
                child: GestureDetector(
                  onTap: v == 0 ? null : close,
                  behavior: HitTestBehavior.opaque,
                  child: AbsorbPointer(absorbing: v != 0, child: child),
                ),
              ),
            ],
          );
        },
        child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: widget.child),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.a, required this.width, required this.onTap});
  final SlideAction a;
  final double width;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: a.color,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(a.icon, color: a.fg, size: 22),
              const SizedBox(height: 4),
              Text(a.label, style: TextStyle(color: a.fg, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}
