/// One exhibitor at an expo (table `event_exhibitors`, read through the
/// `event_exhibitors_list` RPC, which adds the partner's logo and name).
class Exhibitor {
  Exhibitor({
    required this.id,
    required this.eventId,
    required this.name,
    this.booths = const [],
    this.category,
    this.country,
    this.about,
    this.phone,
    this.email,
    this.website,
    this.address,
    this.logoUrl,
    this.partnerVendorId,
    this.partnerLogo,
    this.partnerName,
    this.pinCount = 0,
    this.sort = 0,
  });

  final String id;
  final String eventId;
  final String name;

  /// Booth codes, e.g. [A019, A024].
  final List<String> booths;
  final String? category;
  final String? country;
  final String? about;
  final String? phone;
  final String? email;
  final String? website;
  final String? address;
  final String? logoUrl;

  /// Linked TT Spot partner (active partners only; null otherwise).
  final String? partnerVendorId;
  final String? partnerLogo;
  final String? partnerName;

  /// Booth pins on the floor plan that point at this exhibitor.
  final int pinCount;
  final int sort;

  bool get isPartner => partnerVendorId != null;

  /// The picture to show: own logo, else the partner's.
  String? get displayLogo => _blank(logoUrl) ?? _blank(partnerLogo);

  String get boothsLabel => booths.join(', ');

  /// Up to two letters for the logo placeholder.
  String get initials => initialsOf(name);

  /// Lower-case text matched by the search box: name, booths, category, country.
  late final String searchText = [name, ...booths, category ?? '', country ?? '', partnerName ?? ''].join(' ').toLowerCase();

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return q.split(RegExp(r'\s+')).every(searchText.contains);
  }

  factory Exhibitor.fromMap(Map<String, dynamic> m) => Exhibitor(
        id: m['id'] as String,
        eventId: m['event_id'] as String,
        name: m['name'] as String? ?? '',
        booths: ((m['booths'] as List?) ?? const []).map((e) => '$e').toList(),
        category: _blank(m['category'] as String?),
        country: _blank(m['country'] as String?),
        about: _blank(m['about'] as String?),
        phone: _blank(m['phone'] as String?),
        email: _blank(m['email'] as String?),
        website: _blank(m['website'] as String?),
        address: _blank(m['address'] as String?),
        logoUrl: _blank(m['logo_url'] as String?),
        partnerVendorId: m['partner_vendor_id'] as String?,
        partnerLogo: _blank(m['partner_logo'] as String?),
        partnerName: _blank(m['partner_name'] as String?),
        pinCount: (m['pin_count'] as num?)?.toInt() ?? 0,
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );
}

String? _blank(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

/// "Acme Wheels Sdn Bhd" -> "AW"; "bolt" -> "B".
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(w)).toList();
  if (words.isEmpty) return '?';
  String first(String w) => String.fromCharCode(w.runes.first).toUpperCase();
  return words.length == 1 ? first(words.first) : '${first(words[0])}${first(words[1])}';
}

/// Booth codes from free text: "A019, a024 / B7 & B8" -> [A019, A024, B7, B8].
/// Same rules as `public.expo_booth_codes` in SQL: split on , ; / | & and
/// spaces, trim, upper-case, drop repeats, at most 40 codes of 20 chars.
List<String> parseBoothCodes(String raw) {
  final out = <String>[];
  for (final part in raw.split(RegExp(r'[,;/|&\s]+'))) {
    final c = part.trim().toUpperCase();
    if (c.isEmpty) continue;
    final code = c.length > 20 ? c.substring(0, 20) : c;
    if (!out.contains(code)) out.add(code);
    if (out.length == 40) break;
  }
  return out;
}

/// Category chips for the directory: most common first, then A to Z.
List<String> exhibitorCategories(Iterable<Exhibitor> all) {
  final counts = <String, int>{};
  for (final e in all) {
    final c = e.category;
    if (c != null) counts[c] = (counts[c] ?? 0) + 1;
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final d = counts[b]!.compareTo(counts[a]!);
      return d != 0 ? d : a.toLowerCase().compareTo(b.toLowerCase());
    });
  return keys;
}

/// Partners first, then by sort, then by name.
List<Exhibitor> sortExhibitors(Iterable<Exhibitor> all) => all.toList()
  ..sort((a, b) {
    if (a.isPartner != b.isPartner) return a.isPartner ? -1 : 1;
    final s = a.sort.compareTo(b.sort);
    return s != 0 ? s : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

/// Turns a website field into a launchable URL ("acme.com" -> https://acme.com).
Uri? websiteUri(String? raw) {
  final t = raw?.trim() ?? '';
  if (t.isEmpty) return null;
  final withScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(t) ? t : 'https://$t';
  final u = Uri.tryParse(withScheme);
  return u == null || u.host.isEmpty ? null : u;
}

/// "+60 3-1234 5678" -> tel:+60312345678.
Uri? phoneUri(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
  return digits.replaceAll('+', '').length < 5 ? null : Uri(scheme: 'tel', path: digits);
}

Uri? emailUri(String? raw) {
  final t = raw?.trim() ?? '';
  return t.contains('@') ? Uri(scheme: 'mailto', path: t) : null;
}
