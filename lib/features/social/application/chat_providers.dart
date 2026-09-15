import 'dart:async';

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../accounts/application/active_account.dart';
import '../../vendors/application/vendors_providers.dart';
import '../data/chat_repository.dart';
import '../domain/club.dart';
import '../domain/chat.dart';

/// The inbox follows the active account: personal, a club, or a partner.
final inboxScopeProvider = Provider<InboxScope>((ref) {
  final account = ref.watch(activeAccountProvider);
  final managed = {for (final c in ref.watch(managedClubsProvider).value ?? const <Club>[]) c.id};
  final myVendor = ref.watch(myVendorProvider).value?.id;
  return switch (account) {
    ClubAccount(:final club) => InboxScope.club(club.id),
    PartnerAccount(:final vendor) => InboxScope.vendor(vendor.id),
    _ => InboxScope.personal(managedClubs: managed, myVendorId: myVendor),
  };
});

final inboxProvider = FutureProvider<List<Conversation>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  return ref.watch(chatRepositoryProvider).inbox(me, scope: ref.watch(inboxScopeProvider));
});

final conversationProvider = FutureProvider.family<Conversation?, String>((ref, id) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return null;
  return ref.watch(chatRepositoryProvider).conversation(id, me, scope: ref.watch(inboxScopeProvider));
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
  return inbox.where((c) => !c.muted).fold<int>(0, (s, c) => s + c.unread);
});

class ChatActions {
  ChatActions(this._ref);
  final Ref _ref;

  String get _me {
    final id = _ref.read(currentUserIdProvider);
    if (id == null) throw const AppException('You\'re signed out. Sign in again.');
    return id;
  }

  /// When the active account is the club / partner this chat belongs to,
  /// messages go out as that account.
  ({String? asClub, String? asVendor}) _actor(String conversationId) {
    final account = _ref.read(activeAccountProvider);
    final conv = _ref.read(conversationProvider(conversationId)).value;
    if (conv == null) return (asClub: null, asVendor: null);
    return switch (account) {
      ClubAccount(:final club) when conv.clubId == club.id => (asClub: club.id, asVendor: null),
      PartnerAccount(:final vendor) when conv.vendorId == vendor.id => (asClub: null, asVendor: vendor.id),
      _ => (asClub: null, asVendor: null),
    };
  }

  Future<String> openClubDm(String clubId) async {
    final id = await _ref.read(chatRepositoryProvider).openClubDm(clubId);
    _ref.invalidate(inboxProvider);
    return id;
  }

  Future<String> openVendorDm(String vendorId) async {
    final id = await _ref.read(chatRepositoryProvider).openVendorDm(vendorId);
    _ref.invalidate(inboxProvider);
    return id;
  }

  Future<void> setMute(String conversationId, bool muted) async {
    await _ref.read(chatRepositoryProvider).setMute(conversationId, muted);
    _ref.invalidate(inboxProvider);
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
    await _ref.read(chatRepositoryProvider).send(asClub: _actor(conversationId).asClub, asVendor: _actor(conversationId).asVendor, conversationId: conversationId, me: _me, body: body);
  }

  /// Drop a post or moment into a chat, with an optional note.
  Future<void> share(String conversationId, {String? postId, String? storyId, String note = ''}) async {
    final body = note.trim().isEmpty ? (postId != null ? 'Shared a post' : 'Shared a moment') : note;
    await _ref.read(chatRepositoryProvider).send(asClub: _actor(conversationId).asClub, asVendor: _actor(conversationId).asVendor, conversationId: conversationId, me: _me, body: body, postId: postId, storyId: storyId);
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

  Future<void> sendPhoto(String conversationId, XFile file) async {
    final repo = _ref.read(chatRepositoryProvider);
    final url = await repo.uploadPhoto(me: _me, bytes: await file.readAsBytes());
    await repo.send(asClub: _actor(conversationId).asClub, asVendor: _actor(conversationId).asVendor, conversationId: conversationId, me: _me, body: 'Sent a photo', imageUrl: url);
    _ref.invalidate(inboxProvider);
  }

  Future<void> sendVoice(String conversationId, Uint8List bytes, int ms) async {
    final repo = _ref.read(chatRepositoryProvider);
    final url = await repo.uploadMedia(me: _me, bytes: bytes, ext: 'm4a', contentType: 'audio/mp4');
    await repo.send(asClub: _actor(conversationId).asClub, asVendor: _actor(conversationId).asVendor, conversationId: conversationId, me: _me, body: 'Voice note', audioUrl: url, audioMs: ms);
    _ref.invalidate(inboxProvider);
  }

  Future<void> sendVideo(String conversationId, XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > 50 * 1024 * 1024) throw const AppException('Video is too big. Keep it under 50 MB.');
    final repo = _ref.read(chatRepositoryProvider);
    final url = await repo.uploadMedia(me: _me, bytes: bytes, ext: 'mp4', contentType: 'video/mp4');
    await repo.send(asClub: _actor(conversationId).asClub, asVendor: _actor(conversationId).asVendor, conversationId: conversationId, me: _me, body: 'Sent a video', videoUrl: url);
    _ref.invalidate(inboxProvider);
  }

  Future<void> sendSticker(String conversationId, String key) async {
    await _ref.read(chatRepositoryProvider).send(asClub: _actor(conversationId).asClub, asVendor: _actor(conversationId).asVendor, conversationId: conversationId, me: _me, body: 'Sent a sticker', sticker: key);
    _ref.invalidate(inboxProvider);
  }

  Future<void> attach(String conversationId, {String? eventId, String? placeId, String? carId}) async {
    final body = eventId != null ? 'Shared a meet' : (placeId != null ? 'Shared a spot' : 'Shared a car');
    await _ref.read(chatRepositoryProvider).send(asClub: _actor(conversationId).asClub, asVendor: _actor(conversationId).asVendor, conversationId: conversationId, me: _me, body: body, eventId: eventId, placeId: placeId, carId: carId);
    _ref.invalidate(inboxProvider);
  }

  Future<void> markRead(String conversationId) async {
    await _ref.read(chatRepositoryProvider).markRead(conversationId);
    _ref.invalidate(inboxProvider);
  }
}

final chatActionsProvider = Provider<ChatActions>((ref) => ChatActions(ref));
