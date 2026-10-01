import 'dart:math' as math;

/// How many bars a saved voice-note waveform has (messages.audio_wave).
const kVoiceWaveBars = 50;

/// Mic loudness in dBFS (about -160 for silence up to 0 for full scale) as
/// 0..1. Speech sits around -35..-5 dBFS, so -45 dBFS and below reads as quiet.
double dbfsToLevel(double dbfs) {
  if (dbfs.isNaN) return 0;
  return ((dbfs + 45) / 45).clamp(0.0, 1.0);
}

/// Squeezes (or stretches) a recording's loudness samples (0..1, one every
/// ~100 ms) into [bars] bars of 0..100, the loudest bar near 100. Each bar is
/// the peak of its slice, so short words still show. Quiet recordings are
/// lifted at most 4x, so background hiss doesn't turn into a wall.
List<int> downsampleWave(List<double> levels, {int bars = kVoiceWaveBars}) {
  if (levels.isEmpty || bars <= 0) return const [];
  final n = levels.length;
  final out = List<double>.filled(bars, 0);
  for (var i = 0; i < bars; i++) {
    if (n >= bars) {
      final from = i * n ~/ bars;
      final to = math.max(from + 1, (i + 1) * n ~/ bars);
      var peak = 0.0;
      for (var j = from; j < to; j++) {
        peak = math.max(peak, levels[j].clamp(0.0, 1.0));
      }
      out[i] = peak;
    } else {
      out[i] = levels[(i * n) ~/ bars].clamp(0.0, 1.0);
    }
  }
  final loudest = out.reduce(math.max);
  final scale = 1 / math.max(loudest, 0.25);
  return [for (final v in out) (v * scale * 100).round().clamp(0, 100)];
}

/// A stand-in waveform for voice notes sent before waveforms were saved:
/// speech-like bumps, always the same for the same [seed] (the message id).
List<int> pseudoWave(String seed, {int bars = kVoiceWaveBars}) {
  // FNV-1a, so the shape doesn't change between app versions or platforms.
  var h = 0x811c9dc5;
  for (final c in seed.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  final rnd = math.Random(h);
  var prev = 40.0;
  return [
    for (var i = 0; i < bars; i++)
      () {
        // Wander, with the odd pause between words.
        final next = rnd.nextDouble() < 0.12 ? 12.0 + rnd.nextInt(10) : (prev * 0.45 + (25 + rnd.nextInt(70)) * 0.55);
        prev = next;
        return next.round().clamp(8, 100);
      }(),
  ];
}

/// Postgres smallint[] from the API (a JSON list) or a realtime payload
/// (sometimes the "{1,2,3}" text form).
List<int>? parseWave(Object? raw) {
  if (raw == null) return null;
  if (raw is List) return [for (final v in raw) if (v is num) v.toInt() else if (v is String && int.tryParse(v) != null) int.parse(v)];
  if (raw is String) {
    final s = raw.replaceAll(RegExp(r'[{}\[\]\s]'), '');
    if (s.isEmpty) return const [];
    return [for (final p in s.split(',')) if (int.tryParse(p) != null) int.parse(p)];
  }
  return null;
}
