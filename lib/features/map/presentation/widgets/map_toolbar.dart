import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/geo.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../events/domain/event.dart';
import '../../../friends/application/friends_providers.dart';
import '../../../friends/domain/friend.dart';
import '../../../social/domain/post.dart';
import '../../application/map_providers.dart';
import 'map_filter_sheet.dart';
import 'tt_now_sheet.dart';

/// Solid panel above the tab bar while the map sheet is closed: the red TT
/// button (car over "TT now"), a search-style status pill that opens the
/// lists, and a round filter button. Dark panel on the night map, white by day.
class MapToolbar extends ConsumerWidget {
  const MapToolbar({super.key, required this.mode, required this.light, required this.onOpen});
  final MapMode mode;
  final bool light;
  /// Open the sheet (true = all the way).
  final void Function({bool full}) onOpen;

  static const double height = 78;
  static const double _pad = 10;
  static const double _button = 58;
  static const double _pill = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surface = light ? Colors.white : AppColors.mapSurface;
    final edge = light ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.08);
    return Container(
      height: height,
      padding: const EdgeInsets.all(_pad),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: edge),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: light ? 0.12 : 0.45), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          _ttButton(context, ref),
          const SizedBox(width: 10),
          Expanded(child: _statusPill(context, ref)),
          const SizedBox(width: 10),
          _filterButton(context, ref),
        ],
      ),
    );
  }

  /// Red to start a TT, black while mine is live, white when a friend's is on.
  Widget _ttButton(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final live = ref.watch(liveEventsProvider).value ?? const <Event>[];
    final pins = ref.watch(friendPinsProvider).value ?? const <FriendPin>[];
    final origin = ref.watch(mapOriginProvider);
    final friendIds = ref.watch(friendIdsProvider);
    final mine = live.where((e) => e.isInstant && e.organizerId == me).firstOrNull;
    final friendTt = (live.where((e) => e.isInstant && friendIds.contains(e.organizerId)).toList()
          ..sort((a, b) => distanceKm(origin, a.latLng).compareTo(distanceKm(origin, b.latLng))))
        .firstOrNull;
    if (mine != null) {
      return _TtButton(style: _Style.live, label: '${_minsLeft(mine)} min', onTap: () => context.push(Routes.event(mine.id)));
    }
    if (friendTt != null) {
      final who = _firstName(friendTt.organizerId, pins);
      return _TtButton(style: _Style.friend, label: "$who's TT", onTap: () => context.push(Routes.event(friendTt.id)));
    }
    return _TtButton(style: _Style.start, label: 'TT now', onTap: () => showTtNowSheet(context));
  }

  Widget _statusPill(BuildContext context, WidgetRef ref) {
    switch (mode) {
      case MapMode.now:
        final pins = ref.watch(friendPinsProvider).value ?? const <FriendPin>[];
        final moments = ref.watch(liveMomentsProvider).value ?? const <Story>[];
        final fresh = pins.where((p) => p.isFresh).toList();
        final extra = moments.isEmpty ? '' : ' · ${moments.length} moment${moments.length == 1 ? '' : 's'}';
        return _Pill(
          light: light,
          leading: fresh.isEmpty ? Icon(AppIcons.usersThree, size: 20, color: _muted(light)) : _AvatarStack(pins: fresh.take(3).toList(), light: light),
          text: (fresh.isEmpty ? 'Nobody nearby' : '${fresh.length} nearby') + extra,
          onTap: () => onOpen(full: false),
        );
      case MapMode.upcoming:
        final count = ref.watch(visibleMapEventsProvider).value?.length ?? 0;
        return _Pill(
          light: light,
          leading: Icon(AppIcons.magnifyingGlass, size: 20, color: _muted(light)),
          text: count == 0 ? 'No meets here yet' : '$count meet${count == 1 ? '' : 's'}',
          onTap: () => onOpen(full: true),
        );
      case MapMode.spots:
        final count = ref.watch(visibleSpotsProvider).value?.length ?? 0;
        return _Pill(
          light: light,
          leading: Icon(AppIcons.magnifyingGlass, size: 20, color: _muted(light)),
          text: count == 0 ? 'No spots here yet' : '$count spot${count == 1 ? '' : 's'}',
          onTap: () => onOpen(full: true),
        );
    }
  }

  Widget _filterButton(BuildContext context, WidgetRef ref) {
    final active = !ref.watch(mapFiltersProvider).isDefault;
    final fg = _fg(light);
    return PressScale(
      child: Material(
        color: light ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.08),
        shape: CircleBorder(side: BorderSide(color: light ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.10))),
        child: InkWell(
          onTap: () => showMapFilterSheet(context),
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: _button,
            height: _button,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(AppIcons.slidersHorizontal, size: 22, color: fg),
                if (active)
                  Positioned(
                    right: 14,
                    top: 14,
                    child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _fg(bool light) => light ? AppColors.ink : Colors.white;
Color _muted(bool light) => _fg(light).withValues(alpha: 0.6);

int _minsLeft(Event e) => e.closesAt.difference(DateTime.now()).inMinutes.clamp(0, 9999);

String _firstName(String userId, List<FriendPin> pins) {
  final p = pins.where((x) => x.user.id == userId).firstOrNull?.user;
  final n = p?.displayName ?? p?.username ?? 'Friend';
  return n.split(' ').first;
}

enum _Style { start, live, friend }

/// Car over a short label. One colour on one colour: no gradients, no extras.
class _TtButton extends StatelessWidget {
  const _TtButton({required this.style, required this.label, required this.onTap});
  final _Style style;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = switch (style) { _Style.start => AppColors.brand, _Style.live => Colors.black, _Style.friend => Colors.white };
    final fg = style == _Style.friend ? AppColors.ink : Colors.white;
    return PressScale(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            width: 104,
            height: MapToolbar._button,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(AppIcons.car, size: 22, color: fg),
                const SizedBox(height: 2),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12, height: 1.1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Search-style pill: icon, one line, chevron. Opens the lists.
class _Pill extends StatelessWidget {
  const _Pill({required this.light, required this.leading, required this.text, required this.onTap});
  final bool light;
  final Widget leading;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = _fg(light);
    return Material(
      color: light ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.08),
      shape: StadiumBorder(side: BorderSide(color: light ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.10))),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          height: MapToolbar._pill,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 10),
                Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14.5))),
                const SizedBox(width: 6),
                Icon(AppIcons.caretRight, size: 16, color: _muted(light)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.pins, required this.light});
  final List<FriendPin> pins;
  final bool light;

  @override
  Widget build(BuildContext context) {
    const size = 24.0;
    const overlap = 8.0;
    return SizedBox(
      width: size + (pins.length - 1) * (size - overlap),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < pins.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: UserAvatar(
                url: pins[i].user.avatarUrl,
                name: pins[i].user.displayName ?? pins[i].user.username,
                size: size,
                borderColor: light ? Colors.white : AppColors.mapSurface,
              ),
            ),
        ],
      ),
    );
  }
}
