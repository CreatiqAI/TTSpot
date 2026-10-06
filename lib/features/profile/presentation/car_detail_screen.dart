import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/share_links.dart';
import '../../../core/widgets/photo_viewer.dart';
import '../../../core/widgets/share_options_sheet.dart';
import '../../safety/data/safety_repository.dart' show ReportTarget;
import '../../safety/presentation/report_sheet.dart';
import '../../social/application/chat_providers.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/post.dart';
import '../application/car_page_prefs.dart';
import '../application/garage_providers.dart';
import '../application/portrait_providers.dart';
import '../application/portrait_share.dart';
import '../application/profile_providers.dart';
import '../application/toy_providers.dart';
import '../domain/car.dart';
import '../domain/car_mod.dart';
import '../domain/car_toy.dart';
import 'car_page/car_page_model.dart';
import 'car_page/car_page_view.dart';
import 'widgets/portrait_style_sheet.dart';

/// A car's page (`/car/:id`, `ttspot://car/:id`): the toy car in its studio,
/// who the car is, then its album, mods, papers, portraits and posts. The
/// owner gets Edit, today's car and the "…" menu; anyone else gets a
/// read-only page with Message owner and Report. This widget gathers the
/// data and wires the buttons; the page itself is [CarPageView].
class CarDetailScreen extends ConsumerStatefulWidget {
  const CarDetailScreen({super.key, required this.carId});
  final String carId;

  @override
  ConsumerState<CarDetailScreen> createState() => _CarDetailScreenState();
}

class _CarDetailScreenState extends ConsumerState<CarDetailScreen> {
  bool _opening = false;

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.map);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _delete(Car car) async {
    // Every member keeps at least one car (the server refuses it too).
    final cars = ref.read(userCarsProvider(car.ownerId)).value ?? const <Car>[];
    if (cars.length <= 1) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Your garage needs a car'),
          content: const Text('Add another car first, then you can remove this one.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push(Routes.newCar);
              },
              child: const Text('Add a car'),
            ),
          ],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${car.title}?'),
        content: const Text('This deletes the car, its mods, documents and photos from your garage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    final done = await ref.read(carFormControllerProvider.notifier).delete(car.id);
    if (done && mounted) _back();
  }

  /// Straight into the DM with the owner, like the profile's Message button
  /// (the server says so when they only take messages from friends).
  Future<void> _messageOwner(String ownerId) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final conv = await ref.read(chatActionsProvider).openDm(ownerId);
      if (mounted) context.push(Routes.chat(conv));
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _makeToday(Car car) async {
    try {
      await ref.read(carFormControllerProvider.notifier).setDefault(car.id);
      // Today's car moved: every car of mine shows the right tag now.
      for (final c in ref.read(userCarsProvider(car.ownerId)).value ?? const <Car>[]) {
        ref.invalidate(carProvider(c.id));
      }
      ref.invalidate(carProvider(car.id));
      _snack('The ${car.model} is today\'s car.');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  /// A fresh toy from the cover photo, in the car's paint (free, capped a
  /// day per car; the server says when the cap is reached).
  Future<void> _remakeToy(Car car) async {
    try {
      await ref.read(toyActionsProvider).remake(car.id);
      _snack(car.toyPaintStale ? 'Repainting your toy car. About 2 minutes; it swaps in on its own.' : 'Making your toy car again. About 2 minutes; it swaps in on its own.');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _sharePortrait(Car car, CarPortraitMedia m) async {
    final box = context.findRenderObject() as RenderBox?;
    final styleName = m.style?.name ?? 'an AI portrait';
    _snack('Getting it ready…');
    try {
      await sharePortrait(
        url: m.url,
        fileTag: '${car.model}-${m.style?.id ?? 'portrait'}',
        text: 'My ${car.title}, painted in $styleName on TT Spot. https://ttspot.my',
        origin: box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  void _share(Car car) {
    final owner = ref.read(profileProvider(car.ownerId)).value;
    final whose = owner?.username == null ? '' : ' in @${owner!.username}\'s garage';
    showShareOptions(
      context,
      ShareItem(
        type: 'car',
        id: car.id,
        title: car.title,
        carId: car.id,
        text: '${car.title}$whose on TT Spot\n${shareLink('car', car.id)}',
      ),
    );
  }

  /// A portrait tile. The owner: view it, put it on the car (or go back to
  /// the photos), share it. Anyone else: the viewer.
  Future<void> _openPortrait(Car car, bool mine, CarPortraitMedia p, List<CarPortraitMedia> all) async {
    final urls = [for (final m in all) m.url];
    final index = urls.indexOf(p.url).clamp(0, urls.length - 1);
    if (!mine) {
      showPhotoViewer(context, urls, initial: index);
      return;
    }
    final action = await showModalBottomSheet<String>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(AppIcons.arrowsOut), title: const Text('View full screen'), onTap: () => Navigator.pop(ctx, 'view')),
              if (p.wearing)
                ListTile(
                  leading: const Icon(AppIcons.images),
                  title: const Text('Use the photos instead'),
                  subtitle: const Text('Your photo fronts the car again', style: TextStyle(fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, 'photos'),
                )
              else if (p.portrait != null)
                ListTile(
                  leading: const Icon(AppIcons.star),
                  title: const Text('Use this portrait as the car picture'),
                  subtitle: const Text('It fronts the car where a photo would', style: TextStyle(fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, 'use'),
                ),
              ListTile(
                leading: const Icon(AppIcons.shareFat),
                title: const Text('Share this portrait'),
                subtitle: const Text('With a small TT Spot logo', style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'share'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'view':
        showPhotoViewer(context, urls, initial: index);
      case 'use':
        try {
          await ref.read(portraitActionsProvider).choose(p.portrait!);
          _snack('Your ${car.model} now wears the ${p.style?.name ?? 'new'} portrait.');
        } catch (e) {
          _snack(friendlyError(e));
        }
      case 'photos':
        try {
          await ref.read(portraitActionsProvider).usePhotos(car.id);
        } catch (e) {
          _snack(friendlyError(e));
        }
      case 'share':
        await _sharePortrait(car, p);
    }
  }

  /// The owner's "…": the car's own actions, Delete last.
  Future<void> _more(Car car) async {
    // Right after a cold start the switch may still be loading: wait briefly
    // so "New AI portrait" isn't missing from the sheet.
    final settings = ref.read(portraitSettingsProvider).value ??
        await ref.read(portraitSettingsProvider.future).timeout(const Duration(seconds: 3), onTimeout: () => (enabled: false, cost: kDefaultPortraitCost));
    if (!mounted) return;
    final portraitsOn = settings.enabled;
    final cost = settings.cost;
    final action = await showModalBottomSheet<String>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(AppIcons.pencilSimple), title: const Text('Edit car'), subtitle: const Text('Photos, details, number plate', style: TextStyle(fontSize: 12)), onTap: () => Navigator.pop(ctx, 'edit')),
              if (!car.isDefault)
                ListTile(
                  leading: const Icon(AppIcons.checkCircle),
                  title: const Text('Make it today\'s car'),
                  subtitle: const Text('It fronts your profile and drives on the map', style: TextStyle(fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, 'today'),
                ),
              if (portraitsOn)
                ListTile(
                  leading: const Icon(AppIcons.sparkle),
                  title: const Text('New AI portrait'),
                  subtitle: Text(cost > 0 ? '$cost points, plate blanked, ready in about a minute' : 'Plate blanked, ready in about a minute', style: const TextStyle(fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, 'paint'),
                ),
              ListTile(
                leading: const Icon(AppIcons.receipt),
                title: const Text('Road tax and insurance'),
                subtitle: const Text('Expiry dates and reminders, only you see them', style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'papers'),
              ),
              ListTile(
                leading: const Icon(AppIcons.trash, color: AppColors.danger),
                title: const Text('Delete car', style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        context.push(Routes.editCar(car.id));
      case 'today':
        await _makeToday(car);
      case 'paint':
        await showPortraitStyleSheet(context, ref, car);
      case 'papers':
        context.push(Routes.carDocuments(car.id));
      case 'delete':
        await _delete(car);
    }
  }

  /// A visitor's "…": share, or report the owner.
  Future<void> _visitorMore(Car car) async {
    final owner = ref.read(profileProvider(car.ownerId)).value;
    final who = owner?.username == null ? 'the owner' : '@${owner!.username}';
    final action = await showModalBottomSheet<String>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(AppIcons.shareFat), title: const Text('Share this car'), onTap: () => Navigator.pop(ctx, 'share')),
            ListTile(
              leading: const Icon(AppIcons.flag, color: AppColors.danger),
              title: Text('Report $who', style: const TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'share':
        _share(car);
      case 'report':
        await showReportSheet(context, target: ReportTarget.profile, targetId: car.ownerId);
    }
  }

  Future<void> _refresh(Car car, bool mine) async {
    ref.invalidate(carModsProvider(car.id));
    ref.invalidate(postsWhereProvider((column: 'car_id', value: car.id)));
    ref.invalidate(carMeetsProvider(car.id));
    if (mine) {
      ref.invalidate(carDocumentsProvider(car.id));
      ref.invalidate(carPortraitsProvider(car.id));
      ref.invalidate(carToyQuotaProvider(car.id));
    }
    ref.invalidate(carProvider(car.id));
    try {
      await ref.read(carProvider(car.id).future);
    } catch (_) {
      // The page shows the error.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(carFormControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) _snack(friendlyError(next.error!));
    });
    final carAsync = ref.watch(carProvider(widget.carId));
    final me = ref.watch(currentUserIdProvider);

    return carAsync.when(
      loading: () => const _Shell(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => _Shell(child: Text(friendlyError(e), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary))),
      data: (car) {
        if (car == null) {
          return _Shell(child: Text('This car is no longer in the garage.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)));
        }
        final mine = me != null && car.ownerId == me;
        // My car: keep it fresh while its toy is made or repainted (realtime
        // plus a light poll), and catch up on a paint the cap held back.
        if (mine) ref.watch(toyWatcherProvider);
        final mods = ref.watch(carModsProvider(car.id));
        final docs = mine ? ref.watch(carDocumentsProvider(car.id)) : null;
        final portraits = mine ? ref.watch(carPortraitsProvider(car.id)) : null;
        final settings = ref.watch(portraitSettingsProvider).value;
        final posts = ref.watch(postsWhereProvider((column: 'car_id', value: car.id)));
        final meets = ref.watch(carMeetsProvider(car.id));
        final quota = mine && car.toyPaintWaiting ? ref.watch(carToyQuotaProvider(car.id)).value : null;
        // Hidden until the phone has said whether it was closed, so it never flashes.
        final dismissed = mine ? (ref.watch(carPromoDismissalsProvider).value?.contains(car.id) ?? true) : true;

        final data = CarPageData(
          car: car,
          mine: mine,
          owner: ref.watch(profileProvider(car.ownerId)).value,
          mods: mods.value ?? (mods.hasError ? const <CarMod>[] : null),
          documents: docs?.value,
          documentsLoading: docs?.isLoading ?? false,
          // A failed read reads as "none yet" rather than spinning forever.
          portraits: portraits?.value ?? (portraits?.hasError ?? false ? const [] : null),
          portraitsEnabled: settings?.enabled ?? false,
          portraitCost: settings?.cost ?? kDefaultPortraitCost,
          posts: posts.value ?? (posts.hasError ? const <FeedPost>[] : null),
          meets: meets.value,
          promoDismissed: dismissed,
          messaging: _opening,
          toyQuota: quota,
        );

        return CarPageView(
          data: data,
          onRefresh: () => _refresh(car, mine),
          actions: CarPageActions(
            back: _back,
            share: () => _share(car),
            more: mine ? () => _more(car) : () => _visitorMore(car),
            editCar: () => context.push(Routes.editCar(car.id)),
            makeToday: () => _makeToday(car),
            retryToy: mine ? () => _remakeToy(car) : null,
            openPhoto: (urls, i) => showPhotoViewer(context, urls, initial: i),
            addMod: () => context.push(Routes.newCarMod(car.id)),
            openMod: (m) {
              if (mine) {
                context.push(Routes.editCarMod(car.id, m.id));
              } else if (m.photoUrls.isNotEmpty) {
                showPhotoViewer(context, m.photoUrls);
              }
            },
            modPhotos: (m) {
              if (m.photoUrls.isNotEmpty) showPhotoViewer(context, m.photoUrls);
            },
            openPartner: (id) => context.push(Routes.partner(id)),
            postAboutIt: () => context.push(Routes.createPost(PostKind.post, carId: car.id)),
            openPapers: () => context.push(Routes.carDocuments(car.id)),
            newPortrait: () => showPortraitStyleSheet(context, ref, car),
            openPortrait: (p, all) => _openPortrait(car, mine, p, all),
            dismissPromo: () => ref.read(carPromoDismissalsProvider.notifier).dismiss(car.id),
            messageOwner: () => _messageOwner(car.ownerId),
            openOwner: () => context.push(Routes.profile(car.ownerId)),
            openPost: (id) => context.push(Routes.post(id)),
            openEvent: (id) => context.push(Routes.event(id)),
          ),
        );
      },
    );
  }
}

/// Loading, gone or failed: a plain page with a way back.
class _Shell extends StatelessWidget {
  const _Shell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(AppIcons.arrowLeft),
            onPressed: () => context.canPop() ? context.pop() : context.go(Routes.map),
          ),
        ),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: child)),
      );
}
