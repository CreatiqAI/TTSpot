import '../../../core/env.dart';
import 'event.dart';

/// A bundled meet cover a host can pick instead of uploading a photo.
///
/// Each one is in the app (`assets/covers/<id>.jpg`) and also in storage at
/// `event-covers/presets/<id>.jpg` (migration 0090), so a picked preset is
/// saved as a normal public URL in `events.cover_url`. Everything that shows
/// covers reads it like an upload; the app swaps in the bundled file
/// ([presetCoverAsset]) so it loads instantly.
class CoverPreset {
  const CoverPreset(this.id, this.label);
  final String id;
  final String label;

  String get asset => 'assets/covers/$id.jpg';
  String get url => '${Env.supabaseUrl}/storage/v1/object/public/event-covers/presets/$id.jpg';
}

const kCoverPresets = <CoverPreset>[
  CoverPreset('tt', 'Mamak night'),
  CoverPreset('club', 'Hilltop sunset'),
  CoverPreset('meet', 'City lights'),
  CoverPreset('convoy', 'Mountain road'),
  CoverPreset('trackday', 'Track'),
  CoverPreset('charity', 'Car show'),
];

/// The covers offered for [type], the type's own one first (it is what the
/// meet shows when nothing is picked).
List<CoverPreset> coverPresetsFor(EventType type) {
  final own = kCoverPresets.where((p) => p.id == type.db);
  return [...own, ...kCoverPresets.where((p) => p.id != type.db)];
}

final _presetPath = RegExp(r'/event-covers/presets/([a-z]+)(?:_t)?\.jpg$');

/// The bundled file behind a preset cover URL, or null for an uploaded photo.
String? presetCoverAsset(String? url) {
  if (url == null) return null;
  final m = _presetPath.firstMatch(url);
  if (m == null) return null;
  final id = m.group(1);
  return kCoverPresets.any((p) => p.id == id) || id == 'official' ? 'assets/covers/$id.jpg' : null;
}
