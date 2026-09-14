import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/places/places_service.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/place_search_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../events/application/event_providers.dart';
import '../../../friends/application/friends_providers.dart';
import '../../application/map_providers.dart';

/// "TT now": one field, one button. Type or pick where you are; friends get
/// pinged. The meet ends by itself after three hours, or whenever you end it.
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
  PlaceDetails? _picked;
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
      double? lat = _picked?.lat;
      double? lng = _picked?.lng;
      if (lat == null || lng == null) {
        Position? pos;
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
          );
        } catch (_) {
          pos = null;
        }
        final fallback = ref.read(userLocationProvider).value;
        lat = pos?.latitude ?? fallback?.latitude;
        lng = pos?.longitude ?? fallback?.longitude;
      }
      if (lat == null || lng == null) throw const AppException('Turn on location so friends know where to come.');

      final id = await ref.read(eventActionsProvider).ttNow(lat: lat, lng: lng, venue: _venue.text);
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
    final here = ref.watch(userLocationProvider).value;
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
                ? 'Tell friends where you are. Add friends first so someone gets pinged.'
                : 'Tell your $friends friend${friends == 1 ? '' : 's'} where you are. They get pinged right away.',
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 18),
          PlaceSearchField(
            controller: _venue,
            enabled: !_busy,
            near: here == null ? null : (here.latitude, here.longitude),
            hint: 'Where are you?',
            icon: AppIcons.mapPin,
            onChanged: (_) {
              if (_picked != null) setState(() => _picked = null);
            },
            onPicked: (d) => setState(() {
              _picked = d;
              _venue.text = d.name;
            }),
          ),
          const SizedBox(height: 18),
          PrimaryButton(label: 'Start TT now', loading: _busy, onPressed: _busy ? null : _go),
          const SizedBox(height: 8),
          const Text(
            'Only friends see it on the map. It ends by itself in 3 hours, or when you end it.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
