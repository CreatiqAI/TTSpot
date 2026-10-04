import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/media.dart';
import '../../../core/supabase/supabase_client.dart';
import '../domain/group_chat.dart';
import 'social_repository.dart';

/// Friends' group chats and club members chats. Every membership change goes
/// through a security-definer RPC (20261005000100_group_chats.sql) that
/// checks friends, blocks, admins and the 100-member cap.
class GroupChatRepository {
  GroupChatRepository(this._client);
  final SupabaseClient _client;

  /// Start a group with 2+ friends; returns the chat id.
  Future<String> create({required List<String> memberIds, String? title, String? photoUrl}) async =>
      await _client.rpc('create_group_chat', params: {'p_members': memberIds, 'p_title': title, 'p_photo_url': photoUrl}) as String;

  /// Adds my friends; returns how many were added.
  Future<int> addMembers(String conversationId, List<String> userIds) async =>
      ((await _client.rpc('add_group_members', params: {'p_conversation': conversationId, 'p_members': userIds})) as num?)?.toInt() ?? 0;

  Future<void> removeMember(String conversationId, String userId) => _client.rpc('remove_group_member', params: {'p_conversation': conversationId, 'p_user': userId});
  Future<void> setAdmin(String conversationId, String userId, bool admin) => _client.rpc('set_group_admin', params: {'p_conversation': conversationId, 'p_user': userId, 'p_admin': admin});
  /// Null or blank: no name, the app lists the members.
  Future<void> rename(String conversationId, String? title) => _client.rpc('rename_group_chat', params: {'p_conversation': conversationId, 'p_title': title});
  Future<void> setPhoto(String conversationId, String? url) => _client.rpc('set_group_chat_photo', params: {'p_conversation': conversationId, 'p_photo_url': url});
  Future<void> leave(String conversationId) => _client.rpc('leave_group_chat', params: {'p_conversation': conversationId});

  /// Delete for everyone: my own message, or any message where I moderate.
  Future<void> deleteMessage(String messageId) => _client.rpc('delete_chat_message', params: {'p_message': messageId});

  /// My club's members chat (members only).
  Future<String> openClubChat(String clubId) async => await _client.rpc('open_club_chat', params: {'p_club': clubId}) as String;

  /// Everyone in the chat, in the order they joined.
  Future<List<GroupMember>> members(String conversationId) async {
    final rows = await _client
        .from('conversation_members')
        .select('user_id, is_admin, created_at, profiles($profileCols)')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(1000);
    return [for (final r in rows) if (r['profiles'] != null) GroupMember.fromMap(r)];
  }

  /// A group picture, in chat-photos like chat photos: `<me>/group-<ts>.jpg`.
  Future<String> uploadPhoto({required String me, required Uint8List bytes}) async {
    final path = '$me/group-${DateTime.now().millisecondsSinceEpoch}.jpg';
    final bucket = _client.storage.from('chat-photos');
    await bucket.uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: kImmutableCacheControl));
    return bucket.getPublicUrl(path);
  }
}

final groupChatRepositoryProvider = Provider<GroupChatRepository>((ref) => GroupChatRepository(ref.watch(supabaseProvider)));

/// Group name rules shared by the new-group form and rename.
String? cleanGroupName(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  return t.length > kGroupNameMax ? t.substring(0, kGroupNameMax) : t;
}
