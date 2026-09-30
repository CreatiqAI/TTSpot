import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/open_external.dart';

/// TiTi's small formatter (no markdown package): paragraphs, "- " bullets,
/// "1. " steps, **bold**, [label](url) and bare https links. Web links open
/// outside the app, app paths open inside it. Half-written markup (the
/// answer is still streaming) never shows its asterisks or brackets.
class TitiText extends StatefulWidget {
  const TitiText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  State<TitiText> createState() => _TitiTextState();
}

class _TitiTextState extends State<TitiText> {
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  void _drop() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  // The chat redraws every ~40 ms while an answer streams. Older bubbles hand
  // back the very same widget, so their links (and any tap in progress) live on.
  Widget? _built;
  String? _builtText;
  TextStyle? _builtStyle;
  bool? _builtDark;

  @override
  Widget build(BuildContext context) {
    if (_built != null && _builtText == widget.text && _builtStyle == widget.style && _builtDark == AppColors.dark) return _built!;
    _drop(); // new words: the old recognizers go
    _builtText = widget.text;
    _builtStyle = widget.style;
    _builtDark = AppColors.dark;
    return _built = _render(context);
  }

  Widget _render(BuildContext context) {
    final base = widget.style ?? TextStyle(fontSize: 15, height: 1.38, color: AppColors.textPrimary);
    final blocks = _parseBlocks(widget.text);
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (i > 0) children.add(SizedBox(height: b.kind == _Kind.para || blocks[i - 1].kind == _Kind.para ? 8 : 4));
      final spans = _inline(context, b.text, base);
      if (b.kind == _Kind.para) {
        children.add(Text.rich(TextSpan(children: spans), style: b.bold ? base.copyWith(fontWeight: FontWeight.w700) : base));
      } else {
        children.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: b.kind == _Kind.bullet ? 16 : 22,
              child: Text(b.kind == _Kind.bullet ? '•' : '${b.number}.', style: base.copyWith(fontWeight: FontWeight.w700, color: b.kind == _Kind.bullet ? AppColors.brand : AppColors.textPrimary)),
            ),
            Expanded(child: Text.rich(TextSpan(children: spans), style: base)),
          ],
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }

  static final _token = RegExp(r'\*\*(.+?)\*\*|\[([^\]\n]+)\]\(([^)\s]+)\)|(https?://[^\s<>()\[\]]*[^\s<>()\[\].,!?;:"' "'" r'])');
  // A link still being typed at the very end: "[Points](/me/po".
  static final _openLink = RegExp(r'\[([^\]\n]+)\]\([^)\s]*$');

  List<InlineSpan> _inline(BuildContext context, String text, TextStyle base) {
    final out = <InlineSpan>[];
    final linkStyle = base.copyWith(color: AppColors.brand, fontWeight: FontWeight.w600);
    void plain(String s) {
      if (s.isEmpty) return;
      // An unclosed ** while streaming: bold from there on, marker hidden.
      final open = s.indexOf('**');
      if (open >= 0) {
        if (open > 0) out.add(TextSpan(text: s.substring(0, open)));
        out.add(TextSpan(text: s.substring(open + 2).replaceAll('**', ''), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else {
        out.add(TextSpan(text: s));
      }
    }

    var rest = text;
    final tail = _openLink.firstMatch(rest);
    String? tailLabel;
    if (tail != null) {
      tailLabel = tail.group(1);
      rest = rest.substring(0, tail.start);
    }
    var at = 0;
    for (final m in _token.allMatches(rest)) {
      plain(rest.substring(at, m.start));
      at = m.end;
      if (m.group(1) != null) {
        out.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else {
        final label = m.group(2) ?? m.group(4)!;
        final target = m.group(3) ?? m.group(4)!;
        final tap = _tapFor(context, target);
        if (tap == null) {
          plain(label); // not a link we open: keep the words
        } else {
          final r = TapGestureRecognizer()..onTap = tap;
          _taps.add(r);
          out.add(TextSpan(text: label.replaceAll('**', ''), style: linkStyle, recognizer: r));
        }
      }
    }
    plain(rest.substring(at));
    if (tailLabel != null) out.add(TextSpan(text: tailLabel, style: linkStyle));
    return out;
  }

  VoidCallback? _tapFor(BuildContext context, String target) {
    if (target.startsWith('https://') || target.startsWith('http://')) return () => openExternal(context, target);
    final path = Uri.tryParse(target)?.path ?? '';
    if (!_appPaths.any((p) => p.endsWith('/') ? path.startsWith(p) : path == p)) return null;
    // The four tabs switch branch; everything else stacks on top.
    if (_tabs.contains(path)) return () => context.go(target);
    return () => context.push(target);
  }

  static const _tabs = {Routes.explore, Routes.map, Routes.inbox, Routes.garage};

  /// App paths TiTi may link to (the function's APP_LINKS, plus card-style pages).
  static const _appPaths = [
    Routes.points, Routes.cards, Routes.rewards, Routes.scan, Routes.myQr, Routes.friends, Routes.meets, Routes.clubs,
    Routes.map, Routes.inbox, Routes.explore, Routes.garage, Routes.suggestSpot, Routes.newCar, Routes.myGarage,
    Routes.createEvent, Routes.organizerApply, Routes.clubApply, Routes.partnerApply, Routes.settings, Routes.myMoments,
    '/event/', '/place/', '/club/', '/partner/', '/car/', '/profile/',
  ];
}

enum _Kind { para, bullet, numbered }

class _Block {
  _Block(this.kind, this.text, {this.number = 0, this.bold = false});
  final _Kind kind;
  String text;
  final int number;
  final bool bold;
}

final _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
final _numbered = RegExp(r'^\s*(\d{1,2})[.)]\s+(.*)$');
final _heading = RegExp(r'^\s*#{1,6}\s+(.*)$');

/// Lines → paragraphs, bullets and numbered steps. Blank lines split paragraphs.
List<_Block> _parseBlocks(String text) {
  final blocks = <_Block>[];
  var gap = true;
  for (final raw in text.trim().split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      gap = true;
      continue;
    }
    final b = _bullet.firstMatch(line), n = _numbered.firstMatch(line), h = _heading.firstMatch(line);
    if (b != null) {
      blocks.add(_Block(_Kind.bullet, b.group(1)!));
    } else if (n != null) {
      blocks.add(_Block(_Kind.numbered, n.group(2)!, number: int.parse(n.group(1)!)));
    } else if (h != null) {
      blocks.add(_Block(_Kind.para, h.group(1)!.replaceAll('**', ''), bold: true));
    } else if (!gap && blocks.isNotEmpty && blocks.last.kind == _Kind.para && !blocks.last.bold) {
      blocks.last.text += '\n${line.trim()}';
    } else {
      blocks.add(_Block(_Kind.para, line.trim()));
    }
    gap = false;
  }
  return blocks;
}
