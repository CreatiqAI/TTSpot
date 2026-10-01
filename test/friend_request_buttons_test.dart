import 'dart:async';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/friends/presentation/friend_request_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A request row like Activity's: avatar, sentence, then the buttons.
class _Row extends StatefulWidget {
  const _Row({super.key, required this.send});
  final Future<void> Function(RequestAnswer) send;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  final answers = FriendRequestAnswers();
  String? error;

  @override
  void initState() {
    super.initState();
    answers.addListener(() => setState(() {}));
  }

  Future<void> _answer(RequestAnswer a) async {
    try {
      await answers.answer('u1', a, () => widget.send(a));
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const SizedBox(width: 44, height: 44),
            const SizedBox(width: 12),
            const Expanded(child: Text('titi_onboard1 wants to be friends. 2h', maxLines: 3, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            FriendRequestButtons(
              answer: answers.of('u1'),
              onAccept: () => _answer(RequestAnswer.accepted),
              onDelete: () => _answer(RequestAnswer.removed),
              onMessage: () => setState(() => error = 'message'),
            ),
          ],
        ),
      );
}

Future<GlobalKey<_RowState>> _pump(WidgetTester t, Future<void> Function(RequestAnswer) send, {double scale = 1}) async {
  final key = GlobalKey<_RowState>();
  t.view.physicalSize = const Size(1080, 2340); // a 393 x 851 phone
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.current,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: Scaffold(body: Center(child: _Row(key: key, send: send))),
  ));
  return key;
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('Accept turns into Message at once and stays (text x$scale)', (t) async {
      final done = Completer<void>();
      final key = await _pump(t, (_) => done.future, scale: scale);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await t.tap(find.text('Accept'));
      await t.pumpAndSettle();
      // Optimistic: the server hasn't answered yet.
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      done.complete();
      await t.pumpAndSettle();
      expect(find.text('Message'), findsOneWidget);
      expect(key.currentState!.answers.of('u1'), RequestAnswer.accepted);
      expect(t.takeException(), isNull);

      await t.tap(find.text('Message'));
      await t.pump();
      expect(key.currentState!.error, 'message');
    });

    testWidgets('Delete leaves "Request removed" in the row (text x$scale)', (t) async {
      await _pump(t, (_) async {}, scale: scale);
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(find.text('Request removed'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('a failed answer puts the buttons back', (t) async {
    final fail = Completer<void>();
    final key = await _pump(t, (_) => fail.future);
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(find.text('Message'), findsOneWidget);
    fail.completeError(Exception('offline'));
    await t.pumpAndSettle();
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Message'), findsNothing);
    expect(key.currentState!.answers.of('u1'), isNull);
    expect(key.currentState!.error, contains('offline'));
  });

  test('a second tap while answering is ignored', () async {
    final answers = FriendRequestAnswers();
    var calls = 0;
    final first = answers.answer('u1', RequestAnswer.accepted, () async => calls++);
    await answers.answer('u1', RequestAnswer.removed, () async => calls++);
    await first;
    expect(calls, 1);
    expect(answers.of('u1'), RequestAnswer.accepted);
  });

  test('answered rows stay in the list after the server drops them', () {
    // (id, minutes ago), newest first like the notifications list.
    final fresh = [('a', 1), ('c', 30)];
    final kept = [('b', 10), ('a', 1), ('d', 60)];
    final out = keepAnsweredRows(fresh, kept, id: (r) => r.$1, newerFirst: (x, y) => x.$2.compareTo(y.$2));
    expect(out.map((r) => r.$1), ['a', 'b', 'c', 'd']);
    expect(identical(keepAnsweredRows(fresh, const <(String, int)>[], id: (r) => r.$1, newerFirst: (x, y) => 0), fresh), isTrue);
  });
}
