import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/domain/profile.dart';
import '../domain/friend.dart';

const _profileCols = 'id, username, display_name, bio, avatar_url, home_state, created_at';

/// Friendships (mutual), friend requests, and live pins.
class FriendsRepository {
  FriendsRepository(this._client);
  final SupabaseClient _client;

  // -------------------------------------------------------------- friends ---

  /// People you may know, best match first. Excludes friends, pending and blocked.
  Future<List<FriendSuggestion>> suggestions({int limit = 12}) async {
    final rows = await _client.rpc('suggest_friends', params: {'p_limit': limit}) as List;
    return rows
        .map((r) => FriendSuggestion(profile: Profile.fromMap(r as Map<String, dynamic>), reason: r['reason'] as String? ?? ''))
        .toList();
  }

  /// friend id -> colour key I gave them on the map.
  Future<Map<String, String>> friendTags(String me) async {
    final rows = await _client.from('friend_tags').select('friend_id, color').eq('owner_id', me);
    return {for (final r in rows) r['friend_id'] as String: r['color'] as String};
  }

  Future<void> setFriendTag(String me, String friendId, String? color) async {
    if (color == null) {
      await _client.from('friend_tags').delete().eq('owner_id', me).eq('friend_id', friendId);
    } else {
      await _client.from('friend_tags').upsert({'owner_id': me, 'friend_id': friendId, 'color': color});
    }
  }

  /// Everyone I'm friends with, name order.
  Future<List<Profile>> friends(String me) async {
    final rows = await _client
        .from('friendships')
        .select('requester_id, addressee_id, requester:profiles!friendships_requester_id_fkey($_profileCols), addressee:profiles!friendships_addressee_id_fkey($_profileCols)')
        .eq('status', 'accepted')
        .or('requester_id.eq.$me,addressee_id.eq.$me');
    final list = rows.map((r) {
      final other = r['requester_id'] == me ? r['addressee'] : r['requester'];
      return Profile.fromMap(other as Map<String, dynamic>);
    }).toList();
    list.sort((a, b) => (a.displayName ?? a.username ?? '').toLowerCase().compareTo((b.displayName ?? b.username ?? '').toLowerCase()));
    return list;
  }

  /// Requests waiting for my answer, newest first.
  Future<List<FriendRequest>> incomingRequests(String me) async {
    final rows = await _client
        .from('friendships')
        .select('created_at, requester:profiles!friendships_requester_id_fkey($_profileCols)')
        .eq('status', 'pending')
        .eq('addressee_id', me)
        .order('created_at', ascending: false);
    return rows
        .map((r) => FriendRequest(
              from: Profile.fromMap(r['requester'] as Map<String, dynamic>),
              createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
            ))
        .toList();
  }

  /// Ids of people I've asked and who haven't answered yet.
  Future<Set<String>> outgoingRequestIds(String me) async {
    final rows = await _client.from('friendships').select('addressee_id').eq('status', 'pending').eq('requester_id', me);
    return rows.map((r) => r['addressee_id'] as String).toSet();
  }

  Future<FriendshipStatus> status(String userId) async {
    final v = await _client.rpc('friendship_status', params: {'p_user': userId});
    return FriendshipStatus.fromDb(v as String?);
  }

  Future<int> friendCount(String userId) async {
    final v = await _client.rpc('friend_count', params: {'p_user': userId});
    return (v as num?)?.toInt() ?? 0;
  }

  Future<FriendshipStatus> sendRequest(String userId) async {
    final v = await _client.rpc('send_friend_request', params: {'p_user': userId});
    return FriendshipStatus.fromDb(v as String?);
  }

  Future<void> respond(String userId, {required bool accept}) =>
      _client.rpc('respond_friend_request', params: {'p_user': userId, 'p_accept': accept});

  Future<void> remove(String userId) => _client.rpc('remove_friend', params: {'p_user': userId});

  // ------------------------------------------------------------ live pins ---

  /// Friends' and clubmates' pins (ghosts, expired rows and strangers are
  /// filtered server-side). `via` says how I know each person.
  Future<List<FriendPin>> friendPins(String me) async {
    final rows = await _client.rpc('visible_pins') as List;
    return rows.map((r) => FriendPin.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  Future<MyLocation> myLocation(String me) async {
    final row = await _client.from('user_locations').select('ghost, share_mode, share_radius_m, place_id, event_id, updated_at, places(name)').eq('user_id', me).maybeSingle();
    return row == null ? MyLocation.unknown : MyLocation.fromMap(row);
  }

  Future<LocationPing> updateMyLocation({required double lat, required double lng, double? heading, double? accuracy}) async {
    final v = await _client.rpc('update_my_location', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_heading': ?heading,
      'p_accuracy': ?accuracy,
    });
    return LocationPing.fromMap((v as Map).cast<String, dynamic>());
  }

  Future<void> setGhost(bool ghost) => _client.rpc('set_ghost', params: {'p_ghost': ghost});
  Future<void> setShare(String mode, {int? radiusM}) => _client.rpc('set_share_mode', params: {'p_mode': mode, 'p_radius': ?radiusM});

  /// Realtime: fires on any change to a pin I'm allowed to see.
  RealtimeChannel subscribePins(String me, void Function() onChange) {
    final channel = _client.channel('pins:$me');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_locations',
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }
}

final friendsRepositoryProvider = Provider<FriendsRepository>((ref) => FriendsRepository(ref.watch(supabaseProvider)));
