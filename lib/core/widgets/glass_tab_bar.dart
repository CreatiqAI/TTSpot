import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass.dart';

/// One tab in the floating glass bar.
class GlassTab {
  const GlassTab({required this.icon, required this.selectedIcon, required this.label, this.badge = 0});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
}

/// Floating frosted pill with an ink capsule that slides to the selected tab
/// and an icon that pops when chosen. Sits over the page content
/// (Scaffold.extendBody), so what scrolls under it shows through the blur.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({super.key, required this.tabs, required this.selected, required this.onTap});
  final List<GlassTab> tabs;
  final int selected;
  final ValueChanged<int> onTap;

  static const height = 64.0;
  static const margin = EdgeInsets.fromLTRB(14, 0, 14, 10);

  @override
  Widget build(BuildContext context) {
    final n = tabs.length;
    return Padding(
      padding: margin.add(EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom)),
      child: GlassPanel(
        radius: 30,
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, c) {
              final slot = c.maxWidth / n;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    left: slot * selected + (slot - 52) / 2,
                    top: (height - 44) / 2,
                    child: Container(
                      width: 52,
                      height: 44,
                      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: _TabButton(
                            tab: tabs[i],
                            selected: i == selected,
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatefulWidget {
  const _TabButton({required this.tab, required this.selected, required this.onTap});
  final GlassTab tab;
  final bool selected;
  final VoidCallback onTap;
  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320), value: 1);
  late final Animation<double> _pop = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25).chain(CurveTween(curve: Curves.easeOut)), weight: 45),
    TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 55),
  ]).animate(_c);

  @override
  void didUpdateWidget(covariant _TabButton old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tab;
    final icon = Icon(widget.selected ? t.selectedIcon : t.icon, size: 25, color: widget.selected ? Colors.white : AppColors.textPrimary);
    return Semantics(
      label: t.label,
      selected: widget.selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Center(
          child: ScaleTransition(
            scale: _pop,
            child: t.badge > 0
                ? Badge(label: Text('${t.badge}'), child: icon)
                : icon,
          ),
        ),
      ),
    );
  }
}
