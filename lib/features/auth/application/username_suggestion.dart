import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';

/// Is this username free? (`username_available`, the live check behind
/// UsernameField and the onboarding suggestion). Tests stand in for it.
typedef UsernameCheck = Future<bool> Function(String username);

final usernameAvailabilityProvider = Provider<UsernameCheck>((ref) {
  return (username) async => await ref.read(supabaseProvider).rpc('username_available', params: {'p_username': username}) as bool;
});

const _kMaxUsername = 20;
const _kMinUsername = 3;

const _accents = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ō': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

/// A username made from a display name: lowercase, the words joined by "_",
/// only a-z, 0-9 and "_", at most 20 characters, cut at a word where it can.
/// "Aiman Hakim" → "aiman_hakim". Null when the name gives nothing usable
/// (too short, or no Latin letters, e.g. a name in Chinese).
String? usernameFromName(String name) {
  final lower = name.toLowerCase();
  final buf = StringBuffer();
  for (final ch in lower.split('')) {
    buf.write(_accents[ch] ?? ch);
  }
  final words = buf
      .toString()
      .replaceAll(RegExp(r"['’`]"), '') // "Ah Meng's" → "ah_mengs"
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return null;
  var out = '';
  for (final w in words) {
    final next = out.isEmpty ? w : '${out}_$w';
    if (next.length > _kMaxUsername) {
      if (out.isEmpty) out = w.substring(0, _kMaxUsername);
      break;
    }
    out = next;
  }
  if (out.length < _kMinUsername) return null;
  return out;
}

/// [base] with a short number on the end, still within 20 characters:
/// "aiman_hakim" + 7 → "aiman_hakim7".
String withSuffix(String base, int n) {
  final tail = '$n';
  final room = _kMaxUsername - tail.length;
  var head = base.length > room ? base.substring(0, room) : base;
  head = head.replaceFirst(RegExp(r'_+$'), '');
  return '$head$tail';
}

/// The first free username for [name]: the plain one, else up to [tries]
/// with a short number added (1-99, random so two Aimans signing up at
/// once don't race for the same one). Null when nothing usable or free was
/// found, or the check failed (the member just types one).
Future<String?> suggestUsername(String name, UsernameCheck isFree, {math.Random? random, int tries = 6}) async {
  final base = usernameFromName(name);
  if (base == null) return null;
  final rnd = random ?? math.Random();
  try {
    if (await isFree(base)) return base;
    final used = <int>{};
    for (var i = 0; i < tries; i++) {
      // Single digits first: they read best.
      final n = i < 3 ? 1 + rnd.nextInt(9) : 10 + rnd.nextInt(90);
      if (!used.add(n)) continue;
      final candidate = withSuffix(base, n);
      if (await isFree(candidate)) return candidate;
    }
  } catch (_) {
    return null;
  }
  return null;
}
