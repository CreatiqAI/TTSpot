import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// go_router takes the first route that matches. A literal path declared
/// after a parameter route that also matches it never opens: /partner/apply
/// used to land on /partner/:id (a partner called "apply") and spin forever.
void main() {
  test('no route is shadowed by an earlier :param route', () {
    final src = File('lib/core/router/app_router.dart').readAsStringSync();
    final consts = {for (final m in RegExp(r"static const (\w+) = '([^']+)';").allMatches(src)) m[1]!: m[2]!};
    final paths = <String>[
      for (final m in RegExp(r'GoRoute\(\s*path:\s*([^,]+),').allMatches(src))
        switch (m[1]!.trim()) {
          final p when p.startsWith('Routes.') => consts[p.substring(7)] ?? p,
          final p => p.replaceAll("'", ''),
        },
    ];
    expect(paths, contains('/partner/apply'));

    RegExp pattern(String route) => RegExp('^${route.split('/').map((s) => s.startsWith(':') ? '[^/]+' : RegExp.escape(s)).join('/')}\$');
    final shadowed = <String>[];
    for (var i = 0; i < paths.length; i++) {
      if (!paths[i].contains(':')) continue;
      for (final later in paths.skip(i + 1)) {
        if (!later.contains(':') && pattern(paths[i]).hasMatch(later)) shadowed.add('$later is hidden by ${paths[i]}');
      }
    }
    expect(shadowed, isEmpty);
  });
}
