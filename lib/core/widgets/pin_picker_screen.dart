import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../geo/latlng.dart';
import '../map/app_map.dart';

import '../places/places_service.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'place_search_field.dart';

/// Full-screen "drop the pin" map. Drag the map under the fixed pin, search an
/// address, or jump to your location, then "Use this spot". Returns the
/// coordinates and, when a search result was picked, its name.
class PinPickResult {
  const PinPickResult(this.latLng, {this.name});
  final LatLng latLng;
  final String? name;
}

Future<PinPickResult?> pickPinFullScreen(BuildContext context, {required LatLng start}) {
  return Navigator.of(context).push<PinPickResult>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => PinPickerScreen(start: start)),
  );
}

class PinPickerScreen extends ConsumerStatefulWidget {
  const PinPickerScreen({super.key, required this.start});
  final LatLng start;

  @override
  ConsumerState<PinPickerScreen> createState() => _PinPickerScreenState();
}

class _PinPickerScreenState extends ConsumerState<PinPickerScreen> {
  final _map = AppMapController();
  late LatLng _target = widget.start;
  String? _name;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _myLocation() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
      );
      _map.animateTo(LatLng(p.latitude, p.longitude), zoom: 16);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location is off. Drag the map instead.')));
    }
  }

  void _onPicked(PlaceDetails d) {
    _name = d.name;
    _map.animateTo(LatLng(d.lat, d.lng), zoom: 17);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          AppMap(
            controller: _map,
            initialTarget: widget.start,
            initialZoom: 15,
            night: true,
            onCameraMove: (c) => _target = c,
            onCameraMoveStarted: () => _name = null, // a manual drag is no longer "that place"
            padding: EdgeInsets.only(top: pad.top + 72, bottom: 120),
          ),
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 44),
                child: Icon(AppIcons.mapPinFill, size: 48, color: AppColors.accent),
              ),
            ),
          ),
          // top: close + search
          Positioned(
            left: 12,
            right: 12,
            top: pad.top + 8,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Round(icon: AppIcons.x, onTap: () => Navigator.pop(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: PlaceSearchField(
                      near: (widget.start.latitude, widget.start.longitude),
                      hint: 'Search a place or address',
                      onPicked: _onPicked,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: pad.bottom + 96,
            child: _Round(icon: AppIcons.gpsFix, onTap: _myLocation),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: pad.bottom + 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Drag the map until the pin sits on the meet spot', style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, PinPickResult(_target, name: _name)),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: const Text('Use this spot'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(width: 48, height: 48, child: Icon(icon, size: 22, color: AppColors.textPrimary)),
        ),
      );
}
