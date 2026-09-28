import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/cards.dart';

/// Card proportions everywhere: the posters are 2:3.
const kCardAspect = 2 / 3;

/// The printed back of every card.
const kCardBackAsset = 'assets/cards/back.jpg';

/// Art that ships inside the app, by card id. An `art_url` set by an admin
/// wins over these.
const kCardAssets = <String, String>{
  'c1': 'assets/cards/c1.jpg',
  'c2': 'assets/cards/c2.jpg',
  'c3': 'assets/cards/c3.jpg',
  'c4': 'assets/cards/c4.jpg',
  'c5': 'assets/cards/c5.jpg',
  'c6': 'assets/cards/c6.jpg',
  'c7': 'assets/cards/c7.jpg',
};

/// The image for a card, or null when only the placeholder exists.
ImageProvider? cardArt(CardType card) {
  if (card.artUrl != null) return CachedNetworkImageProvider(card.artUrl!);
  final asset = kCardAssets[card.id];
  return asset == null ? null : AssetImage(asset);
}

/// The front of a card. Draws the final art when the design has landed,
/// otherwise a tinted placeholder with the number, name and rarity ribbon.
class CardFace extends StatelessWidget {
  const CardFace({super.key, required this.card, this.width = 120, this.count, this.locked = false});

  final CardType card;
  final double width;
  /// Copies held; shows a ×N badge when above 1.
  final int? count;
  /// Not owned yet: greyed out with a "?" instead of the art.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final h = width / kCardAspect;
    final r = width * 0.09;
    final rarity = card.rarity;
    final s = width / 120; // scale factor for text
    final art = cardArt(card);

    Widget face = Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(card.color, Colors.white, 0.18)!, card.color, Color.lerp(card.color, Colors.black, 0.45)!],
          stops: const [0, 0.45, 1],
        ),
        border: Border.all(color: rarity == CardRarity.common ? Colors.white.withValues(alpha: 0.35) : rarity.color, width: rarity == CardRarity.common ? 1 : 2 * s),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10 * s, offset: Offset(0, 4 * s)),
          if (rarity != CardRarity.common) BoxShadow(color: rarity.color.withValues(alpha: 0.35), blurRadius: 14 * s),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (art != null)
            Image(image: art, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())
          else
            CustomPaint(painter: _PlaceholderPainter(number: card.number, rarity: rarity)),
          // bottom plate: name + rarity (the posters carry their own title)
          if (art == null) Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(9 * s, 18 * s, 9 * s, 8 * s),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)]),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    card.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: AppFonts.display, fontSize: 17 * s, fontWeight: FontWeight.w800, color: Colors.white, height: 1, letterSpacing: 0.5),
                  ),
                  SizedBox(height: 4 * s),
                  RarityPill(rarity: rarity, scale: s),
                ],
              ),
            ),
          ),
          // number, top left
          if (art == null) Positioned(
            left: 8 * s,
            top: 7 * s,
            child: Text('No. ${card.number}', style: TextStyle(fontFamily: AppFonts.display, fontSize: 11 * s, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.85), letterSpacing: 0.5)),
          ),
          if (count != null && count! > 1)
            Positioned(
              right: 7 * s,
              top: 7 * s,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                child: Text('×$count', style: TextStyle(fontSize: 11 * s, fontWeight: FontWeight.w800, color: AppColors.ink)),
              ),
            ),
        ],
      ),
    );

    if (locked) {
      face = Stack(
        alignment: Alignment.center,
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.2126, 0.7152, 0.0722, 0, 0, //
              0.2126, 0.7152, 0.0722, 0, 0, //
              0.2126, 0.7152, 0.0722, 0, 0, //
              0, 0, 0, 1, 0,
            ]),
            child: Opacity(opacity: 0.35, child: face),
          ),
          Text('?', style: TextStyle(fontFamily: AppFonts.display, fontSize: 44 * s, fontWeight: FontWeight.w800, color: AppColors.textMuted)),
        ],
      );
    }
    return face;
  }
}

class RarityPill extends StatelessWidget {
  const RarityPill({super.key, required this.rarity, this.scale = 1});
  final CardRarity rarity;
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 2.5 * scale),
        decoration: BoxDecoration(color: rarity.color, borderRadius: BorderRadius.circular(999)),
        child: Text(
          rarity.label.toUpperCase(),
          style: TextStyle(fontSize: 9 * scale, fontWeight: FontWeight.w800, letterSpacing: 1, color: rarity == CardRarity.legendary ? AppColors.ink : Colors.white),
        ),
      );
}

/// Until the real art lands: a huge ghosted number, speed lines, a chequered
/// corner for the legendary.
class _PlaceholderPainter extends CustomPainter {
  const _PlaceholderPainter({required this.number, required this.rarity});
  final int number;
  final CardRarity rarity;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // speed lines
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final y = h * (0.12 + i * 0.11);
      canvas.drawLine(Offset(-w * 0.2, y + w * 0.45), Offset(w * 0.75 - i * w * 0.08, y - w * 0.18), line);
    }
    // ghosted number
    final tp = TextPainter(
      text: TextSpan(text: '$number', style: TextStyle(fontFamily: AppFonts.display, fontSize: h * 0.52, fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.22), height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(w - tp.width - w * 0.06, h * 0.16));
    // chequered flag corner for the legendary
    if (rarity == CardRarity.legendary) {
      final sq = w * 0.07;
      final p = Paint()..color = Colors.white.withValues(alpha: 0.35);
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 6; c++) {
          if ((r + c).isEven) canvas.drawRect(Rect.fromLTWH(w - sq * (c + 1), h * 0.5 + r * sq, sq, sq), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PlaceholderPainter old) => old.number != number || old.rarity != rarity;
}

/// The back of every card: ink, red stripe, wordmark.
class CardBack extends StatelessWidget {
  const CardBack({super.key, this.width = 120});
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width / kCardAspect;
    final s = width / 120;
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(width * 0.09),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.5 * s),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12 * s, offset: Offset(0, 5 * s))],
      ),
      clipBehavior: Clip.antiAlias,
      // The printed card back (assets/cards/back.jpg). The drawn version stays
      // as the fallback if the asset ever fails to load.
      child: Image.asset(
        kCardBackAsset,
        fit: BoxFit.cover,
        width: width,
        height: h,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _drawnBack(s),
      ),
    );
  }

  Widget _drawnBack(double s) => Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _BackPainter())),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2 * s), borderRadius: BorderRadius.circular(6 * s)),
            child: Text('TT SPOT', style: TextStyle(fontFamily: AppFonts.display, fontSize: 20 * s, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.5, height: 1)),
          ),
        ],
      );
}

class _BackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final red = Paint()..color = AppColors.brand;
    final path = Path()
      ..moveTo(0, h * 0.62)
      ..lineTo(w, h * 0.30)
      ..lineTo(w, h * 0.46)
      ..lineTo(0, h * 0.78)
      ..close();
    canvas.drawPath(path, red);
    final dots = Paint()..color = Colors.white.withValues(alpha: 0.07);
    final step = w * 0.12;
    for (var y = step / 2; y < h; y += step) {
      for (var x = step / 2; x < w; x += step) {
        canvas.drawCircle(Offset(x, y), w * 0.012, dots);
      }
    }
  }

  @override
  bool shouldRepaint(_BackPainter old) => false;
}

/// Holds a card that tilts under your finger (3D perspective + moving glare)
/// and springs back when you let go.
class TiltCard extends StatefulWidget {
  const TiltCard({super.key, required this.child, this.maxTilt = 0.35, this.idleFloat = true});
  final Widget child;
  /// Radians at the edge of the card.
  final double maxTilt;
  /// Gentle bob while untouched.
  final bool idleFloat;

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> with TickerProviderStateMixin {
  Offset _tilt = Offset.zero; // -1..1 on each axis
  late final AnimationController _spring = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _float = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  Offset _from = Offset.zero;
  bool _touching = false;

  @override
  void initState() {
    super.initState();
    _spring.addListener(() {
      final t = Curves.elasticOut.transform(_spring.value);
      setState(() => _tilt = Offset.lerp(_from, Offset.zero, t)!);
    });
  }

  @override
  void dispose() {
    _spring.dispose();
    _float.dispose();
    super.dispose();
  }

  void _update(Offset local, Size size) {
    final dx = ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0);
    final dy = ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0);
    setState(() => _tilt = Offset(dx, dy));
  }

  void _release() {
    _touching = false;
    _from = _tilt;
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth.isFinite ? c.maxWidth : 200, c.maxHeight.isFinite ? c.maxHeight : 300);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) {
            _touching = true;
            _spring.stop();
            _update(d.localPosition, size);
          },
          onPanUpdate: (d) => _update(d.localPosition, size),
          onPanEnd: (_) => _release(),
          onPanCancel: _release,
          child: AnimatedBuilder(
            animation: _float,
            builder: (context, child) {
              final idle = widget.idleFloat && !_touching && _tilt == Offset.zero;
              final bob = idle ? math.sin(_float.value * 2 * math.pi) : 0.0;
              final rx = -_tilt.dy * widget.maxTilt + bob * 0.04;
              final ry = _tilt.dx * widget.maxTilt + (idle ? math.cos(_float.value * 2 * math.pi) * 0.05 : 0);
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0016)
                  ..rotateX(rx)
                  ..rotateY(ry)
                  ..multiply(Matrix4.translationValues(0, bob * 4, 0)),
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    child!,
                    // glare follows the tilt
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(size.width * 0.09),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(-_tilt.dx * 1.2, -_tilt.dy * 1.2),
                                radius: 1.1,
                                colors: [Colors.white.withValues(alpha: _touching ? 0.32 : 0.14), Colors.white.withValues(alpha: 0)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}
