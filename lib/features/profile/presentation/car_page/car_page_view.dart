import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../guides/me_guides.dart' show CarPageGuideKeys, guideTarget;
import '../../domain/car_mod.dart';
import '../garage/garage_studio.dart' show StudioColors;
import 'car_album.dart';
import 'car_build_tab.dart';
import 'car_hero.dart';
import 'car_page_model.dart';
import 'car_papers_tab.dart';
import 'car_portraits.dart';
import 'car_posts_tab.dart';
import 'car_summary.dart';

/// What the page's buttons do. The screen wires these to routes and sheets;
/// tests record them.
class CarPageActions {
  const CarPageActions({
    required this.back,
    required this.share,
    required this.more,
    required this.editCar,
    required this.makeToday,
    required this.openPhoto,
    required this.addMod,
    required this.openMod,
    required this.modPhotos,
    required this.openPartner,
    required this.postAboutIt,
    required this.openPapers,
    required this.newPortrait,
    required this.openPortrait,
    required this.dismissPromo,
    required this.messageOwner,
    required this.openOwner,
    required this.openPost,
    required this.openEvent,
    this.retryToy,
    this.makeToy,
  });

  final VoidCallback back;
  final VoidCallback share;

  /// The ⋯ sheet: the owner's car menu, a visitor's report (null: none).
  final VoidCallback? more;
  final VoidCallback editCar;
  final VoidCallback makeToday;

  /// The owner's "Try again" after a toy (or repaint) that didn't work.
  final VoidCallback? retryToy;

  /// The owner's "Make my toy car" while toy cars aren't allowed yet (null
  /// hides it).
  final VoidCallback? makeToy;

  /// Full screen, starting at [index] of [urls].
  final void Function(List<String> urls, int index) openPhoto;
  final VoidCallback addMod;

  /// The owner edits it; anyone else sees its photo.
  final void Function(CarMod mod) openMod;
  final void Function(CarMod mod) modPhotos;
  final void Function(String vendorId) openPartner;
  final VoidCallback postAboutIt;
  final VoidCallback openPapers;
  final VoidCallback newPortrait;

  /// A portrait tile: the owner gets its sheet (view, use, share), a visitor
  /// the viewer.
  final void Function(CarPortraitMedia portrait, List<CarPortraitMedia> all) openPortrait;
  final VoidCallback dismissPromo;
  final VoidCallback messageOwner;
  final VoidCallback openOwner;
  final void Function(String postId) openPost;
  final void Function(String eventId) openEvent;
}

/// The car page: the dark studio with the toy car on top (in light and dark
/// mode alike), then on the page's own colours the specs, the owner, the
/// numbers and the buttons, and one clean section after another: Album (the
/// member's real photos), Mods, Papers (owner), Portraits, Posts. A plain bar
/// with the car's name takes over the top once the studio scrolls away.
/// Draws [data] only; no providers, so tests can pump it with fakes.
class CarPageView extends StatefulWidget {
  const CarPageView({super.key, required this.data, required this.actions, this.imageFor = defaultCarImage, this.onRefresh, this.guideKeys});

  final CarPageData data;
  final CarPageActions actions;
  final CarImageResolver imageFor;
  final Future<void> Function()? onRefresh;

  /// TiTi's spotlights on my own car (Mods, Papers, Posts).
  final CarPageGuideKeys? guideKeys;

  @override
  State<CarPageView> createState() => _CarPageViewState();
}

class _CarPageViewState extends State<CarPageView> {
  final _scroll = ScrollController();
  final _heroKey = GlobalKey();

  /// The studio's measured height (it grows with the text size).
  double _heroH = 460;
  bool _history = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _measureHero() {
    final h = _heroKey.currentContext?.size?.height;
    if (h != null && mounted && (h - _heroH).abs() > 0.5) setState(() => _heroH = h);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHero());
    final d = widget.data;
    final a = widget.actions;
    final mq = MediaQuery.of(context);
    final topInset = mq.padding.top;
    final bottomInset = mq.padding.bottom;
    final photos = d.car.photoUrls;
    final mods = d.mods;
    final posts = d.posts;
    final portraits = carPortraitsFor(d.car, portraits: d.portraits);
    final k = d.mine ? widget.guideKeys : null;

    final sections = <Widget>[
      SliverToBoxAdapter(
        child: CarSummary(
          data: d,
          onEdit: a.editCar,
          onMakeToday: a.makeToday,
          onPost: a.postAboutIt,
          onMore: a.more,
          onMessage: a.messageOwner,
          onOwner: a.openOwner,
        ),
      ),
      // Album: the member's own photos (the toy fronts the car instead).
      if (photos.isNotEmpty || d.mine) ...[
        SliverToBoxAdapter(child: CarSectionHeader(title: 'Album', count: photos.length, action: d.mine && photos.isNotEmpty ? 'Edit' : null, onAction: a.editCar)),
        SliverToBoxAdapter(
          child: CarAlbum(
            photos: photos,
            mine: d.mine,
            imageFor: widget.imageFor,
            onOpen: (i) => a.openPhoto(photos, i),
            onAdd: d.mine ? a.editCar : null,
          ),
        ),
      ],
      // Mods (and, with three things to tell, the whole history).
      if (d.mine || (mods?.isNotEmpty ?? false)) ...[
        // The owner's "+ Add a mod" sits under the list.
        SliverToBoxAdapter(child: guideTarget(k?.mods, CarSectionHeader(title: 'Mods', count: mods?.length))),
        SliverToBoxAdapter(
          child: CarBuildTab(
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
        ),
      ],
      // Papers: only ever the owner's.
      if (d.mine) ...[
        SliverToBoxAdapter(child: guideTarget(k?.papers, CarSectionHeader(title: 'Papers', action: (d.documents?.isEmpty ?? true) ? null : 'Edit', onAction: a.openPapers))),
        SliverToBoxAdapter(child: CarPapersTab(documents: d.documents, loading: d.documentsLoading, onEdit: a.openPapers)),
      ],
      if (d.showPortraits) ...[
        SliverToBoxAdapter(
          child: CarSectionHeader(
            title: 'Portraits',
            count: portraits.length,
            action: d.mine && d.portraitsEnabled && portraits.isNotEmpty ? 'New' : null,
            onAction: a.newPortrait,
          ),
        ),
        SliverToBoxAdapter(
          child: CarPortraitsSection(data: d, imageFor: widget.imageFor, onOpen: a.openPortrait, onNew: a.newPortrait, onDismissPromo: a.dismissPromo),
        ),
      ],
      if (d.mine || (posts?.isNotEmpty ?? false)) ...[
        SliverToBoxAdapter(
          child: guideTarget(k?.posts, CarSectionHeader(title: 'Posts', count: posts?.length, action: d.mine && (posts?.isNotEmpty ?? false) ? 'Post' : null, onAction: a.postAboutIt)),
        ),
        SliverToBoxAdapter(child: CarPostsTab(posts: posts, mine: d.mine, onOpen: a.openPost, onPost: a.postAboutIt, imageFor: widget.imageFor)),
      ],
      SliverToBoxAdapter(child: SizedBox(height: 40 + bottomInset)),
    ];

    final scroll = CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: KeyedSubtree(
            key: _heroKey,
            child: CarHero(
              car: d.car,
              mine: d.mine,
              topInset: topInset,
              quota: d.toyQuota,
              onRetryToy: a.retryToy,
              onMakeToy: a.makeToy,
              onLongPress: d.mine ? a.more : null,
            ),
          ),
        ),
        // The page's own colour from here down (the studio stays night).
        DecoratedSliver(
          decoration: BoxDecoration(color: AppColors.bg),
          sliver: SliverMainAxisGroup(slivers: sections),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Night behind the studio, so a pull past the top never shows a
          // white gap above it.
          ListenableBuilder(
            listenable: _scroll,
            builder: (context, _) {
              final offset = _scroll.hasClients ? _scroll.offset : 0.0;
              return Positioned(top: 0, left: 0, right: 0, height: (_heroH - offset).clamp(0.0, double.infinity), child: const ColoredBox(color: StudioColors.page));
            },
          ),
          Positioned.fill(
            child: widget.onRefresh == null
                ? scroll
                : RefreshIndicator(edgeOffset: topInset + CarHero.barHeight, onRefresh: widget.onRefresh!, child: scroll),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ListenableBuilder(
              listenable: _scroll,
              builder: (context, _) {
                final offset = _scroll.hasClients ? _scroll.offset : 0.0;
                // Solid once the studio's lower part slides under the bar.
                final start = _heroH - topInset - CarHero.barHeight - 90;
                final t = ((offset - start) / 60).clamp(0.0, 1.0);
                return _TopBar(
                  t: t,
                  title: d.car.model,
                  topInset: topInset,
                  onBack: a.back,
                  onShare: a.share,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Back, the car's name (once the studio has scrolled away) and Share. Glass
/// buttons on the studio ([t] = 0), a plain bar on the page's colour at 1.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.t, required this.title, required this.topInset, required this.onBack, required this.onShare});
  final double t;
  final String title;
  final double topInset;
  final VoidCallback onBack;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final overlay = t > 0.5 ? AppTheme.systemOverlay : AppTheme.systemOverlay.copyWith(statusBarIconBrightness: Brightness.light, statusBarBrightness: Brightness.dark);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Container(
        height: topInset + CarHero.barHeight,
        padding: EdgeInsets.fromLTRB(12, topInset + 6, 12, 6),
        decoration: BoxDecoration(
          color: AppColors.bg.withValues(alpha: t),
          border: Border(bottom: BorderSide(color: AppColors.divider.withValues(alpha: t))),
        ),
        child: Row(
          children: [
            _BarButton(icon: AppIcons.arrowLeft, tooltip: 'Back', t: t, onTap: onBack),
            const SizedBox(width: 8),
            Expanded(
              child: Opacity(
                opacity: t,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
                  style: TextStyle(fontFamily: AppFonts.display, fontSize: 21, fontWeight: FontWeight.w800, height: 1.1, color: AppColors.textPrimary),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _BarButton(icon: AppIcons.shareFat, tooltip: 'Share', t: t, onTap: onShare),
          ],
        ),
      ),
    );
  }
}

/// A round button: frosted on the studio, plain once the bar is solid.
class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.tooltip, required this.t, required this.onTap});
  final IconData icon;
  final String tooltip;
  final double t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Tooltip(
          message: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10 * (1 - t)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16 * (1 - t))),
              ),
              child: Icon(icon, size: 20, color: Color.lerp(Colors.white, AppColors.textPrimary, t)),
            ),
          ),
        ),
      );
}
