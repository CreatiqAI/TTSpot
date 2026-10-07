import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../domain/exhibitor.dart';
import '../domain/exhibitor_import.dart';

/// Expo exhibitors (table `event_exhibitors`, RPCs in migration 0120).
class ExhibitorsRepository {
  ExhibitorsRepository(this._client);
  final SupabaseClient _client;

  /// Partners first, with the partner's logo and name and booth pin count.
  Future<List<Exhibitor>> list(String eventId) async {
    final rows = await _client.rpc('event_exhibitors_list', params: {'p_event': eventId});
    return sortExhibitors((rows as List).map((r) => Exhibitor.fromMap((r as Map).cast<String, dynamic>())));
  }

  /// Host: add (id null) or edit one. Stamp and freebie fields are left alone.
  Future<void> save({
    String? id,
    required String eventId,
    required String name,
    required List<String> booths,
    String? category,
    String? country,
    String? phone,
    String? email,
    String? website,
    String? about,
    String? partnerVendorId,
  }) async {
    String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final row = {
      'name': name.trim(),
      'booths': booths,
      'category': clean(category),
      'country': clean(country),
      'phone': clean(phone),
      'email': clean(email),
      'website': clean(website),
      'about': clean(about),
      'partner_vendor_id': partnerVendorId,
    };
    if (id == null) {
      await _client.from('event_exhibitors').insert({...row, 'event_id': eventId});
    } else {
      await _client.from('event_exhibitors').update(row).eq('id', id);
    }
  }

  Future<void> delete(String id) => _client.from('event_exhibitors').delete().eq('id', id);

  /// Host: adds a booth code to an exhibitor (keeps the code link in step
  /// when a booth pin is linked by hand).
  Future<void> addBooth(Exhibitor e, String code) async {
    final c = code.trim().toUpperCase();
    if (c.isEmpty || e.booths.map((b) => b.toUpperCase()).contains(c)) return;
    await _client.from('event_exhibitors').update({'booths': [...e.booths, c]}).eq('id', e.id);
  }

  /// Host: paste-a-list import. Returns exhibitors added or updated.
  Future<int> import(String eventId, List<ExhibitorImportRow> rows, {bool replace = false}) async {
    final n = await _client.rpc('import_event_exhibitors', params: {
      'p_event': eventId,
      'p_rows': rows.map((r) => r.toJson()).toList(),
      'p_replace': replace,
    });
    return (n as num?)?.toInt() ?? 0;
  }

  /// Host: booth pins -> exhibitors by booth code. Returns pins linked.
  Future<int> linkBoothPins(String eventId) async => ((await _client.rpc('link_event_booth_pins', params: {'p_event': eventId})) as num?)?.toInt() ?? 0;
}

final exhibitorsRepositoryProvider = Provider<ExhibitorsRepository>((ref) => ExhibitorsRepository(ref.watch(supabaseProvider)));
