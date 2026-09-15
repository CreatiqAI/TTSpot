import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  Future<String> openVendorDm(String vendorId) async => await _client.rpc('get_or_create_vendor_dm', params: {'p_vendor': vendorId}) as String;

  Future<void> markRead(String conversationId) => _client.rpc('mark_conversation_read', params: {'p_conversation': conversationId});

  /// Which account's inbox: personal (everything not owned by a club /
  /// partner I manage), one club, or one partner.
  Future<List<Conversation>> inbox(String me, {InboxScope scope = const InboxScope.personal()}) async {
    final mine = await _client.from('conversation_members').select('conversation_id, last_read_at, pinned_at, hidden_at, muted_at').eq('user_id', me);
    if (mine.isEmpty) return const [];
    final ids = mine.map((r) => r['conversation_id'] as String).toList();
    final lastRead = {for (final r in mine) r['conversation_id'] as String: DateTime.parse(r['last_read_at'] as String)};
    final pinnedAt = {for (final r in mine) if (r['pinned_at'] != null) r['conversation_id'] as String: DateTime.parse(r['pinned_at'] as String)};
    final hiddenAt = {for (final r in mine) if (r['hidden_at'] != null) r['conversation_id'] as String: DateTime.parse(r['hidden_at'] as String)};
    final mutedAt = {for (final r in mine) if (r['muted_at'] != null) r['conversation_id'] as String: DateTime.parse(r['muted_at'] as String)};

    final results = await Future.wait<dynamic>([
      _client
          .from('conversations')
          .select('id, kind, event_id, club_id, vendor_id, events(title, cover_url), clubs!conversations_club_id_fkey(name, avatar_url), vendors!conversations_vendor_id_fkey(name, logo_url), conversation_members(user_id, profiles($profileCols))')
          .inFilter('id', ids),
      _client
          .from('messages')
          .select('*')
          .inFilter('conversation_id', ids)
          .order('created_at', ascending: false)
          .limit(400),
    ]);

    final messages = (results[1] as List).map((r) => Message.fromMap(r as Map<String, dynamic>)).toList();
    final lastByConv = <String, Message>{};
    final unreadByConv = <String, int>{};
    for (final m in messages) {
      lastByConv.putIfAbsent(m.conversationId, () => m);
      final seenAt = lastRead[m.conversationId];
      if (m.senderId != me && seenAt != null && m.createdAt.toUtc().isAfter(seenAt.toUtc())) {
        unreadByConv[m.conversationId] = (unreadByConv[m.conversationId] ?? 0) + 1;
      }
    }

    final convs = (results[0] as List).map((raw) {
      final r = raw as Map<String, dynamic>;
      final id = r['id'] as String;
      final event = r['events'] as Map<String, dynamic>?;
      final members = ((r['conversation_members'] as List?) ?? const [])
          .map((m) => (m as Map<String, dynamic>)['profiles'])
          .whereType<Map<String, dynamic>>()
          .map(Profile.fromMap)
          .toList();
      final clubId = r['club_id'] as String?;
      final vendorId = r['vendor_id'] as String?;
      final club = r['clubs'] as Map<String, dynamic>?;
      final vendor = r['vendors'] as Map<String, dynamic>?;
      final viewAsEntity = scope.owns(clubId, vendorId);
      // In an entity chat the club's managers are members too; "the other person" is whoever is not staff.
      final staff = viewAsEntity ? <String>{me} : (scope.managedClubs.contains(clubId) || (vendorId != null && vendorId == scope.myVendorId) ? {me} : <String>{});
      final other = members.where((p) => p.id != me && !staff.contains(p.id)).firstOrNull;
      return Conversation(
        id: id,
        kind: r['kind'] as String,
        eventId: r['event_id'] as String?,
        eventTitle: event?['title'] as String?,
        eventCover: event?['cover_url'] as String?,
        other: other,
        members: members,
        lastMessage: lastByConv[id],
        unread: unreadByConv[id] ?? 0,
        pinnedAt: pinnedAt[id],
        hiddenAt: hiddenAt[id],
        clubId: clubId,
        vendorId: vendorId,
        entityName: club?['name'] as String? ?? vendor?['name'] as String?,
        entityLogo: club?['avatar_url'] as String? ?? vendor?['logo_url'] as String?,
        mutedAt: mutedAt[id],
        viewAsEntity: viewAsEntity,
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

  Future<List<Message>> messages(String conversationId, {int limit = 200}) async {
    final rows = await _client
        .from('messages')
        .select('*, profiles($profileCols), clubs!messages_as_club_fkey(name, avatar_url), vendors!messages_as_vendor_fkey(name, logo_url)')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(limit);
    return rows.map(Message.fromMap).toList();
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
      });

  Future<String> uploadMedia({required String me, required Uint8List bytes, required String ext, required String contentType}) async {
    final path = '$me/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('chat-media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType));
    return _client.storage.from('chat-media').getPublicUrl(path);
  }

  Future<String> uploadPhoto({required String me, required Uint8List bytes}) async {
    final path = '$me/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('chat-photos').uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    return _client.storage.from('chat-photos').getPublicUrl(path);
  }

  RealtimeChannel subscribe(String conversationId, void Function(Message) onMessage) {
    return _client
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: conversationId),
          callback: (payload) => onMessage(Message.fromMap(payload.newRecord)),
        )
        .subscribe();
  }

  Future<int> totalUnread(String me) async {
    final all = await inbox(me);
    return all.fold<int>(0, (sum, c) => sum + c.unread);
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
    if (clubId != null) return c.clubId == clubId;
    if (vendorId != null) return c.vendorId == vendorId;
    // personal: hide chats that belong to an account I manage
    if (c.clubId != null && managedClubs.contains(c.clubId)) return false;
    if (c.vendorId != null && c.vendorId == myVendorId) return false;
    return true;
  }
}
