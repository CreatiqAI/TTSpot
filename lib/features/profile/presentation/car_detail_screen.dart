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
import '../../social/application/chat_providers.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/post.dart';
import '../application/car_page_prefs.dart';
import '../application/garage_providers.dart';
import '../application/portrait_providers.dart';
import '../application/portrait_share.dart';
import '../application/profile_providers.dart';
import '../domain/car.dart';
import '../domain/car_mod.dart';
import 'car_page/car_page_model.dart';
import 'car_page/car_page_view.dart';
import 'garage/garage_body.dart' show garageOrder;
import 'widgets/car_actions_sheet.dart';
import 'widgets/portrait_style_sheet.dart';

/// A car's page (`/car/:id`, `ttspot://car/:id`): the garage bay with its
/// cut-out, photos and portraits, who the car is, its mods, papers and posts.
/// The owner gets the "…" actions and Post / Add a mod; anyone else gets a
/// read-only page with Message owner. This widget gathers the data; the page
/// itself is [CarPageView].
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

  Future<void> _sharePortrait(Car car, CarMedia m) async {
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

  void _share(Car car, CarMedia? onStage) {
    final owner = ref.read(profileProvider(car.ownerId)).value;
    final whose = owner?.username == null ? '' : ' in @${owner!.username}\'s garage';
    final mine = car.ownerId == ref.read(currentUserIdProvider);
    showShareOptions(
      context,
      ShareItem(
        type: 'car',
        id: car.id,
        title: car.title,
        carId: car.id,
        text: '${car.title}$whose on TT Spot\n${shareLink('car', car.id)}',
      ),
      extras: [
        if (onStage != null && onStage.isPortrait && mine)
          ShareExtra(
            icon: AppIcons.sparkle,
            label: 'This portrait',
            subtitle: 'The picture itself, with a small TT Spot logo',
            onTap: () => _sharePortrait(car, onStage),
          ),
      ],
    );
  }

  /// The owner's "…": what's on the stage first (a portrait: use it, share
  /// it), then the car's own actions, Delete last.
  Future<void> _more(Car car, CarMedia? onStage) async {
    // Right after a cold start the switch may still be loading: wait briefly
    // so "New AI portrait" isn't missing from the sheet.
    final settings = ref.read(portraitSettingsProvider).value ??
        await ref.read(portraitSettingsProvider.future).timeout(const Duration(seconds: 3), onTimeout: () => (enabled: false, cost: kDefaultPortraitCost));
    if (!mounted) return;
    final portraitsOn = settings.enabled;
    final cost = settings.cost;
    final portrait = onStage != null && onStage.isPortrait ? onStage : null;
    final wearing = portrait != null && car.portraitUrl == portrait.url;
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
              if (portrait != null) ...[
                if (wearing)
                  ListTile(
                    leading: const Icon(AppIcons.images),
                    title: const Text('Use the photos instead'),
                    subtitle: const Text('Your photo fronts the car again', style: TextStyle(fontSize: 12)),
                    onTap: () => Navigator.pop(ctx, 'photos'),
                  )
                else if (portrait.portrait != null)
                  ListTile(
                    leading: const Icon(AppIcons.star),
                    title: const Text('Use this portrait as the car picture'),
                    subtitle: const Text('It fronts the car on your profile and the map', style: TextStyle(fontSize: 12)),
                    onTap: () => Navigator.pop(ctx, 'use'),
                  ),
                ListTile(
                  leading: const Icon(AppIcons.shareFat),
                  title: const Text('Share this portrait'),
                  subtitle: const Text('With a small TT Spot logo', style: TextStyle(fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, 'share-portrait'),
                ),
                const Divider(height: 8),
              ],
              ListTile(leading: const Icon(AppIcons.pencilSimple), title: const Text('Edit car'), onTap: () => Navigator.pop(ctx, 'edit')),
              if (!car.isDefault)
                ListTile(
                  leading: const Icon(AppIcons.checkCircle),
                  title: const Text('Make it today\'s car'),
                  subtitle: const Text('It fronts your profile and drives on the map', style: TextStyle(fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, 'today'),
                ),
              ListTile(
                leading: Icon(car.garageStyle == 'card' ? AppIcons.cards : AppIcons.scissors),
                title: const Text('Garage look'),
                subtitle: Text(garageLookLabel(car), style: const TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'look'),
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
      case 'use':
        try {
          await ref.read(portraitActionsProvider).choose(portrait!.portrait!);
          _snack('Your ${car.model} now wears the ${portrait.style?.name ?? 'new'} portrait.');
        } catch (e) {
          _snack(friendlyError(e));
        }
      case 'photos':
        try {
          await ref.read(portraitActionsProvider).usePhotos(car.id);
        } catch (e) {
          _snack(friendlyError(e));
        }
      case 'share-portrait':
        await _sharePortrait(car, portrait!);
      case 'edit':
        context.push(Routes.editCar(car.id));
      case 'today':
        await _makeToday(car);
      case 'look':
        await showGarageLookSheet(context, ref, car);
      case 'paint':
        await showPortraitStyleSheet(context, ref, car);
      case 'papers':
        context.push(Routes.carDocuments(car.id));
      case 'delete':
        await _delete(car);
    }
  }

  Future<void> _refresh(Car car, bool mine) async {
    ref.invalidate(carModsProvider(car.id));
    ref.invalidate(postsWhereProvider((column: 'car_id', value: car.id)));
    ref.invalidate(carMeetsProvider(car.id));
    if (mine) {
      ref.invalidate(carDocumentsProvider(car.id));
      ref.invalidate(carPortraitsProvider(car.id));
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
        final mods = ref.watch(carModsProvider(car.id));
        final docs = mine ? ref.watch(carDocumentsProvider(car.id)) : null;
        final portraits = mine ? ref.watch(carPortraitsProvider(car.id)) : null;
        final settings = ref.watch(portraitSettingsProvider).value;
        final posts = ref.watch(postsWhereProvider((column: 'car_id', value: car.id)));
        final meets = ref.watch(carMeetsProvider(car.id));
        final ownerCars = ref.watch(userCarsProvider(car.ownerId)).value;
        final bay = ownerCars == null ? -1 : garageOrder(ownerCars).indexWhere((c) => c.id == car.id);
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
          bayIndex: bay < 0 ? null : bay,
          promoDismissed: dismissed,
          messaging: _opening,
        );

        return CarPageView(
          data: data,
          onRefresh: () => _refresh(car, mine),
          actions: CarPageActions(
            back: _back,
            share: (m) => _share(car, m),
            more: mine ? (m) => _more(car, m) : null,
            openMedia: (media, i) => showPhotoViewer(context, [for (final m in media) m.url], initial: i),
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
            paint: () => showPortraitStyleSheet(context, ref, car),
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
