import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/open_external.dart';
import 'titi_routes.dart';

/// TiTi's small formatter (no markdown package): paragraphs, "- " bullets,
/// "1. " steps, **bold**, [label](url) and bare https links. Web links open
/// outside the app, app paths open inside it. Half-written markup (the
/// answer is still streaming) never shows its asterisks or brackets.
class TitiText extends StatefulWidget {
  const TitiText(this.text, {super.key, this.style, this.trailing, this.fade});
  final String text;
  final TextStyle? style;

  /// Room kept free at the end of the last line (for the bubble's time,
  /// WhatsApp style): when the line is too full, it wraps to a line of its own.
  final Size? trailing;

  /// While TiTi types: how far the newest letter has faded in (0-1]. The last
  /// [fadeWindow] letters ramp from faint to solid, so words ink in smoothly
  /// instead of popping.
  final double? fade;
  static const fadeWindow = 6;

  @override
  State<TitiText> createState() => _TitiTextState();
}

class _TitiTextState extends State<TitiText> {
  @override
  void dispose() {
    _drop(_blocks);
    super.dispose();
  }

  static void _drop(Iterable<_Built> built) {
    for (final b in built) {
      for (final t in b.taps) {
        t.dispose();
      }
    }
  }

  // The answer being typed redraws every frame, and a finished answer or the
  // list around it can rebuild too. Unchanged text hands back the very same
  // widget: no re-parse, and its links (and any tap in progress) live on.
  // While typing, every paragraph that is already complete keeps its widget
  // too, so only the growing last one is parsed and laid out again.
  Widget? _built;
  var _blocks = <_Built>[];
  String? _builtText;
  TextStyle? _builtStyle;
  bool? _builtDark;
  Size? _builtTrailing;
  double? _builtFade;

  @override
  Widget build(BuildContext context) {
    if (_built != null &&
        _builtText == widget.text &&
        _builtStyle == widget.style &&
        _builtDark == AppColors.dark &&
        _builtTrailing == widget.trailing &&
        _builtFade == widget.fade) {
      return _built!;
    }
    if (_builtStyle != widget.style || _builtDark != AppColors.dark) {
      _drop(_blocks); // a new look: nothing can be kept
      _blocks = [];
    }
    _builtText = widget.text;
    _builtStyle = widget.style;
    _builtDark = AppColors.dark;
    _builtTrailing = widget.trailing;
    _builtFade = widget.fade;
    return _built = _render(context);
  }

  Widget _render(BuildContext context) {
    final base = widget.style ?? TextStyle(fontSize: 15, height: 1.38, color: AppColors.textPrimary);
    final blocks = _parseBlocks(widget.text);
    final old = _blocks;
    final kept = <_Built>{};
    final built = <_Built>[];
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (i > 0) children.add(SizedBox(height: b.kind == _Kind.para || blocks[i - 1].kind == _Kind.para ? 8 : 4));
      final last = i == blocks.length - 1;
      // The last paragraph carries the fade and the time's room: always fresh.
      final plain = !last || (widget.fade == null && widget.trailing == null);
      final key = '${b.kind.index}|${b.number}|${b.bold}|${b.text}';
      if (plain && i < old.length && old[i].plain && old[i].key == key) {
        kept.add(old[i]);
        built.add(old[i]);
        children.add(old[i].widget);
        continue;
      }
      final taps = <TapGestureRecognizer>[];
      var spans = _inline(context, b.text, base, taps);
      final fade = widget.fade;
      if (last && fade != null) spans = _fadeTail(spans, base, fade);
      final room = widget.trailing;
      if (last && room != null) spans.add(WidgetSpan(alignment: PlaceholderAlignment.bottom, child: SizedBox.fromSize(size: room)));
      final Widget w;
      if (b.kind == _Kind.para) {
        w = Text.rich(TextSpan(children: spans), style: b.bold ? base.copyWith(fontWeight: FontWeight.w700) : base);
      } else {
        w = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: b.kind == _Kind.bullet ? 16 : 22,
              child: Text(b.kind == _Kind.bullet ? '•' : '${b.number}.', style: base.copyWith(fontWeight: FontWeight.w700, color: b.kind == _Kind.bullet ? AppColors.brand : AppColors.textPrimary)),
            ),
            Expanded(child: Text.rich(TextSpan(children: spans), style: base)),
          ],
        );
      }
      built.add(_Built(key, plain, w, taps));
      children.add(w);
    }
    // Paragraphs that changed or went: their link recognizers go with them.
    _drop(old.where((b) => !kept.contains(b)));
    _blocks = built;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }

  /// The last few letters, each a little fainter than the one before: the
  /// newest at [progress] / window, solid from the window's far end. Only the
  /// bubble being typed gets this (a handful of extra spans).
  static List<InlineSpan> _fadeTail(List<InlineSpan> spans, TextStyle base, double progress) {
    const window = TitiText.fadeWindow;
    final out = <InlineSpan>[];
    var fromEnd = 0; // letters handed out so far, newest first
    for (final s in spans.reversed) {
      final t = s is TextSpan ? s.text : null;
      if (fromEnd >= window || s is! TextSpan || t == null || t.isEmpty) {
        out.add(s);
        continue;
      }
      var k = t.length;
      while (k > 0 && fromEnd < window) {
        // One letter (both halves of an emoji together).
        var start = k - 1;
        final unit = t.codeUnitAt(start);
        if (start > 0 && unit >= 0xDC00 && unit <= 0xDFFF) start--;
        final color = s.style?.color ?? base.color ?? AppColors.textPrimary;
        final alpha = ((progress + fromEnd) / window).clamp(0.0, 1.0);
        out.add(TextSpan(text: t.substring(start, k), style: (s.style ?? const TextStyle()).copyWith(color: color.withValues(alpha: color.a * alpha)), recognizer: s.recognizer));
        k = start;
        fromEnd++;
      }
      if (k > 0) out.add(TextSpan(text: t.substring(0, k), style: s.style, recognizer: s.recognizer));
    }
    return out.reversed.toList();
  }

  static final _token = RegExp(r'\*\*(.+?)\*\*|\[([^\]\n]+)\]\(([^)\s]+)\)|(https?://[^\s<>()\[\]]*[^\s<>()\[\].,!?;:"' "'" r'])');
  // A link still being typed at the very end: "[Points](/me/po".
  static final _openLink = RegExp(r'\[([^\]\n]+)\]\([^)\s]*$');

  /// One paragraph's words → spans. Links get a recognizer, added to [taps].
  List<InlineSpan> _inline(BuildContext context, String text, TextStyle base, List<TapGestureRecognizer> taps) {
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
          taps.add(r);
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
    if (!titiCanOpen(target)) return null;
    return () => openTitiRoute(context, target);
  }
}

/// One rendered paragraph, kept while its text stays the same.
class _Built {
  _Built(this.key, this.plain, this.widget, this.taps);
  final String key;

  /// No fade and no time room: safe to hand back as it is.
  final bool plain;
  final Widget widget;
  final List<TapGestureRecognizer> taps;
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
