import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../domain/dashboard.dart';

/// The organizer's dashboard and exports (migration 0123).
class DashboardRepository {
  DashboardRepository(this._client);
  final SupabaseClient _client;

  List<Map<String, dynamic>> _rows(Object? v) => ((v as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

  Future<ExpoDashboard> dashboard(String eventId) async =>
      ExpoDashboard.fromMap((await _client.rpc('expo_dashboard', params: {'p_event': eventId}) as Map).cast<String, dynamic>());

  Future<List<Map<String, dynamic>>> exportCheckins(String eventId) async =>
      _rows(await _client.rpc('expo_export_checkins', params: {'p_event': eventId}));

  Future<List<Map<String, dynamic>>> exportBoothVisits(String eventId) async =>
      _rows(await _client.rpc('expo_export_booth_visits', params: {'p_event': eventId}));
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) => DashboardRepository(ref.watch(supabaseProvider)));
