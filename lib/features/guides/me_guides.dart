import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/guide/guide.dart';
import '../../core/guide/guide_controller.dart';
import '../../core/theme/titi.dart';

// TiTi guides for Me and cards (docs/titi-guides-plan.md): the first-box
// journey (open box → Me → Cards tab → collection, trade, points, box,
// prizes) and the first-visit guides for the profile, the garage, my car's
// page, points, cards and rewards. Keys are created by each screen's State
// (one holder per screen below) and handed in here; copy stays short.

/// Where the member is in the first-box journey ([guideJourneyProvider]).
abstract final class FirstBoxStage {
  /// Sent to Me: spotlight the Cards tab and wait for the tap.
  static const me = 'first_box:me';

  /// On the Cards tab: the walk through what cards can do.
  static const cards = 'first_box:cards';
}

// --------------------------------------------------------- the journey ---

/// The first-box journey's "Tap Cards" step on Me. A tap on the tab moves the
/// journey to [FirstBoxStage.cards] (the tab's own walk); anything else ends it.
Future<GuideResult> runFirstBoxCardsTabStep(BuildContext context, WidgetRef ref, GlobalKey cardsTab) async {
  final journey = ref.read(guideJourneyProvider.notifier);
  final result = await ref.read(guideControllerProvider).showOnce(context, MeGuides.firstBoxCardsTab(cardsTab), force: true);
  journey.go(result == GuideResult.tappedTarget ? FirstBoxStage.cards : null);
  return result;
}

/// The first-box journey's last part, on my Cards tab: collection, trade,
/// points, the box, prizes. However it ends, the journey is over.
Future<GuideResult> runFirstBoxTour(BuildContext context, WidgetRef ref, CardsTabGuideKeys cards, {required GlobalKey points, int boxCost = MeGuides.defaultBoxCost}) async {
  final journey = ref.read(guideJourneyProvider.notifier);
  final controller = ref.read(guideControllerProvider);
  final result = await controller.showOnce(context, MeGuides.firstBoxTour(cards, points: points, boxCost: boxCost), force: true);
  journey.go(null);
  // The journey already walked through cards: don't repeat it on the next visit.
  if (result != GuideResult.notShown) await controller.markSeen(GuideIds.cards);
  return result;
}

// ------------------------------------------------------------------ keys ---

/// [child] under [key] (a TiTi guide target), or just [child] without one,
/// so the screens look and behave the same either way.
Widget guideTarget(GlobalKey? key, Widget child) => key == null ? child : KeyedSubtree(key: key, child: child);

/// The Me tab (my own profile): header pills, badges, QR, the Cards tab.
class ProfileGuideKeys {
  final garage = GlobalKey(debugLabel: 'guide-profile-garage');
  final points = GlobalKey(debugLabel: 'guide-profile-points');
  final badges = GlobalKey(debugLabel: 'guide-profile-badges');
  final qr = GlobalKey(debugLabel: 'guide-profile-qr');
  final cardsTab = GlobalKey(debugLabel: 'guide-profile-cards-tab');
}

/// My Cards tab on the profile: the grid, Trades, Prizes, Get a blind box.
class CardsTabGuideKeys {
  final grid = GlobalKey(debugLabel: 'guide-cards-grid');
  final trades = GlobalKey(debugLabel: 'guide-cards-trades');
  final prizes = GlobalKey(debugLabel: 'guide-cards-prizes');
  final getBox = GlobalKey(debugLabel: 'guide-cards-get-box');
}

/// The Cards screen (/cards): its three tabs.
class CardsScreenGuideKeys {
  final collection = GlobalKey(debugLabel: 'guide-cards-screen-collection');
  final trades = GlobalKey(debugLabel: 'guide-cards-screen-trades');
  final prizes = GlobalKey(debugLabel: 'guide-cards-screen-prizes');
}

/// My garage: the toy car, the + button, Open car.
class GarageGuideKeys {
  final toy = GlobalKey(debugLabel: 'guide-garage-toy');
  final add = GlobalKey(debugLabel: 'guide-garage-add');
  final open = GlobalKey(debugLabel: 'guide-garage-open');
}

/// My car's page: the Mods, Papers and Posts sections.
class CarPageGuideKeys {
  final mods = GlobalKey(debugLabel: 'guide-car-mods');
  final papers = GlobalKey(debugLabel: 'guide-car-papers');
  final posts = GlobalKey(debugLabel: 'guide-car-posts');
}

/// Points: the balance, How to earn, the weekly post row.
class PointsGuideKeys {
  final balance = GlobalKey(debugLabel: 'guide-points-balance');
  final earn = GlobalKey(debugLabel: 'guide-points-earn');
  final weekly = GlobalKey(debugLabel: 'guide-points-weekly');
}

/// Rewards: its three tabs.
class RewardsGuideKeys {
  final partners = GlobalKey(debugLabel: 'guide-rewards-partners');
  final vouchers = GlobalKey(debugLabel: 'guide-rewards-vouchers');
  final wallet = GlobalKey(debugLabel: 'guide-rewards-wallet');
}

// ---------------------------------------------------------------- guides ---

abstract final class MeGuides {
  /// What a blind box costs when the settings haven't loaded.
  static const defaultBoxCost = 100;

  // ------------------------------------------------------- first box ---

  /// Step 1, on the open box screen ("What can cards do?"). Finishing it
  /// sends the member to Me with the journey at [FirstBoxStage.me].
  static Guide firstBoxIntro() => const Guide(
        id: GuideIds.firstBox,
        steps: [
          GuideStep(
            pose: TitiPose.celebrate,
            title: 'Nice pull!',
            body: 'Cards are collectibles. Collect sets, trade with friends, and some unlock real prizes.',
            nextLabel: 'Show me',
          ),
        ],
      );

  /// On Me: the member taps the Cards tab themselves.
  static Guide firstBoxCardsTab(GlobalKey cardsTab) => Guide(
        id: GuideIds.firstBox,
        steps: [
          GuideStep(
            target: cardsTab,
            pose: TitiPose.gift,
            title: 'Your cards live here',
            body: 'Tap Cards to see your collection.',
            tapTarget: true,
          ),
        ],
      );

  /// On the Cards tab: collection, trade, points, the box, prizes, done.
  static Guide firstBoxTour(CardsTabGuideKeys cards, {required GlobalKey points, int boxCost = defaultBoxCost}) => Guide(
        id: GuideIds.firstBox,
        steps: [
          GuideStep(
            target: cards.grid,
            pose: TitiPose.trophy,
            title: 'Your collection',
            body: 'Every card you pull lands here. Finish a set for bragging rights.',
          ),
          GuideStep(
            target: cards.trades,
            pose: TitiPose.heart,
            title: 'Trade with friends',
            body: 'Pick your card, pick theirs, send. They accept, you swap.',
          ),
          GuideStep(
            target: points,
            pose: TitiPose.mapPin,
            title: 'Points',
            body: 'Meets, spots, one post a week and badges pay 10. Each friend you bring pays 5.',
          ),
          GuideStep(
            target: cards.getBox,
            pose: TitiPose.gift,
            title: 'Blind boxes',
            body: '$boxCost points buys a box. Open it for a new card.',
          ),
          GuideStep(
            target: cards.prizes,
            pose: TitiPose.voucher,
            title: 'Prizes',
            body: 'Some cards redeem real rewards at partner shops. Check Prizes.',
          ),
          const GuideStep(
            pose: TitiPose.thumbsUp,
            title: "You're all set!",
            body: "Explore the app. I'll pop in with tips on new pages.",
          ),
        ],
      );

  // --------------------------------------------------------- profile ---

  /// Me, first visit. With [showCards] (the member never had the first-box
  /// walk) the Cards tab takes the badges' place, so it stays at 4 steps.
  static Guide profile(ProfileGuideKeys k, {bool showCards = false}) => Guide(
        id: GuideIds.profile,
        steps: [
          GuideStep(
            target: k.garage,
            pose: TitiPose.wrench,
            title: 'My garage',
            body: 'Your cars live here, each with a toy model made from your photo.',
          ),
          GuideStep(
            target: k.points,
            pose: TitiPose.trophy,
            title: 'Your points',
            body: 'Earn them at meets and spots. Tap to see every way to earn.',
          ),
          if (showCards)
            GuideStep(
              target: k.cardsTab,
              pose: TitiPose.gift,
              title: 'Your cards',
              body: 'Blind box cards to collect and trade. Find them under Cards.',
            )
          else
            GuideStep(
              target: k.badges,
              pose: TitiPose.celebrate,
              title: 'Badges',
              body: 'Earn them as you go. Every new badge or tier pays 10 points.',
            ),
          GuideStep(
            target: k.qr,
            pose: TitiPose.phone,
            title: 'Your QR code',
            body: 'Friends scan it to add you. Settings sit in the menu up top.',
          ),
        ],
      );

  // ---------------------------------------------------------- garage ---

  static Guide garage(GarageGuideKeys k) => Guide(
        id: GuideIds.garage,
        steps: [
          GuideStep(
            target: k.toy,
            pose: TitiPose.camera,
            title: 'Your toy car',
            body: "Made from your photo. Today's car drives it on the map.",
            radius: 28,
          ),
          GuideStep(
            target: k.add,
            pose: TitiPose.wrench,
            title: 'Add a car',
            body: 'Park every car you own. Tap + to add one.',
            circle: true,
          ),
          GuideStep(
            target: k.open,
            pose: TitiPose.thumbsUp,
            title: 'Open the car page',
            body: 'Mods, papers, photos and posts for this car, all in one place.',
            radius: 26,
          ),
        ],
      );

  // -------------------------------------------------------- car page ---

  static Guide carPage(CarPageGuideKeys k) => Guide(
        id: GuideIds.carPage,
        steps: [
          GuideStep(
            target: k.mods,
            pose: TitiPose.wrench,
            title: 'Your mods log',
            body: 'Log each mod with its cost. Your build and spend add up here.',
          ),
          GuideStep(
            target: k.papers,
            pose: TitiPose.bell,
            title: 'Papers and reminders',
            body: 'Road tax and insurance dates. Only you see them, and you get a reminder.',
          ),
          GuideStep(
            target: k.posts,
            pose: TitiPose.camera,
            title: 'Posts',
            body: 'Share a post about this car. They all gather here.',
          ),
        ],
      );

  // ---------------------------------------------------------- points ---

  static Guide points(PointsGuideKeys k, {int boxCost = defaultBoxCost}) => Guide(
        id: GuideIds.points,
        steps: [
          GuideStep(
            target: k.earn,
            pose: TitiPose.mapPin,
            title: 'How to earn',
            body: 'Meets, spots, a weekly post and badges pay 10. Tap a row to go earn.',
          ),
          GuideStep(
            target: k.weekly,
            pose: TitiPose.calendar,
            title: 'Weekly reset',
            body: 'The post and spot limits reset every Friday at 6 PM.',
          ),
          GuideStep(
            target: k.balance,
            pose: TitiPose.gift,
            title: 'Blind boxes',
            body: '$boxCost points buys a blind box. Get one from Cards on your profile.',
          ),
        ],
      );

  // ----------------------------------------------------------- cards ---

  /// The Cards screen's tabs, or my profile's Cards tab (grid, Trades,
  /// Prizes): the same three things.
  static Guide cards({required GlobalKey collection, required GlobalKey trades, required GlobalKey prizes}) => Guide(
        id: GuideIds.cards,
        steps: [
          GuideStep(
            target: collection,
            pose: TitiPose.trophy,
            title: 'Your collection',
            body: 'Every card you own, and the ones still missing. Tap one for a closer look.',
          ),
          GuideStep(
            target: trades,
            pose: TitiPose.heart,
            title: 'Trade with friends',
            body: 'Swap cards with friends. Offers they send you wait here.',
          ),
          GuideStep(
            target: prizes,
            pose: TitiPose.voucher,
            title: 'Prizes',
            body: 'Spend cards on real rewards at partner shops.',
          ),
        ],
      );

  // --------------------------------------------------------- rewards ---

  static Guide rewards(RewardsGuideKeys k) => Guide(
        id: GuideIds.rewards,
        steps: [
          GuideStep(
            target: k.vouchers,
            pose: TitiPose.voucher,
            title: 'Vouchers',
            body: 'Spend your points on vouchers from partner shops.',
          ),
          GuideStep(
            target: k.wallet,
            pose: TitiPose.phone,
            title: 'My vouchers',
            body: 'Claimed vouchers wait here. Show the QR at the counter.',
          ),
          GuideStep(
            target: k.partners,
            pose: TitiPose.mapPin,
            title: 'Partners',
            body: 'Shops that welcome members. Check in there for points too.',
          ),
        ],
      );
}
