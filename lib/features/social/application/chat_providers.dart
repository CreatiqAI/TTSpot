import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../data/chat_repository.dart';
import '../domain/chat.dart';

final inboxProvider = FutureProvider<List<Conversation>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  return ref.watch(chatRepositoryProvider).inbox(me);
});

final conversationProvider = FutureProvider.family<Conversation?, String>((ref, id) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return null;
  return ref.watch(chatRepositoryProvider).conversation(id, me);
});

/// Live message list: initial fetch, then realtime inserts appended.
final sharedInChatProvider = FutureProvider.family<List<Message>, String>((ref, id) => ref.watch(chatRepositoryProvider).shared(id));

final messagesProvider = StreamProvider.family<List<Message>, String>((ref, conversationId) {
  final repo = ref.watch(chatRepositoryProvider);
  final controller = StreamController<List<Message>>();
  var list = <Message>[];

  repo.messages(conversationId).then((initial) {
    list = initial;
    if (!controller.isClosed) controller.add(List.unmodifiable(list));
  }).catchError((e, st) {
    if (!controller.isClosed) controller.addError(e, st);
  });

  final channel = repo.subscribe(conversationId, (m) {
    if (list.any((x) => x.id == m.id)) return;
    list = [...list, m];
    if (!controller.isClosed) controller.add(List.unmodifiable(list));
    ref.invalidate(inboxProvider);
  });

  ref.onDispose(() {
    channel.unsubscribe();
    controller.close();
  });
  return controller.stream;
});

final unreadMessagesProvider = FutureProvider<int>((ref) async {
  final inbox = await ref.watch(inboxProvider.future);
  return inbox.fold<int>(0, (s, c) => s + c.unread);
});

class ChatActions {
  ChatActions(this._ref);
  final Ref _ref;

  String get _me {
    final id = _ref.read(currentUserIdProvider);
    if (id == null) throw const AppException('You\'re signed out. Sign in again.');
    return id;
  }

  Future<String> openDm(String otherUserId) async {
    final id = await _ref.read(chatRepositoryProvider).openDm(otherUserId);
    _ref.invalidate(inboxProvider);
    return id;
  }

  Future<String> openMeetChat(String eventId) async {
    final id = await _ref.read(chatRepositoryProvider).openMeetChat(eventId);
    _ref.invalidate(inboxProvider);
    return id;
  }

  Future<void> send(String conversationId, String body) async {
    if (body.trim().isEmpty) return;
    await _ref.read(chatRepositoryProvider).send(conversationId: conversationId, me: _me, body: body);
  }

  /// Drop a post or moment into a chat, with an optional note.
  Future<void> share(String conversationId, {String? postId, String? storyId, String note = ''}) async {
    final body = note.trim().isEmpty ? (postId != null ? 'Shared a post' : 'Shared a moment') : note;
    await _ref.read(chatRepositoryProvider).send(conversationId: conversationId, me: _me, body: body, postId: postId, storyId: storyId);
    _ref.invalidate(inboxProvider);
  }

  Future<void> setPin(String conversationId, bool pin) async {
    await _ref.read(chatRepositoryProvider).setPin(conversationId, pin);
    _ref.invalidate(inboxProvider);
    _ref.invalidate(conversationProvider(conversationId));
  }

  Future<void> hide(String conversationId) async {
    await _ref.read(chatRepositoryProvider).hide(conversationId);
    _ref.invalidate(inboxProvider);
  }

  Future<void> markRead(String conversationId) async {
    await _ref.read(chatRepositoryProvider).markRead(conversationId);
    _ref.invalidate(inboxProvider);
  }
}

final chatActionsProvider = Provider<ChatActions>((ref) => ChatActions(ref));
