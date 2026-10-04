import 'package:car_meet/core/router/app_router.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/social/data/tags_repository.dart';
import 'package:car_meet/features/social/presentation/widgets/rich_caption.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Answers "who is @x" from a map; never reaches the network.
class _FakeTags extends TagsRepository {
  _FakeTags() : super(SupabaseClient('http://localhost', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final asked = <String>[];

  @override
  Future<String?> profileIdByUsername(String username) async {
    asked.add(username);
    return const {'keith_ek9': 'u-keith'}[username];
  }
}

/// A 360 x 800 phone at [scale].
Future<void> _pump(WidgetTester t, Widget child, {double scale = 1}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    child: MaterialApp(
      theme: AppTheme.current,
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    ),
  ));
  await t.pump();
}

RichText _rich(WidgetTester t) => t.widget<RichText>(find.descendant(of: find.byType(RichCaption), matching: find.byType(RichText)));

/// Every leaf TextSpan, in order.
List<TextSpan> _leaves(InlineSpan span) {
  final out = <TextSpan>[];
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null && s.text!.isNotEmpty) out.add(s);
    return true;
  });
  return out;
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('tags and mentions are bold brand-red links (text x$scale)', (t) async {
      final tags = <String>[];
      final people = <String>[];
      await _pump(
        t,
        RichCaption(
          text: 'Clean #Myvi build with @keith_ek9, see #大马',
          style: const TextStyle(fontSize: 14),
          leading: const [TextSpan(text: 'amir ', style: TextStyle(fontWeight: FontWeight.w600))],
          onTag: tags.add,
          onMention: people.add,
        ),
        scale: scale,
      );
      expect(t.takeException(), isNull);
      final spans = _leaves(_rich(t).text);
      expect(spans.map((s) => s.text).join(), 'amir Clean #Myvi build with @keith_ek9, see #大马');
      final links = spans.where((s) => s.recognizer != null).toList();
      expect(links.map((s) => s.text), ['#Myvi', '@keith_ek9', '#大马']);
      for (final l in links) {
        expect(l.style?.color, AppColors.brand);
        expect(l.style?.fontWeight, FontWeight.w600);
      }
      expect(spans.firstWhere((s) => s.text == ' build with ').recognizer, isNull);
      expect(_rich(t).textScaler, TextScaler.linear(scale), reason: 'captions follow the text size setting');

      await t.tapOnText(find.textRange.ofSubstring('#Myvi'));
      await t.tapOnText(find.textRange.ofSubstring('@keith_ek9'));
      await t.tapOnText(find.textRange.ofSubstring('#大马'));
      expect(tags, ['myvi', '大马']);
      expect(people, ['keith_ek9']);
    });
  }

  testWidgets('a long caption stops at maxLines with "… more"; a tap shows it all', (t) async {
    final tags = <String>[];
    final long = 'Sunday run from TTDI to Genting with the whole crew. ${'Great roads and better company all morning. ' * 8}#myvi';
    await _pump(t, RichCaption(text: long, maxLines: 3, style: const TextStyle(fontSize: 14, height: 1.4), onTag: tags.add));
    expect(t.takeException(), isNull);
    var rich = _rich(t);
    expect(rich.maxLines, 3);
    final shown = _leaves(rich.text).map((s) => s.text).join();
    expect(shown, endsWith('… more'));
    expect(shown.length, lessThan(long.length));
    // The cut lands at the end of a word.
    final body = shown.substring(0, shown.length - '… more'.length);
    expect(long.startsWith(body), isTrue);
    expect(long[body.length], ' ');

    final box = t.getRect(find.byType(RichCaption));
    await t.tapOnText(find.textRange.ofSubstring('more'));
    await t.pump();
    rich = _rich(t);
    expect(rich.maxLines, isNull);
    expect(_leaves(rich.text).map((s) => s.text).join(), long);
    expect(t.getRect(find.byType(RichCaption)).height, greaterThan(box.height));
    await t.tapOnText(find.textRange.ofSubstring('#myvi'));
    expect(tags, ['myvi'], reason: 'the tag at the end is live once shown');
  });

  testWidgets('a short caption shows whole, no "more"', (t) async {
    await _pump(t, const RichCaption(text: 'Short one #jdm', maxLines: 3));
    expect(_leaves(_rich(t).text).map((s) => s.text).join(), 'Short one #jdm');
    expect(_rich(t).maxLines, isNull);
  });

  testWidgets('by default a tag opens its page and a mention opens the profile', (t) async {
    final fake = _FakeTags();
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: RichCaption(text: '#Myvi with @keith_ek9 and @ghost_x #大马'))),
      GoRoute(path: '/tag/:tag', builder: (_, s) => Scaffold(body: Text('tag ${s.pathParameters['tag']}'))),
      GoRoute(path: '/profile/:id', builder: (_, s) => Scaffold(body: Text('profile ${s.pathParameters['id']}'))),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [tagsRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp.router(theme: AppTheme.current, routerConfig: router),
    ));
    await t.pump();

    await t.tapOnText(find.textRange.ofSubstring('#Myvi'));
    await t.pumpAndSettle();
    expect(find.text('tag myvi'), findsOneWidget);
    router.pop();
    await t.pumpAndSettle();

    // Not every script is URL-safe: the route encodes it and hands it back whole.
    expect(Routes.tag('大马'), '/tag/%E5%A4%A7%E9%A9%AC');
    await t.tapOnText(find.textRange.ofSubstring('#大马'));
    await t.pumpAndSettle();
    expect(find.text('tag 大马'), findsOneWidget);
    router.pop();
    await t.pumpAndSettle();

    await t.tapOnText(find.textRange.ofSubstring('@keith_ek9'));
    await t.pumpAndSettle();
    expect(find.text('profile u-keith'), findsOneWidget);
    router.pop();
    await t.pumpAndSettle();

    await t.tapOnText(find.textRange.ofSubstring('@ghost_x'));
    await t.pump();
    expect(find.text('No one is called @ghost_x.'), findsOneWidget);
    expect(fake.asked, ['keith_ek9', 'ghost_x']);
  });
}
