import '../../auth/domain/profile.dart';

class Message {
  const Message({required this.id, required this.conversationId, required this.senderId, required this.body, required this.createdAt, this.sender, this.postId, this.storyId});
  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final Profile? sender;
  /// A shared post / moment, rendered as a preview card above the text.
  final String? postId;
  final String? storyId;

  factory Message.fromMap(Map<String, dynamic> m) => Message(
        id: m['id'] as String,
        conversationId: m['conversation_id'] as String,
        senderId: m['sender_id'] as String,
        body: m['body'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        sender: m['profiles'] == null ? null : Profile.fromMap(m['profiles'] as Map<String, dynamic>),
        postId: m['post_id'] as String?,
        storyId: m['story_id'] as String?,
      );
}

/// Inbox row.
class Conversation {
  const Conversation({
    required this.id,
    required this.kind,
    this.eventId,
    this.eventTitle,
    this.eventCover,
    this.other,
    required this.members,
    this.lastMessage,
    required this.unread,
    this.pinnedAt,
    this.hiddenAt,
  });

  final String id;
  final String kind; // dm | meet
  final String? eventId;
  final String? eventTitle;
  final String? eventCover;
  final Profile? other; // the other person, for DMs
  final List<Profile> members;
  final Message? lastMessage;
  final int unread;
  final DateTime? pinnedAt;
  final DateTime? hiddenAt;

  bool get pinned => pinnedAt != null;

  bool get isMeet => kind == 'meet';
  String get title => isMeet ? (eventTitle ?? 'Meet chat') : (other?.displayName ?? other?.username ?? 'Chat');
}
