import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../accounts/application/active_account.dart';
import '../data/group_chat_repository.dart';
import '../domain/club.dart';
import '../domain/group_chat.dart';
import 'chat_providers.dart';

/// Everyone in a group or club chat (the inbox only loads a club chat's size).
final groupMembersProvider = FutureProvider.family<List<GroupMember>, String>((ref, conversationId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(groupChatRepositoryProvider).members(conversationId);
});

/// Can I delete anyone's message in this chat: a club officer (president,
/// VP, secretary) in the club's chat, an admin in a friends' group.
final canModerateChatProvider = Provider.family<bool, String>((ref, conversationId) {
  final conv = ref.watch(conversationProvider(conversationId)).value;
  if (conv == null) return false;
  if (conv.isFriendGroup) return conv.amGroupAdmin;
  final clubId = conv.clubId;
  if (!conv.isClubChat || clubId == null) return false;
  final managed = ref.watch(managedClubsProvider).value ?? const <Club>[];
  return managed.any((c) => c.id == clubId);
});

class GroupChatActions {
  GroupChatActions(this._ref);
  final Ref _ref;

  GroupChatRepository get _repo => _ref.read(groupChatRepositoryProvider);

  String get _me {
    final id = _ref.read(currentUserIdProvider);
    if (id == null) throw const AppException("You're signed out. Sign in again.");
    return id;
  }

  void _refresh(String conversationId) {
    _ref.invalidate(inboxProvider);
    _ref.invalidate(conversationProvider(conversationId));
    _ref.invalidate(groupMembersProvider(conversationId));
  }

  Future<String> _upload(XFile photo) async => _repo.uploadPhoto(me: _me, bytes: await photo.readAsBytes());

  /// Start a group; returns its chat id. The photo goes up first.
  Future<String> create({required List<String> memberIds, String? name, XFile? photo}) async {
    if (memberIds.length < kGroupMinFriends) throw const AppException('Pick at least 2 friends for a group.');
    final url = photo == null ? null : await _upload(photo);
    final id = await _repo.create(memberIds: memberIds, title: cleanGroupName(name), photoUrl: url);
    _ref.invalidate(inboxProvider);
    return id;
  }

  Future<int> addMembers(String conversationId, List<String> userIds) async {
    final n = await _repo.addMembers(conversationId, userIds);
    _refresh(conversationId);
    return n;
  }

  Future<void> removeMember(String conversationId, String userId) async {
    await _repo.removeMember(conversationId, userId);
    _refresh(conversationId);
  }

  Future<void> setAdmin(String conversationId, String userId, bool admin) async {
    await _repo.setAdmin(conversationId, userId, admin);
    _refresh(conversationId);
  }

  Future<void> rename(String conversationId, String? name) async {
    await _repo.rename(conversationId, cleanGroupName(name));
    _refresh(conversationId);
  }

  /// A new picture, or null to take it off.
  Future<void> setPhoto(String conversationId, XFile? photo) async {
    final url = photo == null ? null : await _upload(photo);
    await _repo.setPhoto(conversationId, url);
    _refresh(conversationId);
  }

  Future<void> leave(String conversationId) async {
    await _repo.leave(conversationId);
    _ref.invalidate(inboxProvider);
    _ref.invalidate(conversationProvider(conversationId));
  }

  /// Delete for everyone, then reload the chat.
  Future<void> deleteMessage(String conversationId, String messageId) async {
    await _repo.deleteMessage(messageId);
    _ref.invalidate(messagesProvider(conversationId));
    _ref.invalidate(sharedInChatProvider(conversationId));
    _ref.invalidate(chatMessageProvider(messageId));
    _ref.invalidate(inboxProvider);
  }

  Future<String> openClubChat(String clubId) async {
    final id = await _repo.openClubChat(clubId);
    _ref.invalidate(inboxProvider);
    return id;
  }
}

final groupChatActionsProvider = Provider<GroupChatActions>((ref) => GroupChatActions(ref));
