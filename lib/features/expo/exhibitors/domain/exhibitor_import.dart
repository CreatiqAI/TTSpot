import 'exhibitor.dart';

/// The fields a pasted exhibitor list can fill.
enum ImportField { name, booths, category, country, phone, email, website, about }

/// One parsed exhibitor, ready for `import_event_exhibitors`.
class ExhibitorImportRow {
  ExhibitorImportRow({required this.name, this.booths = const [], this.category, this.country, this.phone, this.email, this.website, this.about});
  final String name;
  List<String> booths;
  String? category;
  String? country;
  String? phone;
  String? email;
  String? website;
  String? about;

  Map<String, dynamic> toJson() => {
        'name': name,
        'booths': booths,
        if (category != null) 'category': category,
        if (country != null) 'country': country,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (website != null) 'website': website,
        if (about != null) 'about': about,
      };
}

/// What the paste box understood.
class ExhibitorImport {
  const ExhibitorImport({this.rows = const [], this.columns = const {}, this.skipped = 0, this.error});

  /// One per exhibitor (same names merged).
  final List<ExhibitorImportRow> rows;

  /// Which column each field came from.
  final Map<ImportField, int> columns;

  /// Data lines without a name.
  final int skipped;

  /// Why nothing could be read, or null.
  final String? error;

  bool get ok => error == null && rows.isNotEmpty;
}

/// Parses pasted CSV or tab-separated text with a header row. Headers are
/// matched loosely (Company / Exhibitor -> name, Booth No -> booths, ...).
/// Quoted fields may hold commas, tabs, doubled quotes and line breaks.
/// Rows with the same name (any case) merge: booths add up, blanks fill.
ExhibitorImport parseExhibitorList(String text) {
  final src = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (src.trim().isEmpty) return const ExhibitorImport(error: 'Paste your list first.');
  final delimiter = detectDelimiter(src);
  final table = parseDelimited(src, delimiter).where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
  if (table.isEmpty) return const ExhibitorImport(error: 'Paste your list first.');

  final columns = matchHeaders(table.first);
  if (!columns.containsKey(ImportField.name)) {
    return ExhibitorImport(columns: columns, error: 'Add a header row with a Name or Company column.');
  }

  final byName = <String, ExhibitorImportRow>{};
  var skipped = 0;
  String? cell(List<String> row, ImportField f) {
    final i = columns[f];
    if (i == null || i >= row.length) return null;
    final v = row[i].trim().replaceAll(RegExp(r'\s+'), ' ');
    return v.isEmpty ? null : v;
  }

  String? clip(String? v, int max) => v == null || v.length <= max ? v : v.substring(0, max);

  for (final row in table.skip(1)) {
    final name = clip(cell(row, ImportField.name), 120);
    if (name == null) {
      skipped++;
      continue;
    }
    final booths = parseBoothCodes(cell(row, ImportField.booths) ?? '');
    final about = columns[ImportField.about] == null || columns[ImportField.about]! >= row.length ? null : row[columns[ImportField.about]!].trim();
    final r = ExhibitorImportRow(
      name: name,
      booths: booths,
      category: clip(cell(row, ImportField.category), 60),
      country: clip(cell(row, ImportField.country), 40),
      phone: clip(cell(row, ImportField.phone), 60),
      email: clip(cell(row, ImportField.email), 120),
      website: clip(cell(row, ImportField.website), 200),
      about: clip(about == null || about.isEmpty ? null : about, 1000),
    );
    final key = name.toLowerCase();
    final had = byName[key];
    if (had == null) {
      byName[key] = r;
    } else {
      had.booths = [...had.booths, ...r.booths.where((b) => !had.booths.contains(b))];
      had.category ??= r.category;
      had.country ??= r.country;
      had.phone ??= r.phone;
      had.email ??= r.email;
      had.website ??= r.website;
      had.about ??= r.about;
    }
  }
  final rows = byName.values.toList();
  return ExhibitorImport(
    rows: rows,
    columns: columns,
    skipped: skipped,
    error: rows.isEmpty ? 'No rows with a name under the header.' : null,
  );
}

/// Tab if the header line has one, else semicolon if it has those and no
/// commas (European Excel), else comma.
String detectDelimiter(String text) {
  final firstLine = text.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  if (firstLine.contains('\t')) return '\t';
  if (firstLine.contains(';') && !firstLine.contains(',')) return ';';
  return ',';
}

/// RFC 4180-style split: quotes wrap fields, "" is a quote, and quoted
/// fields may span lines.
List<List<String>> parseDelimited(String text, String delimiter) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
      continue;
    }
    if (ch == '"' && field.toString().trim().isEmpty) {
      // Opening quote (spaces before it, as in `a, "b"`, are dropped).
      field.clear();
      inQuotes = true;
    } else if (ch == delimiter) {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

/// Header cell -> field, loosely. First column wins for each field.
Map<ImportField, int> matchHeaders(List<String> header) {
  final out = <ImportField, int>{};
  for (var i = 0; i < header.length; i++) {
    final f = fieldForHeader(header[i]);
    if (f != null) out.putIfAbsent(f, () => i);
  }
  return out;
}

ImportField? fieldForHeader(String raw) {
  final h = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  if (h.isEmpty) return null;
  if (h.contains('booth') || h.startsWith('stand') || h == 'hall' || h == 'lot') return ImportField.booths;
  // A person's name, not the company's.
  if (h.startsWith('contact') && (h.contains('name') || h.contains('person'))) return null;
  if (h.contains('mail')) return ImportField.email;
  if (h.contains('web') || h == 'url' || h == 'site' || h.contains('homepage')) return ImportField.website;
  if (h.contains('phone') || h.startsWith('tel') || h.contains('mobile') || h == 'contact' || h == 'contactno' || h == 'contactnumber' || h == 'hp') return ImportField.phone;
  if (h.contains('country') || h == 'origin' || h == 'nation') return ImportField.country;
  if (h.contains('categor') || h == 'type' || h == 'sector' || h == 'industry' || h == 'segment') return ImportField.category;
  if (h.contains('about') || h.contains('descr') || h == 'profile' || h == 'products' || h == 'details' || h == 'info') return ImportField.about;
  if (h.contains('name') || h.contains('company') || h.contains('exhibitor') || h == 'brand' || h == 'organisation' || h == 'organization') return ImportField.name;
  return null;
}
