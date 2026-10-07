import 'door_models.dart';

/// One CSV cell: quoted when it holds a comma, quote or line break, and
/// defused when a spreadsheet would run it as a formula (=, @, or + / -
/// followed by something that isn't a number, so phone numbers stay as is).
String csvCell(Object? value) {
  var s = value == null ? '' : '$value';
  if (s.isNotEmpty) {
    final first = s[0];
    final formula = first == '=' ||
        first == '@' ||
        first == '\t' ||
        first == '\r' ||
        ((first == '+' || first == '-') && !RegExp(r'^[+-][0-9][0-9 ().-]*$').hasMatch(s));
    if (formula) s = "'$s";
  }
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    s = '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String csvRow(Iterable<Object?> cells) => cells.map(csvCell).join(',');

String _two(int n) => n.toString().padLeft(2, '0');

/// "2026-10-08 14:05" in the phone's time zone.
String csvTime(DateTime? t) => t == null ? '' : '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

/// One answer as text: choices joined with "; ".
String answerText(Object? a) {
  if (a == null) return '';
  if (a is List) return a.map((x) => '$x').join('; ');
  return '$a';
}

/// The registrations CSV: fixed columns, then one column per question (by
/// its label), in the form's order. Answers to questions no longer on the
/// form are dropped. CRLF line ends, as spreadsheets expect.
String buildRegistrationCsv({required List<FormQuestion> questions, required List<RegistrationExportRow> rows}) {
  final header = ['Entry', 'Name', 'Username', 'Phone', 'Email', 'State', 'Car', 'Checked in', for (final q in questions) q.label];
  final lines = <String>[csvRow(header)];
  for (final r in rows) {
    lines.add(csvRow([
      r.entryNo == null ? '' : entryLabel(r.entryNo!),
      r.name,
      r.username, // no "@": spreadsheets read a leading @ as a formula
      r.phone,
      r.email,
      r.state,
      r.car,
      csvTime(r.checkedInAt),
      for (final q in questions) answerText(r.answers[q.id]),
    ]));
  }
  return '${lines.join('\r\n')}\r\n';
}
