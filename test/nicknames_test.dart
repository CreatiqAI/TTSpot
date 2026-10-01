import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/widgets/user_avatar.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/friends/application/nicknames.dart';
import 'package:car_meet/features/social/domain/chat.dart';

Profile _p(String id, {String? name, String? handle}) => Profile(id: id, displayName: name, username: handle, createdAt: DateTime(2026));

void main() {
  group('resolveDisplayName: nickname, then name, then @handle', () {
    test('a nickname wins', () {
      expect(resolveDisplayName(nickname: 'Boss 老板', displayName: 'Aiman', username: 'aiman88'), 'Boss 老板');
    });
    test('no nickname: the display name', () {
      expect(resolveDisplayName(displayName: 'Aiman', username: 'aiman88'), 'Aiman');
    });
    test('no name either: the @handle', () {
      expect(resolveDisplayName(username: 'aiman88'), '@aiman88');
    });
    test('blank values count as missing and are trimmed', () {
      expect(resolveDisplayName(nickname: '   ', displayName: '  Aiman ', username: 'aiman88'), 'Aiman');
      expect(resolveDisplayName(nickname: '', displayName: ' ', username: 'aiman88'), '@aiman88');
      expect(resolveDisplayName(nickname: ' Boss ', displayName: 'Aiman'), 'Boss');
    });
    test('nothing at all: the fallback', () {
      expect(resolveDisplayName(), 'Member');
      expect(resolveDisplayName(username: ' ', fallback: 'Someone'), 'Someone');
    });
  });

  test('displayNameFor reads my nickname for that person only', () {
    final a = _p('a', name: 'Aiman', handle: 'aiman88');
    final b = _p('b', handle: 'keith');
    final nicks = {'a': 'Boss'};
    expect(displayNameFor(a, nicks), 'Boss');
    expect(displayNameFor(b, nicks), '@keith');
    expect(displayNameFor(a, const {}), 'Aiman');
    expect(displayNameFor(null, nicks), 'Member');
  });

  group('conversationTitle', () {
    final other = _p('u1', name: 'Aiman', handle: 'aiman88');
    test('a one-to-one chat takes my nickname for them', () {
      final c = Conversation(id: 'c1', kind: 'dm', other: other, members: [other], unread: 0);
      expect(conversationTitle(c, {'u1': 'Boss'}), 'Boss');
      expect(conversationTitle(c, const {}), 'Aiman');
    });
    test('meet chats and club / partner chats keep their own names', () {
      final meet = Conversation(id: 'c2', kind: 'meet', eventTitle: 'TiTi Night', members: [other], unread: 0);
      expect(conversationTitle(meet, {'u1': 'Boss'}), 'TiTi Night');
      final club = Conversation(id: 'c3', kind: 'dm', other: other, members: [other], unread: 0, clubId: 'k1', entityName: 'TT Crew');
      expect(conversationTitle(club, {'u1': 'Boss'}), 'TT Crew');
    });
  });

  test('push avatars match the app: the same seeded TiTi default (FNV-1a) as supabase/functions/push', () {
    // Values computed with the push function's defaultAvatar().
    expect(DefaultAvatars.forSeed('66666666-6666-6666-6666-666666666666'), 'assets/avatars/a2.png');
    expect(DefaultAvatars.forSeed('693b5344-1cf8-4366-96e7-ca196edfcf4d'), 'assets/avatars/a8.png');
    expect(DefaultAvatars.forSeed('abc'), 'assets/avatars/a4.png');
    expect(DefaultAvatars.forSeed('x'), 'assets/avatars/a8.png');
  });
}
