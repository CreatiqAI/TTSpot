import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';

/// A push that arrived while the app is open, shown as our own banner (the
/// phone's banner is switched off in the foreground): who, a one-line
/// preview, where a tap goes. Built from the push's data payload, which the
/// `push` Edge Function fills for every message and notification.
@immutable
class InAppNotice {
  const InAppNotice({
    required this.kind,
    required this.title,
    required this.body,
    this.id,
    this.avatarUrl,
    this.seed,
    this.route,
    this.conversationId,
    this.group = false,
  });

  /// Message / notification id, so a push delivered twice shows once.
  final String? id;

  /// `chat` for messages, else the notification type (post_like, friend_request…).
  final String kind;
  final String title;
  final String body;
  final String? avatarUrl;

  /// The sender's user id: picks their TiTi default avatar when there's no photo.
  final String? seed;
  final String? route;
  final String? conversationId;

  /// A meet group chat (title = the meet, body = "Name: message").
  final bool group;

  bool get isChat => kind == 'chat';

  /// From RemoteMessage.data, with the notification block's title / body as
  /// a fallback (iOS and social pushes carry both). Null when there's
  /// nothing to show.
  static InAppNotice? fromPush(Map<String, dynamic> data, {String? title, String? body, String? messageId}) {
    String? s(String k) {
      final v = data[k];
      final t = v is String ? v.trim() : null;
      return t == null || t.isEmpty ? null : t;
    }

    final t = s('title') ?? title?.trim();
    final b = s('body') ?? body?.trim() ?? '';
    if (t == null || t.isEmpty) return null;
    final route = s('route');
    final conv = s('conversation_id') ?? (route != null && route.startsWith('/chat/') ? route.substring(6).split('/').first : null);
    return InAppNotice(
      id: s('msg_id') ?? messageId,
      kind: s('kind') ?? (conv != null ? 'chat' : 'notice'),
      title: t,
      body: b,
      avatarUrl: s('avatar'),
      seed: s('sender_id'),
      route: route != null && route.startsWith('/') ? route : null,
      conversationId: conv,
      group: s('group') == '1',
    );
  }

  /// Small badge on the avatar saying what kind of notice it is. None for a
  /// one-to-one message (like WhatsApp: the face says it all).
  IconData? get badge => switch (kind) {
        'chat' => group ? AppIcons.usersThree : null,
        'friend_request' || 'follow' => AppIcons.userPlus,
        'friend_accepted' => AppIcons.userCheck,
        'post_like' || 'comment_like' => AppIcons.heartFill,
        'post_comment' || 'event_comment' => AppIcons.chatCircleFill,
        'comment_reply' => AppIcons.arrowBendUpLeft,
        'mention' => AppIcons.chatText,
        'event_join' || 'event_reminder' || 'club_event' || 'partner_event' || 'club_meet' => AppIcons.calendarCheck,
        'event_cancelled' => AppIcons.calendarBlank,
        'checkin' || 'meet_start' => AppIcons.flagCheckered,
        'announcement' => AppIcons.megaphone,
        'lucky_draw' => AppIcons.gift,
        'tt_now' => AppIcons.lightningFill,
        'friend_tt' => AppIcons.coffee,
        'friend_post' || 'club_post' => AppIcons.image,
        'club_member' => AppIcons.usersThree,
        'garage' => AppIcons.garage,
        'club_invite' || 'club_join' || 'club_request' || 'club_official' => AppIcons.usersThree,
        'points' || 'referral' => AppIcons.coins,
        'badge' => AppIcons.medal,
        'voucher' => AppIcons.ticket,
        'cards' => AppIcons.cards,
        'portrait' => AppIcons.sparkle,
        'spotted_claim' => AppIcons.car,
        _ => AppIcons.bellFill,
      };
}

/// Whether to show [n] now. Not when I'm already looking at that chat (or at
/// the page it opens), and never for a chat I muted.
bool shouldShowInAppNotice(
  InAppNotice n, {
  required String? viewingChatId,
  required Set<String> mutedChatIds,
  String? currentPath,
}) {
  final conv = n.conversationId;
  if (conv != null) {
    if (conv == viewingChatId) return false;
    if (mutedChatIds.contains(conv)) return false;
  }
  if (n.route != null && currentPath != null && n.route == currentPath) return false;
  return true;
}

/// The chat on screen: ChatScreen enters on open and leaves on close. The
/// top one counts only while the router shows it (a profile pushed on top of
/// a chat isn't "viewing" it).
abstract final class OpenChats {
  static final _open = <String>[];

  static void enter(String conversationId) {
    _open.add(conversationId);
    clearSystemChatNotification(conversationId);
  }

  static void leave(String conversationId) {
    final i = _open.lastIndexOf(conversationId);
    if (i >= 0) _open.removeAt(i);
  }

  /// The chat being looked at, given the router's current path.
  static String? viewing(String? currentPath) {
    if (_open.isEmpty) return null;
    final top = _open.last;
    if (currentPath == null) return top;
    return currentPath == '/chat/$top' ? top : null;
  }

  @visibleForTesting
  static void reset() => _open.clear();
}

const _chatNotifications = MethodChannel('my.ttspot.app/chat_notifications');

/// Takes a chat's Android notification out of the shade once it's open.
void clearSystemChatNotification(String conversationId) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  _chatNotifications.invokeMethod<void>('cancel', {'conversationId': conversationId}).catchError((_) {});
}

/// What the banner shows; [InAppNoticeHost] listens.
abstract final class InAppNotices {
  static final current = ValueNotifier<({InAppNotice notice, VoidCallback? onTap})?>(null);
  static String? _lastId;

  static void show(InAppNotice n, {VoidCallback? onTap}) {
    if (n.id != null && n.id == _lastId && current.value != null) return;
    _lastId = n.id;
    current.value = (notice: n, onTap: onTap);
  }

  static void hide() => current.value = null;
}

/// WhatsApp-style banner: a dark rounded card that slides down from under
/// the status bar with the sender's avatar, their name in bold, a one-line
/// preview and a grab handle. Hides after 4 s; swipe it up to dismiss, tap
/// to open. Sits over the whole app (MaterialApp.builder).
class InAppNoticeHost extends StatefulWidget {
  const InAppNoticeHost({super.key});

  static const visibleFor = Duration(seconds: 4);

  @override
  State<InAppNoticeHost> createState() => _InAppNoticeHostState();
}

class _InAppNoticeHostState extends State<InAppNoticeHost> with TickerProviderStateMixin {
  late final _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 320), reverseDuration: const Duration(milliseconds: 220));
  late final _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  late final _curve = CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
  ({InAppNotice notice, VoidCallback? onTap})? _shown;
  Timer? _timer;
  double _drag = 0;
  double _settleFrom = 0;

  @override
  void initState() {
    super.initState();
    InAppNotices.current.addListener(_changed);
    _settle.addListener(() => setState(() => _drag = _settleFrom * (1 - Curves.easeOut.transform(_settle.value))));
  }

  @override
  void dispose() {
    InAppNotices.current.removeListener(_changed);
    _timer?.cancel();
    _slide.dispose();
    _settle.dispose();
    super.dispose();
  }

  void _changed() {
    final next = InAppNotices.current.value;
    if (!mounted) return;
    if (next == null) {
      _timer?.cancel();
      _slide.reverse().whenComplete(() {
        if (mounted && InAppNotices.current.value == null) setState(() => _shown = null);
      });
      return;
    }
    setState(() {
      _shown = next;
      _drag = 0;
    });
    _settle.stop();
    _slide.forward();
    HapticFeedback.lightImpact();
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(InAppNoticeHost.visibleFor, InAppNotices.hide);
  }

  void _tap() {
    final onTap = _shown?.onTap;
    InAppNotices.hide();
    onTap?.call();
  }

  void _dragUpdate(DragUpdateDetails d) {
    _timer?.cancel();
    _settle.stop();
    // Up follows the finger; down only gives a little.
    setState(() => _drag = (_drag + (d.delta.dy < 0 ? d.delta.dy : d.delta.dy * 0.25)).clamp(-200.0, 12.0));
  }

  void _dragEnd(DragEndDetails d) {
    if (_drag < -28 || (d.primaryVelocity ?? 0) < -300) {
      InAppNotices.hide();
      return;
    }
    _settleFrom = _drag;
    _settle.forward(from: 0);
    _restartTimer();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    final top = MediaQuery.paddingOf(context).top + 6;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero).animate(_curve),
        child: Transform.translate(
          offset: Offset(0, _drag),
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, top, 8, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _tap,
                  onVerticalDragUpdate: _dragUpdate,
                  onVerticalDragEnd: _dragEnd,
                  child: InAppNoticeCard(notice: shown.notice),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The banner card itself (also used by tests).
class InAppNoticeCard extends StatelessWidget {
  const InAppNoticeCard({super.key, required this.notice});
  final InAppNotice notice;

  @override
  Widget build(BuildContext context) {
    final n = notice;
    // Dark in both themes, like WhatsApp; in dark mode a shade lighter than
    // the page with a hairline so it doesn't sink into it.
    final bg = AppColors.dark ? AppColors.surfaceGray : AppColors.ink;
    final badge = n.badge;
    return Semantics(
      container: true,
      liveRegion: true,
      button: n.route != null,
      label: '${n.title}. ${n.body}',
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 14, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: AppColors.dark ? Border.all(color: AppColors.border) : null,
            boxShadow: const [BoxShadow(color: Color(0x47000000), blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        UserAvatar(url: n.avatarUrl, name: n.title, seed: n.seed, size: 44),
                        if (badge != null)
                          Positioned(
                            right: -3,
                            bottom: -3,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: bg, width: 2)),
                              child: Icon(badge, size: 10, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.25)),
                        if (n.body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(n.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 13.5, height: 1.25)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0x59FFFFFF), borderRadius: BorderRadius.circular(2))),
            ],
          ),
        ),
      ),
    );
  }
}
