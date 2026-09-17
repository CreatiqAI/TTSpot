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

/// The one slim glass row above the tab bar when the map sheet is closed.
/// Now: the TT button and chips for who is on the map and today's moments.
/// Upcoming / Spots: a search pill and a count chip. Tapping a chip or the
/// search pill opens the sheet; the sheet itself holds the lists.
class MapToolbar extends ConsumerWidget {
  const MapToolbar({super.key, required this.mode, required this.light, required this.onOpen});
  final MapMode mode;
  final bool light;
  /// Open the sheet (true = all the way).
  final void Function({bool full}) onOpen;

  static const double height = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = switch (mode) {
      MapMode.now => _now(context, ref),
      MapMode.upcoming => _upcoming(context, ref),
      MapMode.spots => _spots(context, ref),
    };
    return GlassPanel(
      dark: !light,
      radius: height / 2,
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: height - 8,
        child: Row(children: children),
      ),
    );
  }

  List<Widget> _now(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final live = ref.watch(liveEventsProvider).value ?? const <Event>[];
    final pins = ref.watch(friendPinsProvider).value ?? const <FriendPin>[];
    final moments = ref.watch(liveMomentsProvider).value ?? const <Story>[];
    final origin = ref.watch(mapOriginProvider);
    final friendIds = ref.watch(friendIdsProvider);
    final mine = live.where((e) => e.isInstant && e.organizerId == me).firstOrNull;
    final friendTt = live.where((e) => e.isInstant && friendIds.contains(e.organizerId)).toList()
      ..sort((a, b) => distanceKm(origin, a.latLng).compareTo(distanceKm(origin, b.latLng)));
    final friendsTt = friendTt.firstOrNull;
    final onMap = pins.where((p) => p.isFresh).length;

    final Widget tt;
    if (mine != null) {
      tt = _TtButton(
        style: _TtStyle.live,
        icon: AppIcons.record,
        label: 'Live · ${mine.checkinCount} here · ${_minsLeft(mine)} min',
        onTap: () => context.push(Routes.event(mine.id)),
      );
    } else if (friendsTt != null) {
      tt = _TtButton(
        style: _TtStyle.friend,
        icon: AppIcons.coffee,
        label: '${_firstName(friendsTt.organizerId, pins)}\'s TT · ${formatDistance(distanceKm(origin, friendsTt.latLng))}',
        onTap: () => context.push(Routes.event(friendsTt.id)),
      );
    } else {
      tt = _TtButton(style: _TtStyle.start, icon: AppIcons.coffee, label: 'TT now', onTap: () => showTtNowSheet(context));
    }

    return [
      Flexible(flex: 0, child: tt),
      const SizedBox(width: 4),
      Expanded(
        child: _Chip(
          light: light,
          leading: onMap == 0
              ? Icon(AppIcons.users, size: 15, color: _fg(light))
              : _AvatarStack(pins: pins.where((p) => p.isFresh).take(3).toList(), light: light),
          label: onMap == 0 ? 'Nobody yet' : '$onMap on the map',
          onTap: () => onOpen(full: false),
        ),
      ),
      if (moments.isNotEmpty) ...[
        const SizedBox(width: 4),
        _Chip(
          light: light,
          leading: _MomentThumb(url: moments.first.photoUrl),
          label: '${moments.length}',
          onTap: () => onOpen(full: false),
        ),
      ],
    ];
  }

  List<Widget> _upcoming(BuildContext context, WidgetRef ref) {
    final count = ref.watch(visibleMapEventsProvider).value?.length ?? 0;
    final filters = ref.watch(mapFiltersProvider);
    return [
      Expanded(child: _SearchPill(light: light, hint: 'Search meets or venues', onTap: () => onOpen(full: true))),
      const SizedBox(width: 4),
      _Chip(
        light: light,
        leading: Icon(AppIcons.flagCheckered, size: 15, color: _fg(light)),
        label: count == 0 ? 'No meets' : '$count meet${count == 1 ? '' : 's'}${filters.isDefault ? '' : ' · ${filters.label}'}',
        onTap: () => onOpen(full: false),
      ),
    ];
  }

  List<Widget> _spots(BuildContext context, WidgetRef ref) {
    final count = ref.watch(visibleSpotsProvider).value?.length ?? 0;
    return [
      Expanded(child: _SearchPill(light: light, hint: 'Search a spot or address', onTap: () => onOpen(full: true))),
      const SizedBox(width: 4),
      _Chip(
        light: light,
        leading: Icon(AppIcons.mapPin, size: 15, color: _fg(light)),
        label: count == 0 ? 'No spots' : '$count spot${count == 1 ? '' : 's'}',
        onTap: () => onOpen(full: false),
      ),
    ];
  }
}

Color _fg(bool light) => light ? AppColors.ink : Colors.white;

int _minsLeft(Event e) => e.closesAt.difference(DateTime.now()).inMinutes.clamp(0, 9999);

String _firstName(String userId, List<FriendPin> pins) {
  final p = pins.where((x) => x.user.id == userId).firstOrNull?.user;
  final n = p?.displayName ?? p?.username ?? 'Friend';
  return n.split(' ').first;
}

enum _TtStyle { start, live, friend }

class _TtButton extends StatelessWidget {
  const _TtButton({required this.style, required this.icon, required this.label, required this.onTap});
  final _TtStyle style;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = switch (style) { _TtStyle.start => AppColors.brand, _TtStyle.live => Colors.black, _TtStyle.friend => Colors.white };
    final fg = style == _TtStyle.friend ? AppColors.ink : Colors.white;
    return PressScale(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(21),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(21),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: style == _TtStyle.live ? AppColors.brand : fg),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.light, required this.leading, required this.label, required this.onTap});
  final bool light;
  final Widget leading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        color: light ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(21),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(21),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading,
                const SizedBox(width: 7),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _fg(light), fontWeight: FontWeight.w700, fontSize: 13))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.light, required this.hint, required this.onTap});
  final bool light;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: light ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(21),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(AppIcons.magnifyingGlass, size: 17, color: _fg(light).withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Expanded(child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _fg(light).withValues(alpha: 0.7), fontSize: 13.5, fontWeight: FontWeight.w600))),
            ],
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
    const size = 22.0;
    const overlap = 7.0;
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

class _MomentThumb extends StatelessWidget {
  const _MomentThumb({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: -0.12,
        child: Container(
          width: 18,
          height: 22,
          padding: const EdgeInsets.fromLTRB(1.5, 1.5, 1.5, 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 2)]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF9AA0A6))),
          ),
        ),
      );
}
