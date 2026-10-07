import 'package:flutter/widgets.dart';

import '../../core/guide/guide.dart';
import '../../core/theme/titi.dart';

// TiTi guides for the map and the places on it (docs/titi-guides-plan.md):
// map, event, spot, club and partner. Each screen holds a keys object (one
// GlobalKey per spotlighted widget) and builds its guide at show time, so a
// step whose widget isn't on the page is left out.

/// Holds a keys object for a stateless page (one set per page instance, so two
/// copies of the page on the stack never share a GlobalKey).
class GuideKeyScope<T> extends StatefulWidget {
  const GuideKeyScope({super.key, required this.create, required this.builder});
  final T Function() create;
  final Widget Function(BuildContext context, T keys) builder;

  @override
  State<GuideKeyScope<T>> createState() => _GuideKeyScopeState<T>();
}

class _GuideKeyScopeState<T> extends State<GuideKeyScope<T>> {
  late final T _keys = widget.create();

  @override
  Widget build(BuildContext context) => widget.builder(context, _keys);
}

// ------------------------------------------------------------------- map ---

class MapGuideKeys {
  final modeSwitch = GlobalKey(debugLabel: 'guide-map-switch');
  final chips = GlobalKey(debugLabel: 'guide-map-chips');
  /// The round buttons on the right: the eye (who sees me) over find me.
  final buttons = GlobalKey(debugLabel: 'guide-map-buttons');
  final nearbyBar = GlobalKey(debugLabel: 'guide-map-nearby');
}

Guide mapGuide(MapGuideKeys k) => Guide(
      id: GuideIds.map,
      steps: [
        GuideStep(
          target: k.modeSwitch,
          title: 'Three ways to look',
          body: "Now: who's out. Events: meets coming up. Spots: places to hang.",
          pose: TitiPose.mapPin,
          radius: 24,
        ),
        GuideStep(
          target: k.chips,
          title: 'Pick who you see',
          body: 'Tap a chip to filter: friends, clubmates, drivers nearby and more.',
          pose: TitiPose.binoculars,
          radius: 20,
        ),
        GuideStep(
          target: k.buttons,
          title: 'Seen or ghost',
          body: 'Eye: friends see you, or go ghost. Below it: find me, back to you.',
          pose: TitiPose.magnifier,
          radius: 28,
        ),
        GuideStep(
          target: k.nearbyBar,
          title: "Who's around",
          body: 'A quick look at who and what is nearby. Tap it for the list.',
          pose: TitiPose.wave,
          radius: 31,
        ),
        const GuideStep(
          title: 'Tap any pin',
          body: 'A TT, a meet, a spot or a partner shop. Each one opens its page.',
          pose: TitiPose.thumbsUp,
        ),
      ],
    );

// ----------------------------------------------------------------- event ---

class EventGuideKeys {
  final rsvp = GlobalKey(debugLabel: 'guide-event-rsvp');
  final checkIn = GlobalKey(debugLabel: 'guide-event-checkin');
  final onMyWay = GlobalKey(debugLabel: 'guide-event-on-my-way');
  final chat = GlobalKey(debugLabel: 'guide-event-chat');
}

/// A meet page, for a member who isn't the host. Steps follow what the page
/// shows: [live] has the check-in card (else a line about the host's QR),
/// [onMyWay] and [chat] only when those buttons are there.
Guide eventGuide(EventGuideKeys k, {required bool attending, bool full = false, bool live = false, bool onMyWay = false, bool chat = false}) => Guide(
      id: GuideIds.event,
      steps: [
        // Already going: no "how to leave" tip; start with what to do there.
        if (!attending && !full)
          GuideStep(target: k.rsvp, title: 'Count me in', body: "Tap Join to go. That opens the meet chat and \"I'm on my way\".", pose: TitiPose.calendar),
        if (live)
          GuideStep(target: k.checkIn, title: 'Check in here', body: "At the meet? Check in or scan the host's QR. That's +10 points.", pose: TitiPose.mapPin)
        else
          const GuideStep(title: 'Check in at the meet', body: "On the day, scan the host's QR to check in. That's +10 points.", pose: TitiPose.mapPin),
        if (onMyWay) GuideStep(target: k.onMyWay, title: 'On your way?', body: 'Posts your ETA in the meet chat, then opens directions.', pose: TitiPose.rolling),
        if (chat) GuideStep(target: k.chat, title: 'Meet chat', body: 'Plan the drive, share updates, find each other on the day.', pose: TitiPose.chat),
      ],
    );

// ------------------------------------------------------------------ spot ---

class SpotGuideKeys {
  final checkIn = GlobalKey(debugLabel: 'guide-spot-checkin');
  final moment = GlobalKey(debugLabel: 'guide-spot-moment');
}

Guide spotGuide(SpotGuideKeys k) => Guide(
      id: GuideIds.spot,
      steps: [
        GuideStep(
          target: k.checkIn,
          title: 'Check in here',
          body: 'At the spot? Check in for +10 points, once a week per spot.',
          pose: TitiPose.mapPin,
        ),
        GuideStep(
          target: k.moment,
          title: 'Snap a moment',
          body: "Share a photo from here. It lands in the spot's album.",
          pose: TitiPose.camera,
        ),
      ],
    );

// ------------------------------------------------------------------ club ---

class ClubGuideKeys {
  final join = GlobalKey(debugLabel: 'guide-club-join');
  /// The invite banner (it has the Join button when I was invited).
  final invite = GlobalKey(debugLabel: 'guide-club-invite');
  final chat = GlobalKey(debugLabel: 'guide-club-chat');
  /// The "Official club" chip in the header (outsiders).
  final officialChip = GlobalKey(debugLabel: 'guide-club-official');
  /// The wear-the-tag switch (members of an official club).
  final tagSwitch = GlobalKey(debugLabel: 'guide-club-tag');
}

/// A club page, for a member or an outsider (not its officers). [invited]:
/// an open invite, whose banner holds the Join button.
Guide clubGuide(ClubGuideKeys k, {required bool member, required bool official, bool invited = false}) => Guide(
      id: GuideIds.club,
      steps: [
        if (member)
          GuideStep(target: k.join, title: "You're in", body: 'This is your member button. Tap it if you ever want to leave.', pose: TitiPose.thumbsUp)
        else
          GuideStep(target: invited ? k.invite : k.join, title: 'Join the club', body: 'See clubmates on the map, catch their meets and get the club chat.', pose: TitiPose.flag),
        if (member) GuideStep(target: k.chat, title: 'Club chat', body: 'Every member is in here. Plan drives and say hi.', pose: TitiPose.chat),
        if (official && member)
          GuideStep(target: k.tagSwitch, title: 'Wear the tag', body: "Show the club's crest beside your name across the app.", pose: TitiPose.trophy)
        else if (official)
          GuideStep(target: k.officialChip, title: 'An official club', body: 'Members can wear its crest beside their name.', pose: TitiPose.trophy),
        if (!member && !official) const GuideStep(title: 'Say hi first', body: 'Not sure yet? Follow the club or message it.', pose: TitiPose.chat),
      ],
    );

// --------------------------------------------------------------- partner ---

class PartnerGuideKeys {
  final follow = GlobalKey(debugLabel: 'guide-partner-follow');
  final tabs = GlobalKey(debugLabel: 'guide-partner-tabs');
  final directions = GlobalKey(debugLabel: 'guide-partner-directions');
}

/// A partner shop's page, for anyone but its owner. [hasLocation]: the
/// Directions button is there. [hasSpot]: the shop is a spot to check in at.
Guide partnerGuide(PartnerGuideKeys k, {required bool hasLocation, required bool hasSpot}) => Guide(
      id: GuideIds.partner,
      steps: [
        GuideStep(target: k.follow, title: 'Follow the shop', body: 'Their posts land in your Following feed.', pose: TitiPose.heart),
        GuideStep(target: k.tabs, title: 'Deals and goodies', body: 'Vouchers and products live in these tabs. Grab a deal!', pose: TitiPose.voucher),
        if (hasLocation)
          GuideStep(
            target: k.directions,
            title: 'Drop by',
            body: hasSpot ? 'Directions get you there. Check in at the shop for points.' : 'Directions get you there in one tap.',
            pose: TitiPose.mapPin,
          )
        else if (hasSpot)
          const GuideStep(title: 'Drop by', body: 'Visiting? Check in at the shop for points. Find it under Info.', pose: TitiPose.mapPin),
      ],
    );
