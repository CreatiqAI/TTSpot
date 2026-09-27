import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../geo/latlng.dart';
import '../map/app_map.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// Map with a fixed centre pin. Pan the map; [onChanged] reports where the pin
/// ends up whenever the camera stops. Reports [start] once on first frame.
class PinMap extends StatefulWidget {
  const PinMap({
    super.key,
    required this.start,
    required this.onChanged,
    this.height = 220,
    this.zoom = 13.5,
    this.hint = 'Drag the map to the spot',
    this.onMyLocation,
  });

  final LatLng start;
  final ValueChanged<LatLng> onChanged;
  final double height;
  final double zoom;
  final String hint;
  final VoidCallback? onMyLocation;

  @override
  State<PinMap> createState() => PinMapState();
}

class PinMapState extends State<PinMap> {
  final _map = AppMapController();
  LatLng? _target;

  @override
  void initState() {
    super.initState();
    _target = widget.start;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(widget.start);
    });
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void moveTo(LatLng target, {double? zoom}) => _map.animateTo(target, zoom: zoom);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            AppMap(
              controller: _map,
              initialTarget: widget.start,
              initialZoom: widget.zoom,
              night: AppColors.dark,
              onCameraMove: (c) => _target = c,
              onCameraIdle: () {
                if (_target != null) widget.onChanged(_target!);
              },
              gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)},
            ),
            const IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 34),
                  child: Icon(AppIcons.mapPinFill, size: 40, color: AppColors.accent),
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(8)),
                child: Text(widget.hint, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
            if (widget.onMyLocation != null)
              Positioned(
                right: 10,
                bottom: 10,
                child: Material(
                  color: AppColors.surface,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: InkWell(
                    onTap: widget.onMyLocation,
                    customBorder: const CircleBorder(),
                    child: SizedBox(width: 40, height: 40, child: Icon(AppIcons.gpsFix, size: 20, color: AppColors.textPrimary)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
