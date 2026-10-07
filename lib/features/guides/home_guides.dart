import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/features.dart';
import '../../core/guide/guide.dart';
import '../../core/guide/guide_controller.dart';
import '../../core/guide/guide_on_first_view.dart';
import '../../core/theme/titi.dart';
import '../social/application/chat_providers.dart';
import '../social/application/social_providers.dart';

// TiTi guides for Home, the + sheet, Chats and the TiTi chat
// (docs/titi-guides-plan.md). The screens attach these keys; the guides
// below spotlight them. Copy: buddy voice, short.

/// Home (ExploreScreen): the feed switch, the Clubs & Events tab, the first
/// post tile of For you and the search button.
abstract final class HomeGuideKeys {
  static final feedSwitch = GlobalKey(debugLabel: 'guide-home-feed-switch');
  static final clubsEvents = GlobalKey(debugLabel: 'guide-home-clubs-events');
  static final firstPost = GlobalKey(debugLabel: 'guide-home-first-post');
  static final search = GlobalKey(debugLabel: 'guide-home-search');
}

/// The + sheet (personal account): the TT now hero and the tiles under it.
abstract final class CreateGuideKeys {
  static final ttNow = GlobalKey(debugLabel: 'guide-create-tt-now');
  static final make = GlobalKey(debugLabel: 'guide-create-make');
}

/// Chats (InboxScreen): TiTi's pinned row and the Activity tab.
abstract final class ChatsGuideKeys {
  static final titi = GlobalKey(debugLabel: 'guide-chats-titi');
  static final activity = GlobalKey(debugLabel: 'guide-chats-activity');
}

/// The TiTi chat: the input box and the starter chips (empty chat only).
abstract final class TitiChatGuideKeys {
  static final input = GlobalKey(debugLabel: 'guide-titi-input');
  static final starters = GlobalKey(debugLabel: 'guide-titi-starters');
}

/// Home. The post step only when a post tile is actually built (For you
/// has posts); otherwise it is left out, never pointed at nothing.
Guide homeGuide({bool? hasPost}) => Guide(
      id: GuideIds.home,
      steps: [
        GuideStep(
          target: HomeGuideKeys.feedSwitch,
          title: 'Your feed',
          body: 'For you mixes rides we think you will like. Following is friends, follows and your clubs.',
          pose: TitiPose.wave,
          radius: 999,
        ),
        GuideStep(
          target: HomeGuideKeys.clubsEvents,
          title: 'Clubs & Events',
          body: "Find meets and car clubs here. Filters show what's on, official or underground.",
          pose: TitiPose.calendar,
        ),
        if (hasPost ?? HomeGuideKeys.firstPost.currentContext != null)
          GuideStep(
            target: HomeGuideKeys.firstPost,
            title: 'Like what you see?',
            body: "Open a post to like, save or share it. Long-press one if it's not your thing.",
            pose: TitiPose.heart,
          ),
        GuideStep(
          target: HomeGuideKeys.search,
          title: 'Search anything',
          body: 'Look up people, clubs, posts and #tags.',
          pose: TitiPose.magnifier,
          circle: true,
        ),
      ],
    );

/// The + sheet, personal account: TT now first, then the rest.
Guide createGuide({bool social = kSocialFeed}) => Guide(
      id: GuideIds.create,
      steps: [
        GuideStep(
          target: CreateGuideKeys.ttNow,
          title: 'TT now',
          body: 'Going for teh tarik now? One tap tells friends nearby.',
          pose: TitiPose.rolling,
          radius: 22,
        ),
        GuideStep(
          target: CreateGuideKeys.make,
          title: 'Or make something',
          body: social ? 'Post your ride, drop a 24-hour moment, or plan a TT session for later.' : 'Drop a 24-hour moment, or plan a TT session for later.',
          pose: TitiPose.camera,
          radius: 22,
        ),
      ],
    );

/// Chats, personal account.
Guide chatsGuide() => Guide(
      id: GuideIds.chats,
      steps: [
        GuideStep(
          target: ChatsGuideKeys.titi,
          title: 'Ask me anything',
          body: "I'm pinned up top. Meets nearby, fuel prices, road tax, your points… just ask!",
          pose: TitiPose.chat,
          radius: 12,
        ),
        GuideStep(
          target: ChatsGuideKeys.activity,
          title: 'Your activity',
          body: 'Likes, friend requests, meet invites and meet updates land here.',
          pose: TitiPose.bell,
        ),
      ],
    );

/// The TiTi chat. The starters step only while the chat is empty (the chips
/// fade out after the first question).
Guide titiChatGuide({required bool starters}) => Guide(
      id: GuideIds.titiChat,
      steps: [
        GuideStep(
          target: TitiChatGuideKeys.input,
          title: 'Ask TiTi anything',
          body: 'Meets near you, fuel prices, road tax dates, your points. Send me a car photo too!',
          pose: TitiPose.chat,
          radius: 22,
        ),
        if (starters)
          GuideStep(
            target: TitiChatGuideKeys.starters,
            title: 'Not sure? Tap one',
            body: 'These get you going in one tap.',
            pose: TitiPose.thumbsUp,
          ),
      ],
    );

/// Wraps Home: the guide once For you's first page is in, and never during
/// a journey (the first-box walk).
class HomeGuideGate extends ConsumerWidget {
  const HomeGuideGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(forYouFeedProvider.select((f) => f.hasValue));
    final journey = ref.watch(guideJourneyProvider);
    return GuideOnFirstView(id: GuideIds.home, ready: loaded && journey == null, build: homeGuide, child: child);
  }
}

/// Wraps the personal Chats tab: the guide once the inbox is in.
class ChatsGuideGate extends ConsumerWidget {
  const ChatsGuideGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(inboxProvider.select((f) => f.hasValue));
    final journey = ref.watch(guideJourneyProvider);
    return GuideOnFirstView(id: GuideIds.chats, ready: loaded && journey == null, build: chatsGuide, child: child);
  }
}

/// Wraps the + sheet's body: the first time it opens (personal account),
/// once the sheet has finished sliding in, the create guide shows over it
/// (the guide uses the root overlay). The sheet works as before afterwards.
class CreateGuideTrigger extends ConsumerStatefulWidget {
  const CreateGuideTrigger({super.key, required this.enabled, required this.child, this.settle = const Duration(milliseconds: 150)});

  /// Personal account only: club and partner sheets have no TT now.
  final bool enabled;
  final Widget child;

  /// A beat after the slide-in, so the sheet is still.
  final Duration settle;

  @override
  ConsumerState<CreateGuideTrigger> createState() => _CreateGuideTriggerState();
}

class _CreateGuideTriggerState extends ConsumerState<CreateGuideTrigger> {
  Animation<double>? _route;
  var _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_route != null || _done || !widget.enabled) return;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.status == AnimationStatus.completed) {
      _done = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _show());
      return;
    }
    _route = anim..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed || _done) return;
    _done = true;
    _route?.removeStatusListener(_onStatus);
    _show();
  }

  Future<void> _show() async {
    await Future<void>.delayed(widget.settle);
    if (!mounted || ref.read(guideJourneyProvider) != null) return;
    // The sheet is closing (swiped away in the meantime): not now.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    await ref.read(guideControllerProvider).showOnce(context, createGuide());
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
