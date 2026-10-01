import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/car_mod.dart';
import 'car_build_tab.dart';
import 'car_identity.dart';
import 'car_page_model.dart';
import 'car_papers_tab.dart';
import 'car_posts_tab.dart';
import 'car_stage.dart';

enum CarTab { build, papers, posts }

/// What the page's buttons do. The screen wires these to routes and sheets;
/// tests record them.
class CarPageActions {
  const CarPageActions({
    required this.back,
    required this.share,
    required this.more,
    required this.openMedia,
    required this.addMod,
    required this.openMod,
    required this.modPhotos,
    required this.openPartner,
    required this.postAboutIt,
    required this.openPapers,
    required this.paint,
    required this.dismissPromo,
    required this.messageOwner,
    required this.openOwner,
    required this.openPost,
    required this.openEvent,
  });

  final VoidCallback back;

  /// With what's on the stage (a portrait can be shared on its own).
  final void Function(CarMedia? onStage) share;

  /// The "…" sheet (null for visitors with nothing in it).
  final void Function(CarMedia? onStage)? more;

  /// Full screen, at the media's own shape.
  final void Function(List<CarMedia> media, int index) openMedia;
  final VoidCallback addMod;

  /// The owner edits it; anyone else sees its photo.
  final void Function(CarMod mod) openMod;
  final void Function(CarMod mod) modPhotos;
  final void Function(String vendorId) openPartner;
  final VoidCallback postAboutIt;
  final VoidCallback openPapers;
  final VoidCallback paint;
  final VoidCallback dismissPromo;
  final VoidCallback messageOwner;
  final VoidCallback openOwner;
  final void Function(String postId) openPost;
  final void Function(String eventId) openEvent;
}

/// The car page body: the bay with its media, the strip, who the car is, its
/// numbers, the tabs and the fixed bottom bar. Draws [data] only; no
/// providers, so tests can pump it with fakes.
class CarPageView extends StatefulWidget {
  const CarPageView({super.key, required this.data, required this.actions, this.imageFor = defaultCarImage, this.onRefresh});

  final CarPageData data;
  final CarPageActions actions;
  final CarImageResolver imageFor;
  final Future<void> Function()? onRefresh;

  @override
  State<CarPageView> createState() => _CarPageViewState();
}

class _CarPageViewState extends State<CarPageView> {
  /// The media on stage, by URL, so a reload keeps it.
  String? _onStage;
  CarTab? _tab;
  bool _history = false;

  List<CarTab> _tabs(CarPageData d) => d.mine
      ? const [CarTab.build, CarTab.papers, CarTab.posts]
      : [if (d.mods?.isNotEmpty ?? false) CarTab.build, if (d.posts?.isNotEmpty ?? false) CarTab.posts];

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final a = widget.actions;
    final media = carMediaFor(d.car, portraits: d.portraits);
    var selected = _onStage == null ? -1 : media.indexWhere((m) => m.url == _onStage);
    if (selected < 0) selected = initialMediaIndex(d.car, media);
    final onStage = media.isEmpty ? null : media[selected];

    final tabs = _tabs(d);
    final tab = tabs.contains(_tab) ? _tab! : tabs.firstOrNull;

    final mq = MediaQuery.of(context);
    final topInset = mq.padding.top;
    final bottomInset = mq.padding.bottom;
    final stageH = (mq.size.width * 0.76).clamp(270.0, 330.0);
    final tabH = (mq.textScaler.scale(14) + 30).clamp(46.0, 64.0);
    final news = d.portraitNews;

    final slivers = <Widget>[
      SliverPersistentHeader(
        pinned: true,
        delegate: CarStageDelegate(
          car: d.car,
          media: onStage,
          mine: d.mine,
          topInset: topInset,
          stageHeight: stageH,
          imageFor: widget.imageFor,
          bayIndex: d.bayIndex,
          onBack: a.back,
          onShare: () => a.share(onStage),
          onMore: a.more == null ? null : () => a.more!(onStage),
          onOpen: () => a.openMedia(media, selected),
        ),
      ),
      if (media.length > 1)
        SliverToBoxAdapter(
          child: CarMediaStrip(media: media, selected: selected, imageFor: widget.imageFor, onPick: (i) => setState(() => _onStage = media[i].url)),
        ),
      if (news.isNotEmpty) SliverToBoxAdapter(child: PortraitNews(car: d.car, portraits: news, onRetry: a.paint)),
      SliverToBoxAdapter(child: CarIdentity(car: d.car, top: media.length > 1 || news.isNotEmpty ? 16 : 8)),
      SliverToBoxAdapter(child: CarStatsCard(data: d)),
      if (d.showPromo) SliverToBoxAdapter(child: MakeItLookProCard(car: d.car, cost: d.portraitCost, onPaint: a.paint, onDismiss: a.dismissPromo)),
      if (tabs.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(tabs: tabs, current: tab!, height: tabH, onPick: (t) => setState(() => _tab = t)),
        ),
        SliverToBoxAdapter(
          child: switch (tab) {
            CarTab.build => CarBuildTab(
                data: d,
                history: _history,
                onHistory: (v) => setState(() => _history = v),
                onAddMod: a.addMod,
                onOpenMod: a.openMod,
                onModPhotos: a.modPhotos,
                onPartner: a.openPartner,
                onMeet: a.openEvent,
                imageFor: widget.imageFor,
              ),
            CarTab.papers => CarPapersTab(documents: d.documents, loading: d.documentsLoading, onEdit: a.openPapers),
            CarTab.posts => CarPostsTab(posts: d.posts, mine: d.mine, onOpen: a.openPost, onPost: a.postAboutIt, imageFor: widget.imageFor),
          },
        ),
      ],
      if (!d.mine) SliverToBoxAdapter(child: CarOwnerRow(ownerId: d.car.ownerId, owner: d.owner, onTap: a.openOwner)),
      // Room for the bottom bar.
      SliverToBoxAdapter(child: SizedBox(height: 96 + bottomInset)),
    ];

    final scroll = CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: slivers);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: widget.onRefresh == null ? scroll : RefreshIndicator(edgeOffset: topInset + 56, onRefresh: widget.onRefresh!, child: scroll),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(
              mine: d.mine,
              messaging: d.messaging,
              bottomInset: bottomInset,
              onPost: a.postAboutIt,
              onAddMod: a.addMod,
              onMessage: a.messageOwner,
              onShare: () => a.share(onStage),
            ),
          ),
        ],
      ),
    );
  }
}

/// Build · Papers · Posts, pinned under the top bar while the page scrolls.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate({required this.tabs, required this.current, required this.height, required this.onPick});
  final List<CarTab> tabs;
  final CarTab current;
  final double height;
  final ValueChanged<CarTab> onPick;

  static const _labels = {CarTab.build: 'Build', CarTab.papers: 'Papers', CarTab.posts: 'Posts'};

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  // Always: the colours come from AppColors, which flips with the theme.
  @override
  bool shouldRebuild(_TabBarDelegate old) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        key: const ValueKey('car-tabs'),
        decoration: BoxDecoration(color: AppColors.bg, border: Border(bottom: BorderSide(color: AppColors.divider))),
        child: Row(
          children: [
            for (final t in tabs)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: t == current,
                  child: InkWell(
                    onTap: () => onPick(t),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: t == current ? AppColors.brand : Colors.transparent, width: 2.5)),
                      ),
                      child: Text(
                        _labels[t]!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t == current ? AppColors.textPrimary : AppColors.textMuted),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// The fixed bar at the bottom: the owner posts or logs a mod; a visitor
/// messages the owner or shares the car.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.mine,
    required this.messaging,
    required this.bottomInset,
    required this.onPost,
    required this.onAddMod,
    required this.onMessage,
    required this.onShare,
  });

  final bool mine;
  final bool messaging;
  final double bottomInset;
  final VoidCallback onPost;
  final VoidCallback onAddMod;
  final VoidCallback onMessage;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    ButtonStyle filled(Color bg, Color fg) => FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.6),
          disabledForegroundColor: fg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        );
    Widget label(String text) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false);
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.94),
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: mine
            ? [
                Expanded(child: FilledButton(onPressed: onPost, style: filled(AppColors.textPrimary, AppColors.onInk), child: label('Post about it'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: onAddMod, style: filled(AppColors.brand, Colors.white), child: label('Add a mod'))),
              ]
            : [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: messaging ? null : onMessage,
                    style: filled(AppColors.brand, Colors.white),
                    icon: const Icon(AppIcons.chatCircle, size: 18),
                    label: label('Message owner'),
                  ),
                ),
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: 'Share this car',
                  excludeSemantics: true,
                  child: OutlinedButton(
                    onPressed: onShare,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(52, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Icon(AppIcons.shareFat, size: 20),
                  ),
                ),
              ],
      ),
    );
  }
}
