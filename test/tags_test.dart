import 'package:car_meet/features/social/domain/post.dart';
import 'package:car_meet/features/social/domain/tags.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _at(String text, [int? caret]) => TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret ?? text.length));

FeedPost _feed(String? reason) => FeedPost(
      post: Post(id: 'p', authorId: 'a', kind: PostKind.post, photoUrls: const [], coverAspect: 1, createdAt: DateTime(2026), likeCount: 0, commentCount: 0, voteCount: 0),
      likedByMe: false,
      savedByMe: false,
      reason: reason,
    );

void main() {
  group('parseTags (same rules as the database trigger)', () {
    test('the dry-run caption', () {
      // Matches 0101's parse_tags: lowercase, no repeats, 2 to 30 chars, not after a word or &.
      expect(
        parseTags('#Myvi weekend run with #TTDI crew #myvi #a #x123456789012345678901234567890y abc#nope &#39; (#jdm)'),
        ['myvi', 'ttdi', 'jdm'],
      );
    });

    test('letters in any script, digits, underscores', () {
      expect(parseTags('Sunday #Drift meet #大马'), ['drift', '大马']);
      expect(parseTags('#911 #honda_civic #ÉtéCar'), ['911', 'honda_civic', 'étécar']);
    });

    test('a title and caption together, punctuation ends a tag', () {
      expect(parseTags('Top #Sunrise drives no tags here abc#nope'), ['sunrise']);
      expect(parseTags('#myvi, #jdm. #kl!'), ['myvi', 'jdm', 'kl']);
      expect(parseTags('##double #ok'), ['double', 'ok']);
    });

    test('first 10 only', () {
      final tags = parseTags('#t01 #t02 #t03 #t04 #t05 #t06 #t07 #t08 #t09 #t10 #t11 #t12 #T01');
      expect(tags.length, 10);
      expect(tags.first, 't01');
      expect(tags.last, 't10');
    });

    test('nothing to find', () {
      expect(parseTags(null), isEmpty);
      expect(parseTags(''), isEmpty);
      expect(parseTags('no tags, an email a#b and # alone'), isEmpty);
    });
  });

  test('normaliseTag and tagFromName', () {
    expect(normaliseTag('#Myvi'), 'myvi');
    expect(normaliseTag(' myvi '), 'myvi');
    expect(normaliseTag('a'), isNull);
    expect(normaliseTag('my vi'), isNull);
    expect(normaliseTag('x' * 31), isNull);
    expect(tagFromName('Civic Type R'), 'civictyper');
    expect(tagFromName('Perodua'), 'perodua');
    expect(tagFromName('X'), isNull);
    expect(tagFromName(null), isNull);
  });

  group('captionTokens', () {
    test('tags and mentions, the rest as written', () {
      const text = 'Clean #Myvi build with @Keith_EK9, mail me at keith@ttspot.my #a';
      final tokens = captionTokens(text);
      expect(tokens.map((t) => t.text).join(), text, reason: 'joining the tokens gives the text back');
      expect([for (final t in tokens) if (t.kind != CaptionTokenKind.text) t], [
        const CaptionToken(CaptionTokenKind.tag, '#Myvi', 'myvi'),
        const CaptionToken(CaptionTokenKind.mention, '@Keith_EK9', 'keith_ek9'),
      ]);
    });

    test('a mention too short or too long is plain text', () {
      expect(captionTokens('@ab and @${'a' * 21}').where((t) => t.kind == CaptionTokenKind.mention), isEmpty);
      expect(captionTokens('(@abc)').where((t) => t.kind == CaptionTokenKind.mention).single.value, 'abc');
    });

    test('plain text only', () {
      expect(captionTokens('just words'), [const CaptionToken(CaptionTokenKind.text, 'just words')]);
      expect(captionTokens(''), isEmpty);
    });
  });

  group('activeCaptionQuery', () {
    test('a # word being typed', () {
      expect(activeCaptionQuery(_at('Hello #My')), const CaptionQuery(kind: CaptionTokenKind.tag, query: 'my', start: 6, end: 9));
      expect(activeCaptionQuery(_at('#')), const CaptionQuery(kind: CaptionTokenKind.tag, query: '', start: 0, end: 1));
      // Caret inside the word: the word runs on past it.
      expect(activeCaptionQuery(_at('go #myvi now', 6)), const CaptionQuery(kind: CaptionTokenKind.tag, query: 'my', start: 3, end: 8));
    });

    test('an @ word being typed', () {
      expect(activeCaptionQuery(_at('thanks @kei')), const CaptionQuery(kind: CaptionTokenKind.mention, query: 'kei', start: 7, end: 11));
      expect(activeCaptionQuery(_at('@')), const CaptionQuery(kind: CaptionTokenKind.mention, query: '', start: 0, end: 1));
    });

    test('not a tag or mention', () {
      expect(activeCaptionQuery(_at('plain words')), isNull);
      expect(activeCaptionQuery(_at('abc#my')), isNull);
      expect(activeCaptionQuery(_at('mail keith@tts')), isNull);
      expect(activeCaptionQuery(_at('&#39')), isNull);
      expect(activeCaptionQuery(_at('#myvi ')), isNull, reason: 'a space ends the word');
      expect(activeCaptionQuery(_at('@大马')), isNull, reason: 'handles are a-z, 0-9 and _');
      expect(activeCaptionQuery(const TextEditingValue(text: '#myvi', selection: TextSelection(baseOffset: 1, extentOffset: 4))), isNull);
    });
  });

  test('completeCaptionQuery puts the word in with a space after it', () {
    final v = _at('Hello #my');
    final done = completeCaptionQuery(v, activeCaptionQuery(v)!, '#myvi');
    expect(done.text, 'Hello #myvi ');
    expect(done.selection.baseOffset, done.text.length);

    final mid = _at('go #my now', 6);
    final midDone = completeCaptionQuery(mid, activeCaptionQuery(mid)!, '#myvi');
    expect(midDone.text, 'go #myvi now');
    expect(midDone.selection.baseOffset, 'go #myvi '.length);

    final at = _at('ride with @ke');
    expect(completeCaptionQuery(at, activeCaptionQuery(at)!, '@keith_ek9').text, 'ride with @keith_ek9 ');
  });

  test('why you are seeing this: a tag', () {
    expect(_feed('tag:myvi').reasonText, 'You like #myvi posts');
    expect(_feed('tag:').reasonText, 'Suggested for you');
    expect(_feed('make:honda').reasonText, 'You like Honda posts');
  });

  test('numbers', () {
    const stats = MyPostStats(views: 128, saves: 12, likes: 40, comments: 5, shares: 3);
    expect(stats.summary, '128 views · 12 saves · 3 shares');
    expect(const MyPostStats(views: 1, saves: 1, likes: 0, comments: 0, shares: 1).summary, '1 view · 1 save · 1 share');
    expect(const MyPostStats(views: 12345, saves: 0, likes: 0, comments: 0, shares: 0).summary, '12,345 views · 0 saves · 0 shares');
    expect(MyPostStats.fromMap({'views': 7, 'saves': 1, 'likes': 3, 'comments': 1, 'shares': 1}).likes, 3);
    expect(compactCount(950), '950');
    expect(compactCount(1000), '1k');
    expect(compactCount(1234), '1.2k');
    expect(compactCount(12345), '12k');
    expect(compactCount(1500000), '1.5m');
    expect(postCountLabel(1), '1 post');
    expect(postCountLabel(128), '128 posts');
    expect(postCountLabel(1234), '1,234 posts');
  });
}
