/// CSV for the organizer's exports. RFC 4180 quoting, CRLF lines, a UTF-8
/// byte-order mark so Excel shows Chinese and Malay names right, and a guard
/// against spreadsheet formulas in member-typed text.
library;

const csvBom = '﻿';

/// One cell. Text that a spreadsheet would run as a formula gets a leading
/// apostrophe; anything with a comma, quote or line break is quoted.
String csvCell(Object? v) {
  if (v == null) return '';
  if (v is num || v is bool) return '$v';
  var s = v is DateTime ? mytStamp(v) : '$v';
  if (s.isNotEmpty && const ['=', '+', '-', '@', '\t', '\r'].contains(s[0])) s = "'$s";
  if (s.contains(RegExp('[",\r\n]'))) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

String buildCsv(List<String> header, Iterable<List<Object?>> rows, {bool bom = true}) {
  final b = StringBuffer();
  if (bom) b.write(csvBom);
  b.write(header.map(csvCell).join(','));
  b.write('\r\n');
  for (final r in rows) {
    b.write(r.map(csvCell).join(','));
    b.write('\r\n');
  }
  return b.toString();
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Malaysia time (UTC+8, no daylight saving) as "2026-10-08 14:05:09",
/// whatever the phone's own zone is.
String mytStamp(DateTime t) {
  final m = t.toUtc().add(const Duration(hours: 8));
  return '${m.year}-${_two(m.month)}-${_two(m.day)} ${_two(m.hour)}:${_two(m.minute)}:${_two(m.second)}';
}

DateTime? _ts(Object? v) => v == null ? null : DateTime.tryParse('$v');

/// `expo_export_checkins` rows → CSV.
String checkinsCsv(List<Map<String, dynamic>> rows) => buildCsv(
      const ['Entry no', 'Name', 'Username', 'State', 'Car', 'Checked in (MYT)', 'Source'],
      [
        for (final r in rows)
          [
            r['entry_no'],
            r['name'],
            r['username'],
            r['state'],
            r['car'],
            _ts(r['checked_in_at']),
            r['source'],
          ],
      ],
    );

/// `expo_export_booth_visits` rows → CSV.
String boothVisitsCsv(List<Map<String, dynamic>> rows) => buildCsv(
      const ['Exhibitor', 'Booths', 'Username', 'Stamped (MYT)', 'Freebie (MYT)'],
      [
        for (final r in rows)
          [
            r['exhibitor'],
            r['booths'],
            r['username'],
            _ts(r['stamped_at']),
            _ts(r['freebie_redeemed_at']),
          ],
      ],
    );

/// A safe file name piece from an event title.
String csvSlug(String s) {
  final t = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return t.isEmpty ? 'event' : (t.length > 40 ? t.substring(0, 40) : t);
}
