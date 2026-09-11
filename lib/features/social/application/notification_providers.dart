import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../data/notifications_repository.dart';
import '../domain/notification.dart';

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];
  return ref.watch(notificationsRepositoryProvider).fetch(me);
});

/// Unread count, kept fresh by a realtime subscription on the notifications table.
final unreadNotificationsProvider = StreamProvider<int>((ref) {
  final me = ref.watch(currentUserIdProvider);
  final repo = ref.watch(notificationsRepositoryProvider);
  final controller = StreamController<int>();
  if (me == null) {
    controller.add(0);
    return controller.stream;
  }
  Future<void> refresh() async {
    try {
      final n = await repo.unreadCount(me);
      if (!controller.isClosed) controller.add(n);
    } catch (_) {}
  }

  refresh();
  final channel = repo.subscribe(me, () {
    refresh();
    ref.invalidate(notificationsProvider);
  });
  ref.onDispose(() {
    channel.unsubscribe();
    controller.close();
  });
  return controller.stream;
});

final allBadgesProvider = FutureProvider<List<AppBadge>>((ref) => ref.watch(notificationsRepositoryProvider).allBadges());
final earnedBadgesProvider = FutureProvider.family<List<EarnedBadge>, String>((ref, userId) => ref.watch(notificationsRepositoryProvider).earnedBadges(userId));
final ttStreakProvider = FutureProvider.family<int, String>((ref, userId) => ref.watch(notificationsRepositoryProvider).ttStreak(userId));

class NotificationActions {
  NotificationActions(this._ref);
  final Ref _ref;

  Future<void> markAllRead() async {
    final me = _ref.read(currentUserIdProvider);
    if (me == null) return;
    await _ref.read(notificationsRepositoryProvider).markAllRead(me);
    _ref.invalidate(notificationsProvider);
    _ref.invalidate(unreadNotificationsProvider);
  }
}

final notificationActionsProvider = Provider<NotificationActions>((ref) => NotificationActions(ref));
