import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/geo.dart';
import '../../../events/domain/event.dart';
import '../../application/map_providers.dart';

/// Draggable dark sheet over the map: search bar + events sorted by distance.
/// Three snap points: peek / half / full.
class MapEventSheet extends ConsumerWidget {
  const MapEventSheet({super.key, required this.controller});
  final DraggableScrollableController controller;

  static const peek = 0.17;
  static const half = 0.5;
  static const full = 0.92;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(visibleMapEventsProvider);
    final origin = ref.watch(mapOriginProvider);
    final hasSearch = ref.watch(mapSearchProvider).isNotEmpty;

    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: peek,
      minChildSize: peek,
      maxChildSize: full,
      snap: true,
      snapSizes: const [peek, half, full],
      builder: (context, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: MapPalette.of(context).surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(color: MapPalette.of(context).shadow, blurRadius: 24, offset: const Offset(0, -6))],
          ),
          child: CustomScrollView(
            controller: scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: MapPalette.of(context).handle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _SearchField(
                        onTap: () => controller.animateTo(
                          full,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              events.when(
                loading: () => const SliverToBoxAdapter(child: _LoadingRows()),
                error: (e, _) => SliverToBoxAdapter(
                  child: _Message(
                    icon: AppIcons.wifiSlash,
                    title: 'Couldn\'t load meets',
                    subtitle: 'Check your connection and pull to refresh.',
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(mapEventsProvider),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return SliverToBoxAdapter(
                      child: hasSearch
                          ? const _Message(
                              icon: AppIcons.magnifyingGlass,
                              title: 'No matches',
                              subtitle: 'Try a different name or venue.',
                            )
                          : _Message(
                              art: AppArt.flag,
                              title: 'No meets nearby yet',
                              subtitle: 'Start one and your friends will come.',
                              actionLabel: 'Create meet',
                              onAction: () => context.push(Routes.createEvent),
                            ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.only(bottom: 24),
                    sliver: SliverList.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 88,
                        color: MapPalette.of(context).divider,
                      ),
                      itemBuilder: (context, i) {
                        final e = list[i];
                        return EventRow(
                          event: e,
                          distanceKm: distanceKm(origin, e.latLng),
                          onTap: () => context.push(Routes.event(e.id)),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField({required this.onTap});
  final VoidCallback onTap;

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: _ctrl,
        onTap: widget.onTap,
        onChanged: (v) => ref.read(mapSearchProvider.notifier).set(v),
        textInputAction: TextInputAction.search,
        style: TextStyle(color: MapPalette.of(context).text, fontSize: 15),
        cursorColor: MapPalette.of(context).text,
        decoration: InputDecoration(
          hintText: 'Search meets or venues',
          hintStyle: TextStyle(color: MapPalette.of(context).text2, fontSize: 15),
          prefixIcon: Icon(AppIcons.magnifyingGlass, color: MapPalette.of(context).text2, size: 22),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(AppIcons.x, color: MapPalette.of(context).text2, size: 20),
                  onPressed: () {
                    _ctrl.clear();
                    ref.read(mapSearchProvider.notifier).set('');
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: MapPalette.of(context).tile,
          contentPadding: EdgeInsets.zero,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

/// One event in the list. Dark variant (lives on the map sheet).
class EventRow extends StatelessWidget {
  const EventRow({super.key, required this.event, required this.distanceKm, required this.onTap, this.live = false});
  final Event event;
  final double distanceKm;
  final VoidCallback onTap;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final e = event;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Cover(url: e.coverUrl, type: e.type),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: MapPalette.of(context).text, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    live
                        ? '🔴 LIVE · ${e.checkinCount} here · started ${timeAgo(e.startsAt)}'
                        : '${e.type.label} · ${formatEventDateFriendly(e.startsAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: live ? const Color(0xFFFF6B6B) : MapPalette.of(context).text2, fontSize: 13, fontWeight: live ? FontWeight.w600 : FontWeight.w400),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${e.venueName} · ${formatDistance(distanceKm)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: MapPalette.of(context).text2, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.users, size: 18, color: MapPalette.of(context).text2),
                const SizedBox(height: 2),
                Text(
                  '${e.attendeeCount}',
                  style: TextStyle(color: MapPalette.of(context).text, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.type});
  final String? url;
  final EventType type;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 58,
        height: 58,
        child: url == null
            ? ColoredBox(
                color: MapPalette.of(context).tile,
                child: Center(child: ArtIcon(type.art, size: 34)),
              )
            : Image(image: CachedNetworkImageProvider(url!),
                fit: BoxFit.cover,
                frameBuilder: (_, child, frame, sync) => frame == null && !sync
                    ? ColoredBox(color: MapPalette.of(context).tile, child: Center(child: ArtIcon(type.art, size: 34)))
                    : child,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: MapPalette.of(context).tile,
                  child: Center(child: ArtIcon(type.art, size: 34)),
                ),
              ),
      ),
    );
  }
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: MapPalette.of(context).tile,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Column(
      children: List.generate(
        4,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              bar(58, 58),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [bar(180, 14), const SizedBox(height: 8), bar(140, 12), const SizedBox(height: 6), bar(100, 12)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    this.subtitle,
    this.icon,
    this.art,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? art;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 36, 32, 24),
      child: Column(
        children: [
          if (art != null)
            ArtIcon(art!, size: 56)
          else
            Icon(icon, size: 40, color: MapPalette.of(context).text2),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: MapPalette.of(context).text, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: MapPalette.of(context).text2, fontSize: 14, height: 1.4),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
