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

  Future<void> markRead(String conversationId) => _client.rpc('mark_conversation_read', params: {'p_conversation': conversationId});

  Future<List<Conversation>> inbox(String me) async {
    final mine = await _client.from('conversation_members').select('conversation_id, last_read_at').eq('user_id', me);
    if (mine.isEmpty) return const [];
    final ids = mine.map((r) => r['conversation_id'] as String).toList();
    final lastRead = {for (final r in mine) r['conversation_id'] as String: DateTime.parse(r['last_read_at'] as String)};

    final results = await Future.wait<dynamic>([
      _client
          .from('conversations')
          .select('id, kind, event_id, events(title, cover_url), conversation_members(user_id, profiles($profileCols))')
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
      final other = members.where((p) => p.id != me).firstOrNull;
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
      );
    }).toList();

    convs.sort((a, b) {
      final ta = a.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return convs;
  }

  Future<Conversation?> conversation(String id, String me) async {
    final all = await inbox(me);
    return all.where((c) => c.id == id).firstOrNull;
  }

  Future<List<Message>> messages(String conversationId, {int limit = 200}) async {
    final rows = await _client
        .from('messages')
        .select('*, profiles($profileCols)')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(limit);
    return rows.map(Message.fromMap).toList();
  }

  Future<void> send({required String conversationId, required String me, required String body}) =>
      _client.from('messages').insert({'conversation_id': conversationId, 'sender_id': me, 'body': body.trim()});

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
