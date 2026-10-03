import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../friends/application/friends_providers.dart';
import '../../../friends/domain/friend.dart';
import '../../../social/domain/post.dart';
import '../../application/map_providers.dart';

/// Quick filters under the Now · Events · Spots switch: one row of chips
/// that scrolls sideways, Google Maps style. The chips act on the map and
/// on the list in the sheet at once.
///
///   Now:    All · Friends · Clubmates · Nearby · Events · Moments · Spots
///           (Now is the whole map; Events and Spots are filters of it)
///   Events: All · Official · Partners · Clubs · TT sessions | Track day ·
///           Convoy · Meet | Today · This week · Later
///   Spots:  All · Car cafés · Mamak · Workshops · Detailing · Partners · Saved
///
/// Inside a group the picked chips add up; across groups they narrow. A
/// group with nothing picked shows everything ("All" lights up where there
/// is one). The numbers say how many each chip would show in view.
class MapChipBar extends ConsumerWidget {
  const MapChipBar({super.key, required this.mode, required this.light});
  final MapMode mode;

  /// White chips on the day map, dark ones at night.
  final bool light;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chips = switch (mode) {
      MapMode.now => _now(ref),
      MapMode.events => _events(ref),
      MapMode.spots => _spots(ref),
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6), // room for the chips' shadow
      child: Row(children: chips),
    );
  }

  List<Widget> _now(WidgetRef ref) {
    final picked = ref.watch(nowChipsProvider);
    final notifier = ref.read(nowChipsProvider.notifier);
    final pins = ref.watch(friendPinsProvider).value ?? const <FriendPin>[];
    final events = ref.watch(nowMapEventsProvider);
    final moments = ref.watch(liveMomentsProvider).value ?? const <Story>[];
    final places = ref.watch(mapAllPlacesProvider);
    int? n(NowChip c) => switch (c) {
          NowChip.friends => pins.where((p) => !p.isStranger && !p.viaClub).length,
          NowChip.club => pins.where((p) => !p.isStranger && p.viaClub).length,
          NowChip.nearby => pins.where((p) => p.isStranger).length,
          NowChip.events => events.length,
          NowChip.moments => moments.length,
          NowChip.spots => places.length,
        };
    IconData icon(NowChip c) => switch (c) {
          NowChip.friends => AppIcons.users,
          NowChip.club => AppIcons.usersThree,
          NowChip.nearby => AppIcons.broadcast,
          NowChip.events => AppIcons.flag,
          NowChip.moments => AppIcons.image,
          NowChip.spots => AppIcons.mapPin,
        };
    return [
      _MapChip(label: 'All', selected: picked.isEmpty, light: light, onTap: notifier.all),
      for (final c in NowChip.values)
        _MapChip(label: c.label, icon: icon(c), count: n(c), selected: picked.contains(c), light: light, onTap: () => notifier.toggle(c)),
    ];
  }

  List<Widget> _events(WidgetRef ref) {
    final f = ref.watch(eventFilterProvider);
    final notifier = ref.read(eventFilterProvider.notifier);
    final counts = ref.watch(eventChipCountsProvider);
    IconData hostIcon(HostChip c) => switch (c) {
          HostChip.official => AppIcons.sealCheck,
          HostChip.partners => AppIcons.storefront,
          HostChip.clubs => AppIcons.usersThree,
          HostChip.tt => AppIcons.flagPennantFill,
        };
    IconData typeIcon(TypeChip c) => switch (c) {
          TypeChip.trackday => AppIcons.flagCheckered,
          TypeChip.convoy => AppIcons.roadHorizon,
          TypeChip.meet => AppIcons.flag,
        };
    return [
      _MapChip(label: 'All', count: counts?.allHosts, selected: f.hosts.isEmpty, light: light, onTap: notifier.allHosts),
      for (final c in HostChip.values)
        _MapChip(label: c.label, icon: hostIcon(c), count: counts?.host[c], selected: f.hosts.contains(c), light: light, onTap: () => notifier.toggleHost(c)),
      _Divider(light: light),
      for (final c in TypeChip.values)
        _MapChip(label: c.label, icon: typeIcon(c), count: counts?.type[c], selected: f.types.contains(c), light: light, onTap: () => notifier.toggleType(c)),
      _Divider(light: light),
      for (final c in WhenChip.values)
        _MapChip(label: c.label, count: counts?.time[c], selected: f.when.contains(c), light: light, onTap: () => notifier.toggleWhen(c)),
    ];
  }

  List<Widget> _spots(WidgetRef ref) {
    final picked = ref.watch(spotChipsProvider);
    final notifier = ref.read(spotChipsProvider.notifier);
    final (all, counts) = ref.watch(spotChipCountsProvider);
    IconData icon(SpotChip c) => switch (c) {
          SpotChip.cafe => AppIcons.coffee,
          SpotChip.mamak => AppIcons.forkKnife,
          SpotChip.workshop => AppIcons.wrench,
          SpotChip.detailing => AppIcons.sparkle,
          SpotChip.partners => AppIcons.storefront,
          SpotChip.saved => AppIcons.bookmarkSimple,
        };
    return [
      _MapChip(label: 'All', count: all, selected: picked.isEmpty, light: light, onTap: notifier.all),
      for (final c in SpotChip.values)
        _MapChip(label: c.label, icon: icon(c), count: counts[c], selected: picked.contains(c), light: light, onTap: () => notifier.toggle(c)),
    ];
  }
}

/// One chip: optional icon, label and a quiet count. Ink when picked by day,
/// white when picked at night.
class _MapChip extends StatelessWidget {
  const _MapChip({required this.label, required this.selected, required this.light, required this.onTap, this.icon, this.count});
  final String label;
  final IconData? icon;
  final int? count;
  final bool selected;
  final bool light;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? (light ? AppColors.ink : Colors.white) : (light ? Colors.white : AppColors.mapSurface);
    final fg = selected ? (light ? Colors.white : Colors.black) : (light ? AppColors.ink : Colors.white);
    final n = count;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: bg,
          shape: StadiumBorder(side: BorderSide(color: light ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.10))),
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: light ? 0.35 : 0.6),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: EdgeInsets.fromLTRB(icon == null ? 12 : 10, 7, 12, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
                  Text(label, maxLines: 1, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700, height: 1.15)),
                  if (n != null && n > 0) ...[
                    const SizedBox(width: 5),
                    Text('$n', maxLines: 1, style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 12, fontWeight: FontWeight.w700, height: 1.15)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A hairline between the Events tab's chip groups (host | type | time).
class _Divider extends StatelessWidget {
  const _Divider({required this.light});
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 8),
      child: Container(
        width: 1.5,
        height: 20,
        decoration: BoxDecoration(
          color: (light ? AppColors.ink : Colors.white).withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
