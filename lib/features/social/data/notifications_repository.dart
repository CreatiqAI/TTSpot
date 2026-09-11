import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/notification.dart';
import 'social_repository.dart';

class NotificationsRepository {
  NotificationsRepository(this._client);
  final SupabaseClient _client;

  Future<List<AppNotification>> fetch(String me, {int limit = 100}) async {
    final rows = await _client
        .from('notifications')
        .select('*, actor:profiles!notifications_actor_id_fkey($profileCols), posts(photo_urls), events(title), clubs(name)')
        .eq('user_id', me)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AppNotification.fromMap).toList();
  }

  Future<int> unreadCount(String me) async {
    final rows = await _client.from('notifications').select('id').eq('user_id', me).isFilter('read_at', null);
    return rows.length;
  }

  Future<void> markAllRead(String me) => _client
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('user_id', me)
      .isFilter('read_at', null);

  /// Fires whenever a new notification row lands for [me].
  RealtimeChannel subscribe(String me, void Function() onNew) {
    return _client
        .channel('notifications:$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: me),
          callback: (_) => onNew(),
        )
        .subscribe();
  }

  Future<List<AppBadge>> allBadges() async {
    final rows = await _client.from('badges').select().order('sort');
    return rows.map(AppBadge.fromMap).toList();
  }

  Future<List<EarnedBadge>> earnedBadges(String userId) async {
    final rows = await _client.from('user_badges').select('awarded_at, badges(*)').eq('user_id', userId).order('awarded_at', ascending: false);
    return rows
        .where((r) => r['badges'] != null)
        .map((r) => EarnedBadge(badge: AppBadge.fromMap(r['badges'] as Map<String, dynamic>), awardedAt: DateTime.parse(r['awarded_at'] as String).toLocal()))
        .toList();
  }

  Future<int> ttStreak(String userId) async {
    final v = await _client.rpc('tt_streak_weeks', params: {'p_user': userId});
    return (v as num?)?.toInt() ?? 0;
  }
}

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) => NotificationsRepository(ref.watch(supabaseProvider)));
