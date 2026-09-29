import 'package:flutter/material.dart';

import 'app_theme.dart';

/// TiTi, the cone. Our mascot from the blind-box cards, rendered by Kie from
/// the card art as transparent PNGs in assets/titi/. He guides onboarding,
/// hands over the first box and fronts empty and error states.
enum TitiPose {
  wave('wave'),
  camera('camera'),
  magnifier('magnifier'),
  thumbsUp('thumbsup'),
  phone('phone'),
  gift('gift'),
  mapPin('mappin'),
  rolling('rolling'),
  sad('sad'),
  celebrate('celebrate'),
  sleeping('sleeping'),
  binoculars('binoculars'),
  chat('chat'),
  trophy('trophy'),
  calendar('calendar'),
  heart('heart'),
  voucher('voucher'),
  bell('bell'),
  flag('flag'),
  wrench('wrench'),
  stop('stop'),
  clipboard('clipboard');

  const TitiPose(this.file);
  final String file;
  String get asset => 'assets/titi/$file.png';
}

/// TiTi at a given height. Transparent art, so it sits on any background.
class Titi extends StatelessWidget {
  const Titi(this.pose, {super.key, this.height = 160, this.alignment = Alignment.center});
  final TitiPose pose;
  final double height;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Image.asset(pose.asset, height: height, fit: BoxFit.contain, alignment: alignment, filterQuality: FilterQuality.medium);
}

/// TiTi in a circle, for a small "he said" avatar next to a bubble.
class TitiAvatar extends StatelessWidget {
  const TitiAvatar(this.pose, {super.key, this.size = 56, this.background});
  final TitiPose pose;
  final double size;
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.08),
        decoration: BoxDecoration(shape: BoxShape.circle, color: background ?? AppColors.surfaceGray),
        child: Image.asset(pose.asset, fit: BoxFit.contain),
      );
}

/// A speech bubble that types itself in. [dark] = black bubble on a light
/// page (the default), else white on dark. The tail points bottom-left,
/// towards TiTi, unless [tailRight].
class TitiBubble extends StatefulWidget {
  const TitiBubble(this.text, {super.key, this.dark = true, this.tailRight = false, this.typing = true, this.maxWidth = 300, this.fontSize = 15});
  final String text;
  final bool dark;
  final bool tailRight;
  final bool typing;
  final double maxWidth;
  final double fontSize;

  @override
  State<TitiBubble> createState() => _TitiBubbleState();
}

class _TitiBubbleState extends State<TitiBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 220 + widget.text.length * 18));

  @override
  void initState() {
    super.initState();
    if (widget.typing) _c.forward();
  }

  @override
  void didUpdateWidget(TitiBubble old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _c.duration = Duration(milliseconds: 220 + widget.text.length * 18);
      if (widget.typing) _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.dark ? AppColors.ink : Colors.white;
    final fg = widget.dark ? Colors.white : AppColors.ink;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(widget.tailRight ? 18 : 4),
      bottomRight: Radius.circular(widget.tailRight ? 4 : 18),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: bg, borderRadius: radius, boxShadow: widget.dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))]),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final n = widget.typing ? (widget.text.length * Curves.easeOut.transform(_c.value)).round() : widget.text.length;
            return Stack(
              children: [
                // full text laid out invisibly so the bubble never resizes while typing
                Opacity(opacity: 0, child: Text(widget.text, style: TextStyle(fontSize: widget.fontSize, height: 1.35, color: fg))),
                Text(widget.text.substring(0, n), style: TextStyle(fontSize: widget.fontSize, height: 1.35, color: fg)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// TiTi (small, round) with a bubble beside him. The standard "guide" row.
class TitiSays extends StatelessWidget {
  const TitiSays(this.text, {super.key, required this.pose, this.dark = true, this.size = 64, this.typing = true});
  final String text;
  final TitiPose pose;
  final bool dark;
  final double size;
  final bool typing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TitiAvatar(pose, size: size, background: dark ? AppColors.surfaceGray : Colors.white),
          const SizedBox(width: 10),
          Flexible(child: TitiBubble(text, dark: dark, typing: typing)),
        ],
      );
}
