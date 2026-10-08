import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/core/widgets/keyboard_dismissal.dart';
import 'package:car_meet/features/social/presentation/widgets/chat_composer.dart';
import 'package:car_meet/features/social/presentation/widgets/voice_recorder.dart';

// The owner: "every time I finish typing and press return, it closes the
// keyboard. Don't leave it stuck there." Return closes (or sends) everywhere,
// and a tap outside a field or a drag of the page closes it too.

/// A text field has focus, so the keyboard is up.
bool _typing() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

void main() {
  group('the app-wide safety net', () {
    Future<void> pump(WidgetTester t, {VoidCallback? onButton, VoidCallback? onInsideButton}) => t.pumpWidget(MaterialApp(
          theme: AppTheme.current,
          builder: (context, child) => KeyboardDismissal(child: child!),
          home: Scaffold(
            body: Column(
              children: [
                const TextField(key: Key('field')),
                TextButton(onPressed: onButton, child: const Text('Elsewhere')),
                SizedBox(
                  height: 80,
                  child: ListView(
                    key: const Key('sideways'),
                    scrollDirection: Axis.horizontal,
                    children: [for (var i = 0; i < 20; i++) SizedBox(width: 80, child: Text('chip $i'))],
                  ),
                ),
                Expanded(
                  child: ListView(
                    key: const Key('list'),
                    children: [for (var i = 0; i < 60; i++) SizedBox(height: 40, child: Text('row $i'))],
                  ),
                ),
                TextFieldTapRegion(child: TextButton(onPressed: onInsideButton, child: const Text('Send'))),
              ],
            ),
          ),
        ));

    testWidgets('a tap outside the field closes the keyboard, and the tap still lands', (t) async {
      var taps = 0;
      await pump(t, onButton: () => taps++);
      await t.tap(find.byKey(const Key('field')));
      await t.pump();
      expect(_typing(), isTrue);
      await t.tap(find.text('Elsewhere'));
      await t.pump();
      expect(_typing(), isFalse);
      expect(t.testTextInput.hasAnyClients, isFalse);
      expect(taps, 1, reason: 'the button under the finger still works');
    });

    testWidgets('a tap on plain background closes it too', (t) async {
      await pump(t);
      await t.tap(find.byKey(const Key('field')));
      await t.pump();
      await t.tap(find.text('row 3'));
      await t.pump();
      expect(_typing(), isFalse);
    });

    testWidgets('buttons inside a TextFieldTapRegion (a chat Send) keep the keyboard up', (t) async {
      var sends = 0;
      await pump(t, onInsideButton: () => sends++);
      await t.tap(find.byKey(const Key('field')));
      await t.pump();
      await t.tap(find.text('Send'));
      await t.pump();
      expect(sends, 1);
      expect(_typing(), isTrue);
    });

    testWidgets('tapping another field moves the keyboard there', (t) async {
      await t.pumpWidget(MaterialApp(
        builder: (context, child) => KeyboardDismissal(child: child!),
        home: const Scaffold(body: Column(children: [TextField(key: Key('a')), TextField(key: Key('b'))])),
      ));
      await t.tap(find.byKey(const Key('a')));
      await t.pump();
      await t.tap(find.byKey(const Key('b')));
      await t.pump();
      expect(t.widget<EditableText>(find.descendant(of: find.byKey(const Key('b')), matching: find.byType(EditableText))).focusNode.hasFocus, isTrue);
    });

    testWidgets('dragging a list closes it; a sideways swipe or a long press does not', (t) async {
      await pump(t);
      await t.tap(find.byKey(const Key('field')));
      await t.pump();

      await t.drag(find.byKey(const Key('sideways')), const Offset(-200, 0));
      await t.pumpAndSettle();
      expect(_typing(), isTrue, reason: 'carousels and swipe-to-reply leave the keyboard alone');

      await t.longPress(find.text('row 2'));
      await t.pumpAndSettle();
      expect(_typing(), isTrue, reason: 'a long-press menu leaves the keyboard alone');

      await t.drag(find.byKey(const Key('list')), const Offset(0, -200));
      await t.pumpAndSettle();
      expect(_typing(), isFalse);
    });

    testWidgets('a long field scrolling its own lines keeps the keyboard up', (t) async {
      final c = TextEditingController(text: List.generate(30, (i) => 'line $i').join('\n'));
      addTearDown(c.dispose);
      await t.pumpWidget(MaterialApp(
        builder: (context, child) => KeyboardDismissal(child: child!),
        home: Scaffold(
          body: ListView(children: [TextField(key: const Key('long'), controller: c, minLines: 1, maxLines: 4, keyboardType: TextInputType.text, textInputAction: TextInputAction.done)]),
        ),
      ));
      await t.tap(find.byKey(const Key('long')));
      await t.pump();
      await t.drag(find.byKey(const Key('long')), const Offset(0, -40));
      await t.pumpAndSettle();
      expect(_typing(), isTrue);
    });
  });

  group('chat composer', () {
    Future<(TextEditingController, List<String>)> pump(WidgetTester t, {bool sending = false}) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      final rec = VoiceRecorder(onReady: (_) async {}, onHint: (_) {});
      addTearDown(rec.dispose);
      final sent = <String>[];
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.current,
        builder: (context, child) => KeyboardDismissal(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              ChatComposer(
                controller: c,
                sending: sending,
                // Like the chat screen: nothing goes out empty, and the box clears.
                onSend: () {
                  if (c.text.trim().isEmpty) return;
                  sent.add(c.text.trim());
                  c.clear();
                },
                onPlus: () {},
                onCamera: () {},
                recorder: rec,
              ),
            ],
          ),
        ),
      ));
      return (c, sent);
    }

    testWidgets('return sends, like the Send button, and closes the keyboard', (t) async {
      final (c, sent) = await pump(t);
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.textInputAction, TextInputAction.send);
      expect(field.keyboardType, TextInputType.text, reason: 'a multiline keyboard would turn return into a newline');
      expect((field.minLines, field.maxLines), (1, 5), reason: 'long text still grows the box');

      await t.enterText(find.byType(TextField), 'otw, 10 min');
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pump();
      expect(sent, ['otw, 10 min']);
      expect(c.text, isEmpty);
      expect(_typing(), isFalse);
      expect(t.testTextInput.hasAnyClients, isFalse);
    });

    testWidgets('the Send button sends the same and keeps typing', (t) async {
      final (_, sent) = await pump(t);
      await t.enterText(find.byType(TextField), 'see you');
      await t.pump();
      await t.tap(find.byIcon(AppIcons.paperPlaneRight));
      await t.pump();
      expect(sent, ['see you']);
      expect(_typing(), isTrue, reason: 'the bar counts as inside the field');
    });

    testWidgets('return on an empty box sends nothing', (t) async {
      final (_, sent) = await pump(t);
      await t.enterText(find.byType(TextField), '   ');
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pump();
      expect(sent, isEmpty);
      expect(_typing(), isFalse);
    });

    testWidgets('return while a message is still going out does not send twice', (t) async {
      final (_, sent) = await pump(t, sending: true);
      await t.enterText(find.byType(TextField), 'again');
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pump();
      expect(sent, isEmpty);
    });
  });

  test('no multi-line field in lib/ turns return into a newline', () {
    // The exhibitor import box takes pasted rows: one line per exhibitor.
    const allowed = [r'Name\tBooth\tCategory'];
    final call = RegExp(r'\b(TextField|TextFormField|CupertinoTextField)\(');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in call.allMatches(src)) {
        var depth = 1, i = m.end;
        while (depth > 0 && i < src.length) {
          final ch = src[i++];
          if (ch == '(') depth++;
          if (ch == ')') depth--;
        }
        final args = src.substring(m.end, i - 1);
        final lines = RegExp(r'\bmaxLines:\s*([^,\n)]+)').firstMatch(args)?.group(1)?.trim();
        if (lines == null || lines == '1') continue;
        if (allowed.any(args.contains)) continue;
        final ok = args.contains('textInputAction:') && !args.contains('TextInputAction.newline') && args.contains('keyboardType:');
        if (!ok) offenders.add('${f.path}:${'\n'.allMatches(src.substring(0, m.start)).length + 1}');
      }
    }
    expect(offenders, isEmpty, reason: 'multi-line fields need textInputAction (done/send) and keyboardType: TextInputType.text');
  });
}
