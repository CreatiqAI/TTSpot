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
import 'tt_now_sheet.dart';

/// The one glass row above the tab bar when the map sheet is closed. Same
/// shape on every layer: a red action on the left, a line of status in the
/// middle, a round "open" button on the right. Tapping the middle or the
/// button opens the sheet, which holds the lists.
class MapToolbar extends ConsumerWidget {
  const MapToolbar({super.key, required this.mode, required this.light, required this.onOpen});
  final MapMode mode;
  final bool light;
  /// Open the sheet (true = all the way).
  final void Function({bool full}) onOpen;

  static const double height = 58;
  static const double _inner = 46;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (action, status) = switch (mode) {
      MapMode.now => _now(context, ref),
      MapMode.upcoming => _upcoming(context, ref),
      MapMode.spots => _spots(context, ref),
    };
    return GlassPanel(
      dark: !light,
      radius: height / 2,
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        height: _inner,
        child: Row(
          children: [
            action,
            const SizedBox(width: 6),
            Expanded(child: status),
          ],
        ),
      ),
    );
  }

  (Widget, Widget) _now(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final live = ref.watch(liveEventsProvider).value ?? const <Event>[];
    final pins = ref.watch(friendPinsProvider).value ?? const <FriendPin>[];
    final moments = ref.watch(liveMomentsProvider).value ?? const <Story>[];
    final origin = ref.watch(mapOriginProvider);
    final friendIds = ref.watch(friendIdsProvider);
    final mine = live.where((e) => e.isInstant && e.organizerId == me).firstOrNull;
    final friendTt = (live.where((e) => e.isInstant && friendIds.contains(e.organizerId)).toList()
          ..sort((a, b) => distanceKm(origin, a.latLng).compareTo(distanceKm(origin, b.latLng))))
        .firstOrNull;
    final fresh = pins.where((p) => p.isFresh).toList();

    final Widget action;
    if (mine != null) {
      action = _Action(style: _Style.live, icon: AppIcons.record, label: '${mine.checkinCount} here · ${_minsLeft(mine)} min', onTap: () => context.push(Routes.event(mine.id)));
    } else if (friendTt != null) {
      action = _Action(style: _Style.friend, icon: AppIcons.coffee, label: '${_firstName(friendTt.organizerId, pins)}\'s TT', onTap: () => context.push(Routes.event(friendTt.id)));
    } else {
      action = _Action(style: _Style.start, icon: AppIcons.coffee, label: 'TT now', onTap: () => showTtNowSheet(context));
    }

    final status = _Status(
      light: light,
      leading: fresh.isEmpty ? Icon(AppIcons.usersThree, size: 18, color: _muted(light)) : _AvatarStack(pins: fresh.take(3).toList(), light: light),
      text: fresh.isEmpty ? 'Nobody on the map' : '${fresh.length} on the map',
      badge: moments.length,
      onTap: () => onOpen(full: false),
    );
    return (action, status);
  }

  (Widget, Widget) _upcoming(BuildContext context, WidgetRef ref) {
    final count = ref.watch(visibleMapEventsProvider).value?.length ?? 0;
    final filters = ref.watch(mapFiltersProvider);
    final action = _Action(style: _Style.start, icon: AppIcons.plus, label: 'Plan', onTap: () => context.push(Routes.createEvent));
    final status = _Status(
      light: light,
      leading: Icon(AppIcons.magnifyingGlass, size: 18, color: _muted(light)),
      text: count == 0 ? 'No meets here yet' : '$count meet${count == 1 ? '' : 's'}${filters.isDefault ? '' : ' · ${filters.label}'}',
      muted: count == 0,
      onTap: () => onOpen(full: true),
    );
    return (action, status);
  }

  (Widget, Widget) _spots(BuildContext context, WidgetRef ref) {
    final count = ref.watch(visibleSpotsProvider).value?.length ?? 0;
    final action = _Action(style: _Style.start, icon: AppIcons.mapPinPlus, label: 'Suggest', onTap: () => context.push(Routes.suggestSpot));
    final status = _Status(
      light: light,
      leading: Icon(AppIcons.magnifyingGlass, size: 18, color: _muted(light)),
      text: count == 0 ? 'No spots here yet' : '$count spot${count == 1 ? '' : 's'} to check in',
      muted: count == 0,
      onTap: () => onOpen(full: true),
    );
    return (action, status);
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

/// The left button: red to start, black while my TT is live, white for a friend's.
class _Action extends StatelessWidget {
  const _Action({required this.style, required this.icon, required this.label, required this.onTap});
  final _Style style;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = switch (style) { _Style.start => AppColors.brand, _Style.live => Colors.black, _Style.friend => Colors.white };
    final fg = style == _Style.friend ? AppColors.ink : Colors.white;
    return PressScale(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(MapToolbar._inner / 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MapToolbar._inner / 2),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 16, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: style == _Style.live ? AppColors.brand : fg),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Middle text plus the round open button. One tap target.
class _Status extends StatelessWidget {
  const _Status({required this.light, required this.leading, required this.text, required this.onTap, this.badge = 0, this.muted = false});
  final bool light;
  final Widget leading;
  final String text;
  final VoidCallback onTap;
  /// Moments today, shown as a small count on the open button.
  final int badge;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final fg = _fg(light);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(MapToolbar._inner / 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MapToolbar._inner / 2),
        child: Row(
          children: [
            const SizedBox(width: 10),
            leading,
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted ? _muted(light) : fg, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
            const SizedBox(width: 6),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: MapToolbar._inner - 6,
                  height: MapToolbar._inner - 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: light ? Colors.black.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.14)),
                  child: Icon(AppIcons.caretUp, size: 16, color: fg),
                ),
                if (badge > 0)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(9), border: Border.all(color: light ? Colors.white : AppColors.mapSurface, width: 1.5)),
                      child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, height: 1)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 3),
          ],
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
