import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';

class AdminStats {
  const AdminStats(this.m);
  final Map<String, dynamic> m;
  int operator [](String k) => (m[k] as num?)?.toInt() ?? 0;
}

class AdminReport {
  const AdminReport({required this.id, required this.reporterUsername, required this.targetType, required this.targetId, required this.reason, required this.createdAt, this.resolvedAt, this.targetLabel});
  final String id;
  final String reporterUsername;
  final String targetType;
  final String targetId;
  final String reason;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? targetLabel;
}

class AdminUser {
  const AdminUser({required this.id, required this.username, this.displayName, this.avatarUrl, required this.createdAt, this.homeState, required this.isAdmin, required this.clubOwner, required this.cars, this.lastSeen, this.phone, this.isPartner = false, this.email});
  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final DateTime createdAt;
  final String? homeState;
  final bool isAdmin;
  final bool clubOwner;
  final int cars;
  final DateTime? lastSeen;
  final String? phone;
  final bool isPartner;
  final String? email;
}

final adminStatsProvider = FutureProvider<AdminStats>((ref) async {
  ref.watch(currentUserIdProvider);
  final v = await ref.read(supabaseProvider).rpc('admin_stats');
  return AdminStats((v as Map).cast<String, dynamic>());
});

final adminReportsProvider = FutureProvider<List<AdminReport>>((ref) async {
  ref.watch(currentUserIdProvider);
  final rows = await ref.read(supabaseProvider).rpc('admin_reports', params: {'p_limit': 100}) as List;
  return rows.map((r) {
    final m = (r as Map).cast<String, dynamic>();
    return AdminReport(
      id: m['id'] as String,
      reporterUsername: m['reporter_username'] as String? ?? '',
      targetType: m['target_type'] as String? ?? '',
      targetId: m['target_id'] as String? ?? '',
      reason: m['reason'] as String? ?? '',
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      resolvedAt: m['resolved_at'] == null ? null : DateTime.parse(m['resolved_at'] as String).toLocal(),
      targetLabel: m['target_label'] as String?,
    );
  }).toList();
});

final adminUsersProvider = FutureProvider<List<AdminUser>>((ref) async {
  ref.watch(currentUserIdProvider);
  final rows = await ref.read(supabaseProvider).rpc('admin_recent_users', params: {'p_limit': 500}) as List;
  return rows.map((r) {
    final m = (r as Map).cast<String, dynamic>();
    return AdminUser(
      id: m['id'] as String,
      username: m['username'] as String? ?? '',
      displayName: m['display_name'] as String?,
      avatarUrl: m['avatar_url'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      homeState: m['home_state'] as String?,
      isAdmin: m['is_admin'] as bool? ?? false,
      clubOwner: m['club_owner'] as bool? ?? false,
      cars: (m['cars'] as num?)?.toInt() ?? 0,
      lastSeen: m['last_seen'] == null ? null : DateTime.parse(m['last_seen'] as String).toLocal(),
      phone: m['phone'] as String?,
      isPartner: m['is_partner'] as bool? ?? false,
      email: m['email'] as String?,
    );
  }).toList();
});

class AdminSuggestion {
  const AdminSuggestion({required this.id, required this.username, required this.name, this.address, required this.kind, this.note, this.photoUrl, required this.status, required this.createdAt});
  final String id;
  final String username;
  final String name;
  final String? address;
  final String kind;
  final String? note;
  final String? photoUrl;
  final String status;
  final DateTime createdAt;
}

final adminSuggestionsProvider = FutureProvider<List<AdminSuggestion>>((ref) async {
  ref.watch(currentUserIdProvider);
  final rows = await ref.read(supabaseProvider).rpc('admin_place_suggestions', params: {'p_limit': 100}) as List;
  return rows.map((r) {
    final m = (r as Map).cast<String, dynamic>();
    return AdminSuggestion(
      id: m['id'] as String,
      username: m['username'] as String? ?? '',
      name: m['name'] as String,
      address: m['address'] as String?,
      kind: m['kind'] as String? ?? 'other',
      note: m['note'] as String?,
      photoUrl: m['photo_url'] as String?,
      status: m['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    );
  }).toList();
});

final platformSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(currentUserIdProvider);
  final rows = await ref.read(supabaseProvider).from('platform_settings').select('key, value, description');
  return {for (final r in rows) r['key'] as String: r['value']};
});

class AdminActions {
  AdminActions(this._ref);
  final Ref _ref;

  Future<void> resolveReport(String id, {String? note}) async {
    await _ref.read(supabaseProvider).rpc('admin_resolve_report', params: {'p_id': id, 'p_note': ?note});
    _ref.invalidate(adminReportsProvider);
    _ref.invalidate(adminStatsProvider);
  }

  Future<void> setRole(String userId, {bool? admin, bool? clubOwner}) async {
    await _ref.read(supabaseProvider).rpc('admin_set_role', params: {'p_user': userId, 'p_admin': ?admin, 'p_club_owner': ?clubOwner});
    _ref.invalidate(adminUsersProvider);
  }

  Future<void> reviewSuggestion(String id, {required bool approve}) async {
    await _ref.read(supabaseProvider).rpc('admin_review_suggestion', params: {'p_id': id, 'p_approve': approve});
    _ref.invalidate(adminSuggestionsProvider);
    _ref.invalidate(adminStatsProvider);
  }

  Future<void> setSetting(String key, Object value) async {
    await _ref.read(supabaseProvider).rpc('admin_set_setting', params: {'p_key': key, 'p_value': value});
    _ref.invalidate(platformSettingsProvider);
  }
}

final adminActionsProvider = Provider<AdminActions>((ref) => AdminActions(ref));
