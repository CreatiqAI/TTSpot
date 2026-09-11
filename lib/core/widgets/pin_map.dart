import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
  GoogleMapController? _map;
  String? _style;
  LatLng? _target;

  @override
  void initState() {
    super.initState();
    _target = widget.start;
    rootBundle.loadString('assets/map_style_dark.json').then((s) {
      if (mounted) setState(() => _style = s);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(widget.start);
    });
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  void moveTo(LatLng target, {double? zoom}) {
    _map?.animateCamera(zoom == null ? CameraUpdate.newLatLng(target) : CameraUpdate.newLatLngZoom(target, zoom));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: widget.start, zoom: widget.zoom),
              style: _style,
              onMapCreated: (c) => _map = c,
              onCameraMove: (pos) => _target = pos.target,
              onCameraIdle: () {
                if (_target != null) widget.onChanged(_target!);
              },
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
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
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: InkWell(
                    onTap: widget.onMyLocation,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(width: 40, height: 40, child: Icon(AppIcons.gpsFix, size: 20, color: AppColors.textPrimary)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
