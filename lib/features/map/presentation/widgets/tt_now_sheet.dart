import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../events/application/event_providers.dart';
import '../../../friends/application/friends_providers.dart';
import '../../application/map_providers.dart';

/// "TT now": two taps from wherever you are to a live meet your friends get pinged about.
Future<void> showTtNowSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _TtNowSheet(),
  );
}

class _TtNowSheet extends ConsumerStatefulWidget {
  const _TtNowSheet();

  @override
  ConsumerState<_TtNowSheet> createState() => _TtNowSheetState();
}

class _TtNowSheetState extends ConsumerState<_TtNowSheet> {
  final _venue = TextEditingController();
  int _hours = 3;
  bool _busy = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _venue.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
        );
      } catch (_) {
        pos = null;
      }
      final fallback = ref.read(userLocationProvider).value;
      final lat = pos?.latitude ?? fallback?.latitude;
      final lng = pos?.longitude ?? fallback?.longitude;
      if (lat == null || lng == null) throw const AppException('Turn on location so friends know where to come.');

      final id = await ref.read(eventActionsProvider).ttNow(lat: lat, lng: lng, venue: _venue.text, hours: _hours);
      ref.invalidate(liveEventsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      context.push(Routes.event(id));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final my = ref.watch(myLocationProvider).value;
    final friends = ref.watch(friendsProvider).value?.length ?? 0;
    if (!_prefilled && my?.placeName != null) {
      _venue.text = my!.placeName!;
      _prefilled = true;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              ArtIcon(AppArt.coffee, size: 30),
              SizedBox(width: 8),
              Text('TT now', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            friends == 0
                ? 'Starts a meet right here, right now. Add friends so they get pinged.'
                : 'Starts a meet right here, right now. Your $friends friend${friends == 1 ? '' : 's'} get pinged.',
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _venue,
            textCapitalization: TextCapitalization.words,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Where are you?', hintText: 'e.g. Mamak Sri Melur, TTDI', counterText: '', prefixIcon: Icon(AppIcons.mapPin)),
          ),
          const SizedBox(height: 14),
          const Text('HOW LONG', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final h in const [2, 3, 4])
                ChoiceChip(label: Text('$h hours'), selected: _hours == h, onSelected: (_) => setState(() => _hours = h)),
            ],
          ),
          const SizedBox(height: 22),
          PrimaryButton(label: 'Ping friends', loading: _busy, onPressed: _busy ? null : _go),
          const SizedBox(height: 8),
          const Text(
            'Your spot shows on the map for friends only. You can end it any time.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
