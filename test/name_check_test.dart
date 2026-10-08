import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/core/utils/friendly_error.dart';
import 'package:car_meet/features/safety/application/name_check.dart';

const _notAllowed = "That name isn't allowed. Try another.";
const _reserved = 'That name is reserved.';

/// Stands in for check_name, and counts the calls.
class _Fake {
  final calls = <String>[];
  bool offline = false;
  Future<String?> call(String text, NameKind kind) async {
    calls.add(text);
    if (offline) throw Exception('SocketException');
    final t = text.toLowerCase();
    if (t.contains('cibai')) return _notAllowed;
    if (kind != NameKind.title && t.startsWith('ttspot')) return _reserved;
    return null;
  }
}

/// A name field wired the way the app's screens are.
class _Field extends StatefulWidget {
  const _Field({required this.check, this.kind = NameKind.name, this.saved});
  final NameCheck check;
  final NameKind kind;
  final String? saved;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  final _ctl = TextEditingController();
  late final LiveNameCheck _nameCheck;
  String? saveResult;

  @override
  void initState() {
    super.initState();
    _nameCheck = LiveNameCheck(controller: _ctl, kind: widget.kind, check: widget.check, saved: widget.saved)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    if (widget.saved != null) _ctl.text = widget.saved!;
  }

  @override
  void dispose() {
    _nameCheck.dispose();
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p = await _nameCheck.verify();
    setState(() => saveResult = p == null ? 'saved' : 'blocked');
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextField(controller: _ctl, decoration: InputDecoration(labelText: 'Name', errorText: _nameCheck.problem, errorMaxLines: 2)),
          TextButton(onPressed: _save, child: const Text('Save')),
          if (saveResult != null) Text(saveResult!),
        ],
      );
}

Future<void> _pump(WidgetTester t, Widget child, {double scale = 1.0}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.current,
    builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
  ));
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('a rude name shows the reason under the field after a pause (text $scale)', (t) async {
      final fake = _Fake();
      await _pump(t, _Field(check: fake.call), scale: scale);
      await t.enterText(find.byType(TextField), 'Cibai Racing');
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text(_notAllowed), findsNothing, reason: 'waits for the member to stop typing');
      expect(fake.calls, isEmpty);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(_notAllowed), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.enterText(find.byType(TextField), 'Assam Racing');
      await t.pump(const Duration(milliseconds: 450));
      expect(find.text(_notAllowed), findsNothing);
    });
  }

  testWidgets('Save is blocked while the name is refused, then goes through', (t) async {
    final fake = _Fake();
    await _pump(t, _Field(check: fake.call, kind: NameKind.handle));
    // Tapping Save before the pause is over still checks the name.
    await t.enterText(find.byType(TextField), 'ttspot_official');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('blocked'), findsOneWidget);
    expect(find.text(_reserved), findsOneWidget);

    await t.enterText(find.byType(TextField), 'kok_wai');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('saved'), findsOneWidget);
    expect(find.text(_reserved), findsNothing);
  });

  testWidgets('the saved name is never re-checked, so old names do not block edits', (t) async {
    final fake = _Fake();
    await _pump(t, _Field(check: fake.call, saved: 'TT Spot Crew'));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('saved'), findsOneWidget);
    expect(fake.calls, isEmpty);
  });

  testWidgets('offline: the check counts as fine (the server still refuses on save)', (t) async {
    final fake = _Fake()..offline = true;
    await _pump(t, _Field(check: fake.call));
    await t.enterText(find.byType(TextField), 'Cibai');
    await t.pump(const Duration(milliseconds: 450));
    expect(find.text(_notAllowed), findsNothing);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('saved'), findsOneWidget);
  });

  test("friendlyError shows the server's name filter reason as it is", () {
    expect(
      friendlyError(const PostgrestException(message: _reserved, code: 'P0001', hint: 'name_filter')),
      _reserved,
    );
    expect(
      friendlyError(const PostgrestException(message: _notAllowed, code: 'P0001', hint: 'name_filter')),
      _notAllowed,
    );
  });
}
