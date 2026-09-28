import 'package:flutter/widgets.dart';

import '../../../core/theme/app_icons.dart';

/// What a pin on a floorplan marks. `db` matches the check constraint on
/// `event_floor_pins.kind`.
enum PinKind {
  zone('zone', 'Zone', AppIcons.mapPinArea, Color(0xFF2F6FED)),
  booth('booth', 'Booth', AppIcons.storefront, Color(0xFF8B3FD9)),
  stage('stage', 'Stage', AppIcons.microphoneStage, Color(0xFFE00008)),
  food('food', 'Food', AppIcons.forkKnife, Color(0xFFE8820C)),
  toilet('toilet', 'Toilet', AppIcons.toilet, Color(0xFF0E9AA7)),
  entrance('entrance', 'Entrance', AppIcons.doorOpen, Color(0xFF1DA750)),
  lift('lift', 'Lift', AppIcons.elevator, Color(0xFF5A6270)),
  ramp('ramp', 'Ramp', AppIcons.trendUp, Color(0xFF5A6270)),
  parking('parking', 'Parking', AppIcons.car, Color(0xFF1F4FB8)),
  info('info', 'Info', AppIcons.info, Color(0xFF101010)),
  luckyDraw('lucky_draw', 'Lucky draw', AppIcons.gift, Color(0xFFD4A20C));

  const PinKind(this.db, this.label, this.icon, this.color);
  final String db;
  final String label;
  final IconData icon;
  final Color color;

  static PinKind fromDb(String? v) => values.firstWhere((k) => k.db == v, orElse: () => PinKind.info);

  /// Kinds that get a printable QR ("scan to set your spot").
  bool get hasZoneQr => this == zone || this == entrance || this == parking;

  /// Big landmarks keep their label visible when zoomed out.
  bool get alwaysLabelled => this == zone || this == stage || this == entrance || this == luckyDraw || this == parking;
}

/// Payload printed on zone QR codes: `ttspot:zone:<pin_id>`.
String zoneQrPayload(String pinId) => 'ttspot:zone:$pinId';

/// Pulls the pin id out of a zone QR payload, or null.
String? parseZoneQr(String raw) {
  final t = raw.trim();
  const prefix = 'ttspot:zone:';
  if (!t.toLowerCase().startsWith(prefix)) return null;
  final id = t.substring(prefix.length).trim();
  return RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id) ? id : null;
}

/// Invite link printed on an event's invite QR.
String eventInviteUrl(String code) => 'https://ttspot.my/e/$code';

class FloorPin {
  const FloorPin({required this.id, required this.levelId, required this.kind, required this.label, required this.x, required this.y, this.partnerVendorId});
  final String id;
  final String levelId;
  final PinKind kind;
  final String label;
  final double x;
  final double y;
  final String? partnerVendorId;

  String get title => label.trim().isEmpty ? kind.label : label.trim();

  FloorPin copyWith({PinKind? kind, String? label, double? x, double? y, String? partnerVendorId, bool clearPartner = false}) => FloorPin(
        id: id,
        levelId: levelId,
        kind: kind ?? this.kind,
        label: label ?? this.label,
        x: x ?? this.x,
        y: y ?? this.y,
        partnerVendorId: clearPartner ? null : (partnerVendorId ?? this.partnerVendorId),
      );

  factory FloorPin.fromMap(Map<String, dynamic> m) => FloorPin(
        id: m['id'] as String,
        levelId: m['level_id'] as String,
        kind: PinKind.fromDb(m['kind'] as String?),
        label: m['label'] as String? ?? '',
        x: (m['x'] as num).toDouble(),
        y: (m['y'] as num).toDouble(),
        partnerVendorId: m['partner_vendor_id'] as String?,
      );
}

class FloorLevel {
  const FloorLevel({required this.id, required this.eventId, required this.name, required this.sort, this.imagePath, this.imageUrl, this.imageW, this.imageH, this.pins = const []});
  final String id;
  final String eventId;
  final String name;
  final int sort;
  final String? imagePath;
  final String? imageUrl;
  final int? imageW;
  final int? imageH;
  final List<FloorPin> pins;

  bool get hasImage => imageUrl != null && (imageW ?? 0) > 0 && (imageH ?? 0) > 0;
  double get aspect => hasImage ? imageW! / imageH! : 1;

  factory FloorLevel.fromMap(Map<String, dynamic> m, {String Function(String path)? publicUrl}) {
    final path = m['image_path'] as String?;
    final pins = ((m['event_floor_pins'] as List?) ?? const []).map((p) => FloorPin.fromMap((p as Map).cast<String, dynamic>())).toList()
      ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return FloorLevel(
      id: m['id'] as String,
      eventId: m['event_id'] as String,
      name: m['name'] as String,
      sort: (m['sort'] as num?)?.toInt() ?? 0,
      imagePath: path,
      imageUrl: path == null || publicUrl == null ? null : publicUrl(path),
      imageW: (m['image_w'] as num?)?.toInt(),
      imageH: (m['image_h'] as num?)?.toInt(),
      pins: pins,
    );
  }
}

/// My own spot at an event (only I can read it).
class MyPosition {
  const MyPosition({required this.eventId, required this.levelId, this.x, this.y, this.zonePinId, required this.updatedAt});
  final String eventId;
  final String levelId;
  final double? x;
  final double? y;
  final String? zonePinId;
  final DateTime updatedAt;

  bool get hasPoint => x != null && y != null;

  factory MyPosition.fromMap(Map<String, dynamic> m) => MyPosition(
        eventId: m['event_id'] as String,
        levelId: m['level_id'] as String,
        x: (m['x'] as num?)?.toDouble(),
        y: (m['y'] as num?)?.toDouble(),
        zonePinId: m['zone_pin_id'] as String?,
        updatedAt: DateTime.parse(m['updated_at'] as String).toLocal(),
      );
}
