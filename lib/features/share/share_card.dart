import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_images.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/titi.dart';
import '../../core/utils/dates.dart';
import '../cards/domain/cards.dart';
import '../cards/presentation/widgets/card_face.dart';
import '../events/domain/event.dart';

/// Story-format share cards (9:16). Laid out at [kShareCardSize] logical
/// pixels and captured at [kSharePixelRatio], so the PNG is 1080x1920.
/// Always dark, whatever the app theme: near-black with a soft red glow, the
/// TT Spot logo on top, a big Barlow headline, the content, and a
/// "Join me on TT Spot" footer with a link.
const kShareCardSize = Size(360, 640);
const kSharePixelRatio = 3.0;

const _bg = Color(0xFF0B0B0E);
const _panel = Color(0xFF1B1B20);
const _muted = Color(0xB3FFFFFF); // white 70%
const _faint = Color(0x80FFFFFF); // white 50%

/// What a share card shows. Each kind picks its own layout.
sealed class ShareCardSpec {
  const ShareCardSpec();

  /// Short tag for the PNG file name.
  String get fileTag;

  /// Message that goes with the image; [link] is the footer URL.
  String shareText(String link);

  /// Images to have decoded before the card is captured.
  List<ImageProvider> get images => const [];
}

/// "CHECKED IN" at a meet or spot, with the member's car.
class CheckinShareSpec extends ShareCardSpec {
  const CheckinShareSpec({required this.placeName, required this.at, this.carCover, this.carBodyStyle, this.carTitle});
  final String placeName;
  final DateTime at;
  final String? carCover;
  final String? carBodyStyle;
  final String? carTitle;

  @override
  String get fileTag => 'checkin';

  @override
  String shareText(String link) => 'Checked in at $placeName on TT Spot. $link';

  @override
  List<ImageProvider> get images => [
        carCover != null ? CachedNetworkImageProvider(carCover!) : AssetImage(carPlaceholderAsset(carBodyStyle)),
        AssetImage(TitiPose.thumbsUp.asset),
      ];
}

/// A blind-box pull.
class CardPullShareSpec extends ShareCardSpec {
  const CardPullShareSpec({required this.card});
  final CardType card;

  @override
  String get fileTag => 'card-${card.id}';

  @override
  String shareText(String link) => card.rarity == CardRarity.legendary
      ? 'I pulled the Secret card, ${card.name}, from a TT Spot blind box. $link'
      : 'I just pulled ${card.name} (${card.rarity.label}) from a TT Spot blind box. $link';

  /// "I PULLED A RARE", but "I PULLED THE SECRET": there is only one.
  String get headline => card.rarity == CardRarity.legendary ? 'I PULLED\nTHE SECRET' : 'I PULLED A\n${card.rarity.label.toUpperCase()}';

  @override
  List<ImageProvider> get images => [?cardArt(card)];
}

/// Invite to a meet. [hostInvite] = the viewer hosts it, so the footer
/// carries the meet's invite link instead of the member's referral link.
class MeetInviteShareSpec extends ShareCardSpec {
  const MeetInviteShareSpec({required this.event, this.hostInvite = false});
  final Event event;
  final bool hostInvite;

  @override
  String get fileTag => 'meet';

  @override
  String shareText(String link) => 'Join us: ${event.title} · ${event.venueName} · ${_when(event)}. $link';

  @override
  List<ImageProvider> get images => [
        event.coverUrl != null ? CachedNetworkImageProvider(event.coverUrl!) : AssetImage(event.defaultCover),
      ];
}

/// "WINNER" of a lucky draw.
class DrawWinShareSpec extends ShareCardSpec {
  const DrawWinShareSpec({required this.prize, required this.eventName});
  final String prize;
  final String eventName;

  @override
  String get fileTag => 'winner';

  @override
  String shareText(String link) => 'I won $prize at $eventName on TT Spot! $link';

  @override
  List<ImageProvider> get images => [AssetImage(TitiPose.celebrate.asset), AssetImage(prizeAsset(prize))];
}

String _when(Event e) => e.isInstant ? 'now until ${formatTime(e.closesAt)}' : formatEventDateFriendly(e.startsAt);

/// The card itself, [kShareCardSize] logical pixels. [footerLink] is shown
/// without the scheme ("ttspot.my/r/AB12CD").
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.spec, required this.footerLink, this.footerLead = 'Join me on TT Spot'});
  final ShareCardSpec spec;
  final String footerLink;
  final String footerLead;

  @override
  Widget build(BuildContext context) {
    final (String? eyebrow, String headline, Widget body) = switch (spec) {
      CheckinShareSpec s => (null, 'CHECKED IN', _CheckinBody(s)),
      CardPullShareSpec s => (null, s.headline, _CardPullBody(s)),
      MeetInviteShareSpec s => ('JOIN US', s.event.title.toUpperCase(), _MeetBody(s)),
      DrawWinShareSpec s => ('LUCKY DRAW', 'WINNER', _DrawWinBody(s)),
    };
    final longHeadline = headline.length > 22;
    return MediaQuery(
      data: const MediaQueryData(size: kShareCardSize, devicePixelRatio: kSharePixelRatio),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 14, decoration: TextDecoration.none, fontWeight: FontWeight.w500),
        child: SizedBox.fromSize(
          size: kShareCardSize,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: _bg),
            child: Stack(
              children: [
                // Soft red glow behind the logo and headline, a fainter one low right.
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(center: Alignment(0, -0.78), radius: 0.95, colors: [Color(0x66E00008), Color(0x00E00008)]),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(center: Alignment(1.1, 0.9), radius: 0.8, colors: [Color(0x33E00008), Color(0x00E00008)]),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 30, 26, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Image.asset('assets/brand/logo_dark.png', height: 30, filterQuality: FilterQuality.high)),
                      const SizedBox(height: 26),
                      if (eyebrow != null) ...[
                        Text(eyebrow, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 3, color: AppColors.brand)),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        headline,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: longHeadline ? 40 : 60,
                          height: 0.95,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Expanded(child: body),
                      const SizedBox(height: 16),
                      Container(height: 1, color: const Color(0x26FFFFFF)),
                      const SizedBox(height: 14),
                      Text(footerLead, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _muted)),
                      const SizedBox(height: 3),
                      Text(
                        footerLink,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: AppFonts.display, fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- bodies ---

class _CheckinBody extends StatelessWidget {
  const _CheckinBody(this.s);
  final CheckinShareSpec s;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(s.placeName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 30, height: 1, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 6),
        Text(formatEventDate(s.at), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: _faint, fontWeight: FontWeight.w600)),
        const SizedBox(height: 18),
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                bottom: 20,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: s.carCover != null
                      ? Image(
                          image: CachedNetworkImageProvider(s.carCover!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _CarArt(bodyStyle: s.carBodyStyle),
                        )
                      : _CarArt(bodyStyle: s.carBodyStyle),
                ),
              ),
              if (s.carTitle != null)
                Positioned(
                  left: 12,
                  bottom: 32,
                  right: 110,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(999)),
                    child: Text(s.carTitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
              Positioned(right: -8, bottom: -6, child: Image.asset(TitiPose.thumbsUp.asset, height: 112, filterQuality: FilterQuality.medium)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The body-style render on a dark panel (no photo yet).
class _CarArt extends StatelessWidget {
  const _CarArt({this.bodyStyle});
  final String? bodyStyle;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: _panel,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Image.asset(carPlaceholderAsset(bodyStyle), fit: BoxFit.contain, filterQuality: FilterQuality.medium, errorBuilder: (_, _, _) => const SizedBox.shrink()),
        ),
      );
}

class _CardPullBody extends StatelessWidget {
  const _CardPullBody(this.s);
  final CardPullShareSpec s;

  @override
  Widget build(BuildContext context) {
    final rarity = s.card.rarity;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: rarity.pill(),
          child: Text(rarity.label.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2, color: rarity.onPill)),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (_, c) {
              final w = (c.maxHeight - 40) * kCardAspect;
              return Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(w * 0.09),
                      boxShadow: [BoxShadow(color: rarity.color.withValues(alpha: 0.55), blurRadius: 40, spreadRadius: 2)],
                    ),
                    child: CardFace(card: s.card, width: w.clamp(80.0, 230.0)),
                  ),
                  const SizedBox(height: 10),
                  Text(s.card.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MeetBody extends StatelessWidget {
  const _MeetBody(this.s);
  final MeetInviteShareSpec s;

  @override
  Widget build(BuildContext context) {
    final e = s.event;
    final fallback = Image.asset(e.defaultCover, fit: BoxFit.cover);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: e.coverUrl != null
                ? Image(image: CachedNetworkImageProvider(e.coverUrl!), fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback)
                : fallback,
          ),
        ),
        const SizedBox(height: 16),
        _InfoLine(icon: AppIcons.calendarBlank, text: _when(e)),
        const SizedBox(height: 8),
        _InfoLine(icon: AppIcons.mapPin, text: e.venueName),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(color: _panel, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: AppColors.brand),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2))),
        ],
      );
}

class _DrawWinBody extends StatelessWidget {
  const _DrawWinBody(this.s);
  final DrawWinShareSpec s;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          s.prize,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: AppFonts.display, fontSize: 34, height: 1, fontWeight: FontWeight.w800, color: AppColors.brand),
        ),
        const SizedBox(height: 8),
        Text('at ${s.eventName}', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _muted)),
        const SizedBox(height: 10),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: RadialGradient(radius: 0.6, colors: [Color(0x40F5B301), Color(0x00F5B301)])),
                ),
              ),
              Image.asset(TitiPose.celebrate.asset, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0x33FFFFFF))),
                  child: Image.asset(prizeAsset(s.prize), fit: BoxFit.contain, filterQuality: FilterQuality.medium, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
