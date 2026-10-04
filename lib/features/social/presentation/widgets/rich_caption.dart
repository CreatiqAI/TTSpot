import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/tags_repository.dart';
import '../../domain/tags.dart';

/// Post text with live #tags and @mentions: a tag opens its page, a mention
/// opens that member's profile. Both show in the brand colour, bold.
///
/// With [maxLines] the text stops there with "… more" (a tap shows the
/// rest), like Instagram. [leading] goes in front on the first line (the
/// author's name in a feed caption). [onTag] / [onMention] replace the
/// default navigation (tests, or a screen that wants its own).
///
/// ```dart
/// RichCaption(text: post.caption ?? '', style: TextStyle(fontSize: 14), maxLines: 3)
/// ```
class RichCaption extends ConsumerStatefulWidget {
  const RichCaption({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.leading = const [],
    this.linkStyle,
    this.onTag,
    this.onMention,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final List<InlineSpan> leading;

  /// Overrides the tags' and mentions' look (default: brand red, bold).
  final TextStyle? linkStyle;
  final ValueChanged<String>? onTag;
  final ValueChanged<String>? onMention;

  @override
  ConsumerState<RichCaption> createState() => _RichCaptionState();
}

class _RichCaptionState extends ConsumerState<RichCaption> {
  List<CaptionToken> _tokens = const [];
  // One per token; null for plain runs.
  List<TapGestureRecognizer?> _taps = const [];
  late final TapGestureRecognizer _moreTap = TapGestureRecognizer()..onTap = _expand;
  bool _expanded = false;

  // The last "where to cut" answer, keyed by everything that changes it.
  Object? _cutKey;
  int? _cut;

  @override
  void initState() {
    super.initState();
    _tokenise();
  }

  @override
  void didUpdateWidget(covariant RichCaption old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _tokenise();
      _cutKey = null;
    }
  }

  @override
  void dispose() {
    _disposeTaps();
    _moreTap.dispose();
    super.dispose();
  }

  void _disposeTaps() {
    for (final r in _taps) {
      r?.dispose();
    }
  }

  void _tokenise() {
    _disposeTaps();
    _tokens = captionTokens(widget.text);
    _taps = [
      for (final t in _tokens)
        if (t.kind == CaptionTokenKind.text) null else _recognizer(t.kind, t.value),
    ];
  }

  TapGestureRecognizer _recognizer(CaptionTokenKind kind, String value) =>
      TapGestureRecognizer()..onTap = () => kind == CaptionTokenKind.tag ? _openTag(value) : _openMention(value);

  void _expand() {
    if (!_expanded && mounted) setState(() => _expanded = true);
  }

  void _openTag(String tag) {
    final cb = widget.onTag;
    if (cb != null) {
      cb(tag);
      return;
    }
    context.push(Routes.tag(tag));
  }

  Future<void> _openMention(String username) async {
    final cb = widget.onMention;
    if (cb != null) {
      cb(username);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final id = await ref.read(tagsRepositoryProvider).profileIdByUsername(username);
      if (!mounted) return;
      if (id == null) {
        messenger?.showSnackBar(SnackBar(content: Text('No one is called @$username.')));
        return;
      }
      context.push(Routes.profile(id));
    } catch (_) {
      messenger?.showSnackBar(const SnackBar(content: Text("Couldn't open that profile. Try again.")));
    }
  }

  /// The spans for the first [cut] characters of the text (all when null).
  List<InlineSpan> _spans(TextStyle link, int? cut) {
    final out = <InlineSpan>[...widget.leading];
    var at = 0;
    for (var i = 0; i < _tokens.length; i++) {
      if (cut != null && at >= cut) break;
      final t = _tokens[i];
      final whole = t.text;
      final shown = cut != null && at + whole.length > cut ? whole.substring(0, cut - at) : whole;
      at += whole.length;
      final tap = _taps[i];
      out.add(tap == null ? TextSpan(text: shown) : TextSpan(text: shown, style: link, recognizer: tap));
    }
    return out;
  }

  TextSpan _more(TextStyle base) => TextSpan(
        text: '… ',
        children: [TextSpan(text: 'more', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500), recognizer: _moreTap)],
      );

  /// How many characters fit in [maxLines] with "… more" after them, or
  /// null when the whole text fits.
  int? _fit(double width, TextStyle base, TextStyle link, TextScaler scaler, TextDirection dir, int maxLines) {
    final key = Object.hash(width, scaler, base, link, maxLines, dir, widget.text, Object.hashAll(widget.leading));
    if (key == _cutKey) return _cut;
    final painter = TextPainter(textDirection: dir, textScaler: scaler, maxLines: maxLines);
    bool fits(List<InlineSpan> spans) {
      painter.text = TextSpan(style: base, children: spans);
      painter.layout(maxWidth: width);
      return !painter.didExceedMaxLines;
    }

    int? cut;
    if (!fits(_spans(link, null))) {
      final more = _more(base);
      var lo = 0;
      var hi = widget.text.length;
      while (lo < hi) {
        final mid = (lo + hi + 1) ~/ 2;
        if (fits([..._spans(link, mid), more])) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      cut = _tidyCut(widget.text, lo);
    }
    painter.dispose();
    _cutKey = key;
    _cut = cut;
    return cut;
  }

  /// Back to the end of a word when one is close, never inside an emoji.
  static int _tidyCut(String text, int cut) {
    var n = cut;
    if (n > 0 && n < text.length && _isHighSurrogate(text.codeUnitAt(n - 1))) n--;
    final space = text.lastIndexOf(RegExp(r'\s'), n > 0 ? n - 1 : 0);
    if (space > 0 && n - space < 16 && n < text.length) n = space;
    while (n > 0 && text[n - 1].trim().isEmpty) {
      n--;
    }
    return n;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(widget.style);
    final link = const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600).merge(widget.linkStyle);
    final scaler = MediaQuery.textScalerOf(context);
    final max = widget.maxLines;
    if (max == null || _expanded) {
      return RichText(textScaler: scaler, text: TextSpan(style: base, children: _spans(link, null)));
    }
    return LayoutBuilder(builder: (context, c) {
      final cut = _fit(c.maxWidth, base, link, scaler, Directionality.of(context), max);
      if (cut == null) {
        return RichText(textScaler: scaler, text: TextSpan(style: base, children: _spans(link, null)));
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _expand,
        child: RichText(
          textScaler: scaler,
          maxLines: max,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(style: base, children: [..._spans(link, cut), _more(base)]),
        ),
      );
    });
  }
}
