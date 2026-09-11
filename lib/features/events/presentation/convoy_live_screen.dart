import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../application/event_providers.dart';

/// Convoy live mode: everyone who joined shares their position for the
/// duration, via Supabase Realtime presence (nothing is stored).
class ConvoyLiveScreen extends ConsumerStatefulWidget {
  const ConvoyLiveScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<ConvoyLiveScreen> createState() => _ConvoyLiveScreenState();
}

class _Member {
  const _Member({required this.userId, required this.username, this.avatarUrl, required this.position, required this.updatedAt});
  final String userId;
  final String username;
  final String? avatarUrl;
  final LatLng position;
  final DateTime updatedAt;
}

class _ConvoyLiveScreenState extends ConsumerState<ConvoyLiveScreen> {
  RealtimeChannel? _channel;
  StreamSubscription<Position>? _positions;
  GoogleMapController? _map;
  String? _style;
  Map<String, _Member> _members = {};
  LatLng? _me;
  bool _sharing = false;
  String? _error;
  bool _followMe = true;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/map_style_dark.json').then((s) {
      if (mounted) setState(() => _style = s);
    });
    _start();
  }

  @override
  void dispose() {
    _positions?.cancel();
    _channel?.untrack();
    _channel?.unsubscribe();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final me = ref.read(currentUserIdProvider);
    final profile = ref.read(currentProfileProvider).value;
    if (me == null) return;

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _error = 'Location permission is needed to join the convoy.');
        return;
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
      return;
    }

    final client = ref.read(supabaseProvider);
    final channel = client.channel('convoy:${widget.eventId}');
    _channel = channel;

    channel.onPresenceSync((_) => _syncMembers()).subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _positions = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 8),
        ).listen((pos) {
          final here = LatLng(pos.latitude, pos.longitude);
          setState(() {
            _me = here;
            _sharing = true;
          });
          channel.track({
            'user_id': me,
            'username': profile?.username ?? 'me',
            'avatar_url': profile?.avatarUrl,
            'lat': pos.latitude,
            'lng': pos.longitude,
            'heading': pos.heading,
            'at': DateTime.now().toUtc().toIso8601String(),
          });
          if (_followMe) _map?.animateCamera(CameraUpdate.newLatLng(here));
        }, onError: (e) => setState(() => _error = friendlyError(e)));
      } else if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
        setState(() => _error = 'Couldn\'t connect to the convoy channel. Check your connection.');
      }
    });
  }

  void _syncMembers() {
    final channel = _channel;
    if (channel == null) return;
    final next = <String, _Member>{};
    for (final state in channel.presenceState()) {
      for (final p in state.presences) {
        final payload = p.payload;
        final id = payload['user_id'] as String?;
        final lat = (payload['lat'] as num?)?.toDouble();
        final lng = (payload['lng'] as num?)?.toDouble();
        if (id == null || lat == null || lng == null) continue;
        next[id] = _Member(
          userId: id,
          username: payload['username'] as String? ?? 'driver',
          avatarUrl: payload['avatar_url'] as String?,
          position: LatLng(lat, lng),
          updatedAt: DateTime.tryParse(payload['at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        );
      }
    }
    if (mounted) setState(() => _members = next);
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(eventDetailProvider(widget.eventId)).value;
    final me = ref.watch(currentUserIdProvider);
    final others = _members.values.where((m) => m.userId != me).toList();
    final markers = {
      for (final m in _members.values)
        Marker(
          markerId: MarkerId(m.userId),
          position: m.position,
          infoWindow: InfoWindow(title: m.userId == me ? 'You' : m.username),
          icon: m.userId == me ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure) : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ),
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.mapBg,
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: detail?.event.latLng ?? const LatLng(3.139, 101.6869), zoom: 12),
              style: _style,
              markers: markers,
              onMapCreated: (c) => _map = c,
              onCameraMoveStarted: () => _followMe = false,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              padding: const EdgeInsets.only(bottom: 180),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(
                  children: [
                    _Round(icon: AppIcons.arrowLeft, onTap: () => context.pop()),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(color: const Color(0xF2151820), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
                        child: Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _sharing ? AppColors.success : AppColors.warnColor)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                detail == null ? 'Convoy' : '${detail.event.title} · live',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Round(
                      icon: AppIcons.gpsFix,
                      onTap: () {
                        _followMe = true;
                        if (_me != null) _map?.animateCamera(CameraUpdate.newLatLngZoom(_me!, 14));
                      },
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(color: AppColors.mapSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _error ?? (_sharing ? 'Sharing your position with the convoy' : 'Connecting…'),
                        style: TextStyle(color: _error == null ? AppColors.mapText : AppColors.danger, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_members.length} in the convoy · positions are only shared while this screen is open',
                        style: const TextStyle(color: AppColors.mapTextSecondary, fontSize: 12.5),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 64,
                        child: others.isEmpty
                            ? const Align(alignment: Alignment.centerLeft, child: Text('Waiting for the rest of the pack…', style: TextStyle(color: AppColors.mapTextSecondary, fontSize: 13)))
                            : ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  for (final m in others)
                                    GestureDetector(
                                      onTap: () {
                                        _followMe = false;
                                        _map?.animateCamera(CameraUpdate.newLatLngZoom(m.position, 14));
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 12),
                                        child: Column(
                                          children: [
                                            UserAvatar(url: m.avatarUrl, name: m.username, size: 40, borderColor: AppColors.accent),
                                            const SizedBox(height: 4),
                                            SizedBox(width: 56, child: Text(m.username, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mapText, fontSize: 11))),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => context.pop(),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                          child: const Text('Leave live mode'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF2151820),
      shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white, size: 22)),
      ),
    );
  }
}
