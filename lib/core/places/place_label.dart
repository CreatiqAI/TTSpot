/// One line for a picked place: "name, address", unless the address already
/// says the name (Google and Mapbox often start a street address with it:
/// name "2, Jalan Suria Park 1", address "2, Jln Suria Park 1, Bandar …").
String placeLabel(String name, String address) {
  final n = name.trim();
  final a = address.trim();
  if (a.isEmpty) return n;
  if (n.isEmpty) return a;
  final nn = normalizePlaceText(n);
  // Whole words only: "2 Jalan Suria Park 1" is not inside "12 Jalan Suria Park 10".
  if (nn.isEmpty || ' ${normalizePlaceText(a)} '.contains(' $nn ')) return a;
  return '$n, $a';
}

/// Common Malaysian street-address abbreviations, folded to one spelling.
const _abbrev = {
  'jln': 'jalan',
  'lrg': 'lorong',
  'tmn': 'taman',
  'psn': 'persiaran',
  'pers': 'persiaran',
  'bdr': 'bandar',
  'kg': 'kampung',
  'kpg': 'kampung',
  'lbh': 'lebuh',
  'lbhrya': 'lebuhraya',
  'sek': 'seksyen',
  'sg': 'sungai',
  'bt': 'batu',
  'tg': 'tanjung',
  'pjs': 'pjs',
  'st': 'street',
  'rd': 'road',
  'ave': 'avenue',
  'no': '',
};

/// Lower case, punctuation dropped, abbreviations spelled out, single spaces.
String normalizePlaceText(String s) {
  final words = s
      .toLowerCase()
      .replaceAll(RegExp(r"[^\p{L}\p{N}]+", unicode: true), ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => _abbrev[w] ?? w)
      .where((w) => w.isNotEmpty);
  return words.join(' ');
}
