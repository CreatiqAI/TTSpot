import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/media.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../auth/domain/profile.dart';
import '../domain/chat.dart';
import 'social_repository.dart';

class ChatRepository {
  ChatRepository(this._client);
  final SupabaseClient _client;

  Future<String> openDm(String otherUserId) async {
    final id = await _client.rpc('get_or_create_dm', params: {'p_other': otherUserId});
    return id as String;
  }

  Future<String> openMeetChat(String eventId) async {
    final id = await _client.rpc('get_or_create_meet_chat', params: {'p_event': eventId});
    return id as String;
  }

  Future<void> setPin(String conversationId, bool pin) => _client.rpc('set_conversation_pin', params: {'p_conversation': conversationId, 'p_pin': pin});
  Future<void> hide(String conversationId) => _client.rpc('hide_conversation', params: {'p_conversation': conversationId});

  /// Posts and moments shared in a chat, newest first.
  Future<List<Message>> shared(String conversationId) async {
    final rows = await _client
        .from('messages')
        .select('*')
        .eq('conversation_id', conversationId)
        .or('post_id.not.is.null,story_id.not.is.null,image_url.not.is.null,video_url.not.is.null')
        .order('created_at', ascending: false)
        .limit(60);
    return rows.map(Message.fromMap).toList();
  }

  Future<void> setMute(String conversationId, bool muted) => _client.rpc('set_conversation_mute', params: {'p_conversation': conversationId, 'p_muted': muted});

  Future<String> openClubDm(String clubId) async => await _client.rpc('get_or_create_club_dm', params: {'p_club': clubId}) as String;
  Future<String> openVendorDmWith(String userId) async => await _client.rpc('get_or_create_vendor_dm_with', params: {'p_user': userId}) as String;
  Future<String> openVendorDm(String vendorId) async => await _client.rpc('get_or_create_vendor_dm', params: {'p_vendor': vendorId}) as String;

  Future<void> markRead(String conversationId) => _client.rpc('mark_conversation_read', params: {'p_conversation': conversationId});

  /// Which account's inbox: personal (everything not owned by a club /
  /// partner I manage), one club, or one partner.
  Future<List<Conversation>> inbox(String me, {InboxScope scope = const InboxScope.personal()}) async {
    final mine = await _client.from('conversation_members').select('conversation_id, pinned_at, hidden_at, muted_at').eq('user_id', me);
    if (mine.isEmpty) return const [];
    final ids = mine.map((r) => r['conversation_id'] as String).toList();
    final pinnedAt = {for (final r in mine) if (r['pinned_at'] != null) r['conversation_id'] as String: DateTime.parse(r['pinned_at'] as String)};
    final hiddenAt = {for (final r in mine) if (r['hidden_at'] != null) r['conversation_id'] as String: DateTime.parse(r['hidden_at'] as String)};
    final mutedAt = {for (final r in mine) if (r['muted_at'] != null) r['conversation_id'] as String: DateTime.parse(r['muted_at'] as String)};

    const convCols = 'id, kind, event_id, club_id, vendor_id, title, photo_url, created_by, events(title, cover_url), clubs!conversations_club_id_fkey(name, avatar_url), vendors!conversations_vendor_id_fkey(name, logo_url)';
    final results = await Future.wait<dynamic>([
      // Everyone in DMs, meet chats and friends' groups (100 at most) ...
      _client
          .from('conversations')
          .select('$convCols, conversation_members(user_id, is_admin, created_at, profiles($profileCols))')
          .inFilter('id', ids)
          .neq('kind', 'club')
          .order('created_at', ascending: true, referencedTable: 'conversation_members'),
      // ... but not a club chat's whole club: its size comes with the summaries.
      _client.from('conversations').select(convCols).inFilter('id', ids).eq('kind', 'club'),
      // Each chat's last message, unread count and size, worked out per chat
      // (20261005000100), so a busy group can't crowd the others out.
      _client.rpc('my_chat_summaries'),
    ]);

    final summaries = {for (final r in (results[2] as List).cast<Map<String, dynamic>>()) r['conversation_id'] as String: r};

    final convs = [...(results[0] as List), ...(results[1] as List)].map((raw) {
      final r = raw as Map<String, dynamic>;
      final id = r['id'] as String;
      final kind = r['kind'] as String;
      final group = kind == 'group' || kind == 'club';
      final event = r['events'] as Map<String, dynamic>?;
      final memberRows = ((r['conversation_members'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final members = memberRows.map((m) => m['profiles']).whereType<Map<String, dynamic>>().map(Profile.fromMap).toList();
      final clubId = r['club_id'] as String?;
      final vendorId = r['vendor_id'] as String?;
      final club = r['clubs'] as Map<String, dynamic>?;
      final vendor = r['vendors'] as Map<String, dynamic>?;
      // A club's members chat is everyone's own chat, never the club account's inbox.
      final viewAsEntity = kind != 'club' && scope.owns(clubId, vendorId);
      // In an entity chat the club's managers are members too; "the other person" is whoever is not staff.
      final staff = viewAsEntity ? <String>{me} : (scope.managedClubs.contains(clubId) || (vendorId != null && vendorId == scope.myVendorId) ? {me} : <String>{});
      final other = group ? null : members.where((p) => p.id != me && !staff.contains(p.id)).firstOrNull;
      final summary = summaries[id];
      final last = summary?['last_message'];
      return Conversation(
        id: id,
        kind: kind,
        eventId: r['event_id'] as String?,
        eventTitle: event?['title'] as String?,
        eventCover: event?['cover_url'] as String?,
        other: other,
        members: members,
        lastMessage: last is Map<String, dynamic> ? Message.fromMap(last) : null,
        unread: (summary?['unread'] as num?)?.toInt() ?? 0,
        pinnedAt: pinnedAt[id],
        hiddenAt: hiddenAt[id],
        clubId: clubId,
        vendorId: vendorId,
        entityName: club?['name'] as String? ?? vendor?['name'] as String?,
        entityLogo: club?['avatar_url'] as String? ?? vendor?['logo_url'] as String?,
        mutedAt: mutedAt[id],
        viewAsEntity: viewAsEntity,
        groupName: r['title'] as String?,
        photoUrl: r['photo_url'] as String?,
        createdBy: r['created_by'] as String?,
        memberCount: (summary?['member_count'] as num?)?.toInt(),
        adminIds: {for (final m in memberRows) if (m['is_admin'] == true) m['user_id'] as String},
        selfId: me,
      );
    }).where((c) => scope.includes(c)).where((c) {
      // "Deleted" chats stay hidden until a newer message arrives.
      final h = c.hiddenAt;
      if (h == null) return true;
      final last = c.lastMessage?.createdAt;
      return last != null && last.toUtc().isAfter(h.toUtc());
    }).toList();

    convs.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final ta = a.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return convs;
  }

  Future<Conversation?> conversation(String id, String me, {InboxScope scope = const InboxScope.personal()}) async {
    final all = await inbox(me, scope: InboxScope.all(scope));
    return all.where((c) => c.id == id).firstOrNull;
  }

  /// The newest [limit] messages, oldest first.
  Future<List<Message>> messages(String conversationId, {int limit = 200}) async {
    final rows = await _client
        .from('messages')
        .select('*, profiles($profileCols), clubs!messages_as_club_fkey(name, avatar_url), vendors!messages_as_vendor_fkey(name, logo_url)')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Message.fromMap).toList().reversed.toList();
  }

  /// One message with its sender, for a reply whose original is older than
  /// the loaded page. Null when it was deleted (or isn't visible to me).
  Future<Message?> message(String id) async {
    final row = await _client
        .from('messages')
        .select('*, profiles($profileCols), clubs!messages_as_club_fkey(name, avatar_url), vendors!messages_as_vendor_fkey(name, logo_url)')
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Message.fromMap(row);
  }

  Future<void> send({
    required String conversationId,
    required String me,
    required String body,
    String? postId,
    String? storyId,
    String? imageUrl,
    String? sticker,
    String? eventId,
    String? placeId,
    String? carId,
    String? audioUrl,
    int? audioMs,
    String? videoUrl,
    String? asClub,
    String? asVendor,
    String? replyTo,
    List<int>? audioWave,
    String? videoPosterUrl,
    int? videoMs,
  }) =>
      _client.from('messages').insert({
        'as_club': ?asClub,
        'as_vendor': ?asVendor,
        'audio_url': ?audioUrl,
        'audio_ms': ?audioMs,
        'video_url': ?videoUrl,
        'conversation_id': conversationId,
        'sender_id': me,
        'body': body.trim(),
        'post_id': ?postId,
        'story_id': ?storyId,
        'image_url': ?imageUrl,
        'sticker': ?sticker,
        'event_id': ?eventId,
        'place_id': ?placeId,
        'car_id': ?carId,
        'reply_to': ?replyTo,
        'audio_wave': ?audioWave,
        'video_poster_url': ?videoPosterUrl,
        'video_ms': ?videoMs,
      });

  Future<String> uploadMedia({required String me, required Uint8List bytes, required String ext, required String contentType}) async {
    final path = '$me/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('chat-media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, cacheControl: kImmutableCacheControl));
    return _client.storage.from('chat-media').getPublicUrl(path);
  }

  Future<String> uploadPhoto({required String me, required Uint8List bytes}) async {
    final path = '$me/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('chat-photos').uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: kImmutableCacheControl));
    return _client.storage.from('chat-photos').getPublicUrl(path);
  }

  /// A video and its poster frame side by side in chat-media:
  /// `<me>/<ts>.mp4` and `<me>/<ts>.jpg`. The poster is best effort: if it
  /// fails, the video still goes and the bubble loads its first frame instead.
  Future<({String url, String? posterUrl})> uploadVideo({required String me, required Uint8List bytes, Uint8List? poster}) async {
    final stem = '$me/${DateTime.now().millisecondsSinceEpoch}';
    final bucket = _client.storage.from('chat-media');
    Future<String?> posterUp() async {
      if (poster == null) return null;
      try {
        await bucket.uploadBinary('$stem.jpg', poster, fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: kImmutableCacheControl));
        return bucket.getPublicUrl('$stem.jpg');
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait<String?>([
      bucket.uploadBinary('$stem.mp4', bytes, fileOptions: const FileOptions(contentType: 'video/mp4', cacheControl: kImmutableCacheControl)).then((_) => bucket.getPublicUrl('$stem.mp4')),
      posterUp(),
    ]);
    return (url: results[0]!, posterUrl: results[1]);
  }

  /// New messages as they arrive. [onSubscribed] runs each time the channel
  /// (re)joins: after a dropped connection anything sent meanwhile was missed.
  RealtimeChannel subscribe(String conversationId, void Function(Message) onMessage, {void Function()? onSubscribed}) {
    return _client
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: conversationId),
          callback: (payload) => onMessage(Message.fromMap(payload.newRecord)),
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) onSubscribed?.call();
        });
  }

  Future<int> totalUnread(String me) async {
    final all = await inbox(me);
    // Chats with a deleted account aren't shown, so they don't count either.
    return all.where((c) => !c.otherGone).fold<int>(0, (sum, c) => sum + c.unread);
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) => ChatRepository(ref.watch(supabaseProvider)));


/// Whose inbox we are looking at.
class InboxScope {
  const InboxScope.personal({this.managedClubs = const {}, this.myVendorId})
      : clubId = null,
        vendorId = null,
        everything = false;
  const InboxScope.club(this.clubId)
      : vendorId = null,
        managedClubs = const {},
        myVendorId = null,
        everything = false;
  const InboxScope.vendor(this.vendorId)
      : clubId = null,
        managedClubs = const {},
        myVendorId = null,
        everything = false;
  /// Same ownership knowledge as [base], but no filtering (single lookups).
  InboxScope.all(InboxScope base)
      : clubId = base.clubId,
        vendorId = base.vendorId,
        managedClubs = base.managedClubs,
        myVendorId = base.myVendorId,
        everything = true;

  final String? clubId;
  final String? vendorId;
  final Set<String> managedClubs;
  final String? myVendorId;
  final bool everything;

  bool owns(String? convClub, String? convVendor) => (clubId != null && clubId == convClub) || (vendorId != null && vendorId == convVendor);

  bool includes(Conversation c) {
    if (everything) return true;
    // A club's members chat is in each member's own Chats, not the club account's.
    if (c.isClubChat) return clubId == null && vendorId == null;
    if (clubId != null) return c.clubId == clubId;
    if (vendorId != null) return c.vendorId == vendorId;
    // personal: hide chats that belong to an account I manage
    if (c.clubId != null && managedClubs.contains(c.clubId)) return false;
    if (c.vendorId != null && c.vendorId == myVendorId) return false;
    return true;
  }
}
