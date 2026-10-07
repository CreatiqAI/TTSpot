import 'package:flutter/widgets.dart';

import '../theme/titi.dart';

// TiTi guides: short, first-visit tips (docs/titi-guides-plan.md).
// A Guide is a list of steps; each step spotlights one widget (by GlobalKey)
// with TiTi and a speech card, or shows TiTi in the middle when it has no
// target (or the target isn't on screen).

/// One step of a guide.
class GuideStep {
  const GuideStep({
    this.target,
    required this.title,
    required this.body,
    this.pose = TitiPose.wave,
    this.tapTarget = false,
    this.padding = 8,
    this.radius = 16,
    this.circle = false,
    this.nextLabel,
  });

  /// The widget to spotlight. Null (or not on screen): TiTi in the middle, no hole.
  final GlobalKey? target;

  /// 2–5 words.
  final String title;

  /// One or two short lines (about 18 words at most).
  final String body;

  final TitiPose pose;

  /// The member taps the spotlighted widget themselves ("Tap Cards"). The tap
  /// reaches the real widget, then the guide ends with [GuideResult.tappedTarget]
  /// (journeys continue on the next screen). No Next button on this step.
  final bool tapTarget;

  /// Space around the target inside the spotlight.
  final double padding;

  /// Corner radius of the spotlight (ignored when [circle]).
  final double radius;

  /// A round spotlight (tab icons, round buttons).
  final bool circle;

  /// Overrides "Next" / "Got it" on this step (e.g. "Show me").
  final String? nextLabel;
}

/// A first-visit guide.
class Guide {
  const Guide({required this.id, required this.steps});

  /// One of [GuideIds]; stored in profiles.settings.guides_seen once shown.
  final String id;
  final List<GuideStep> steps;
}

/// How a guide ended.
enum GuideResult {
  /// Not shown: seen before, tips off, another guide showing, or not mounted.
  notShown,

  /// The member tapped Skip, Back, or outside.
  skipped,

  /// Went through every step.
  finished,

  /// A [GuideStep.tapTarget] step: the member tapped the spotlighted widget.
  tappedTarget,
}

/// Every guide id in one place (docs/titi-guides-plan.md has the catalogue).
abstract final class GuideIds {
  static const firstBox = 'first_box';
  static const home = 'home';
  static const map = 'map';
  static const create = 'create';
  static const chats = 'chats';
  static const titiChat = 'titi_chat';
  static const profile = 'profile';
  static const garage = 'garage';
  static const carPage = 'car_page';
  static const points = 'points';
  static const cards = 'cards';
  static const event = 'event';
  static const spot = 'spot';
  static const club = 'club';
  static const partner = 'partner';
  static const rewards = 'rewards';

  static const all = [firstBox, home, map, create, chats, titiChat, profile, garage, carPage, points, cards, event, spot, club, partner, rewards];
}

/// The bottom bar's tab buttons, by shell branch index (0 Home, 1 Map,
/// 2 Chats, 3 Me). AppShell attaches them; journeys spotlight them.
abstract final class GuideTabKeys {
  static final home = GlobalKey(debugLabel: 'guide-tab-home');
  static final map = GlobalKey(debugLabel: 'guide-tab-map');
  static final chats = GlobalKey(debugLabel: 'guide-tab-chats');
  static final me = GlobalKey(debugLabel: 'guide-tab-me');
  static final create = GlobalKey(debugLabel: 'guide-tab-create');

  static GlobalKey? forBranch(int branch) => switch (branch) { 0 => home, 1 => map, 2 => chats, 3 => me, _ => null };
}
