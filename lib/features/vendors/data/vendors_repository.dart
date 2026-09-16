import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../events/domain/event.dart';
import '../domain/vendor.dart';

/// Partner applications, vendor dashboard, vouchers, wallet, redemptions.
/// Everything that writes goes through a security-definer RPC.
class VendorsRepository {
  VendorsRepository(this._client);
  final SupabaseClient _client;

  List<Map<String, dynamic>> _rows(Object? v) => (v as List).map((r) => (r as Map).cast<String, dynamic>()).toList();

  // ----------------------------------------------------------- partners ---

  /// Uploads a logo / receipt to `post-photos/<uid>/vendor/…` and returns its public URL.
  Future<String> uploadImage({required String userId, required Uint8List bytes}) async {
    final path = '$userId/vendor/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _client.storage.from('post-photos').uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    return _client.storage.from('post-photos').getPublicUrl(path);
  }

  Future<String> applyPartner({
    required ApplicationKind kind,
    required String name,
    required String type,
    String? address,
    String? placeId,
    String? phone,
    String? description,
    String? logoUrl,
    String? ssmNo,
    double? lat,
    double? lng,
  }) async {
    final v = await _client.rpc('apply_partner', params: {
      'p_kind': kind.db,
      'p_lat': ?lat,
      'p_lng': ?lng,
      'p_name': name,
      'p_type': type,
      'p_address': address,
      'p_place': placeId,
      'p_phone': phone,
      'p_description': description,
      'p_logo_url': logoUrl,
      'p_ssm': ssmNo,
    });
    return v as String;
  }

  Future<PartnerApplication?> myApplication(ApplicationKind kind) async {
    final rows = _rows(await _client.rpc('my_partner_application', params: {'p_kind': kind.db}));
    return rows.isEmpty ? null : PartnerApplication.fromMap(rows.first);
  }

  Future<List<PartnerApplication>> adminQueue() async =>
      _rows(await _client.rpc('admin_partner_queue', params: {'p_limit': 100})).map(PartnerApplication.fromMap).toList();

  Future<void> reviewApplication(String id, {required bool approve, String? note}) =>
      _client.rpc('admin_review_partner', params: {'p_id': id, 'p_approve': approve, 'p_note': ?note});

  Future<Vendor?> myVendor() async {
    final rows = _rows(await _client.rpc('my_vendor'));
    return rows.isEmpty ? null : Vendor.fromMap(rows.first);
  }

  Future<void> updateMyVendor({String? address, String? phone, String? description, String? logoUrl, double? lat, double? lng, String? hours, List<String>? photoUrls, Map<String, Object?>? hoursJson}) =>
      _client.rpc('update_my_vendor', params: {
        'p_address': address,
        'p_phone': phone,
        'p_description': description,
        'p_logo_url': logoUrl,
        'p_lat': ?lat,
        'p_lng': ?lng,
        'p_hours': ?hours,
        'p_photo_urls': ?photoUrls,
        'p_hours_json': ?hoursJson,
      });

  // ------------------------------------------------------------ products ---
  Future<List<Product>> myProducts() async {
    final id = (await _client.rpc('my_vendor_id')) as String?;
    if (id == null) return const [];
    final rows = await _client.from('vendor_products').select().eq('vendor_id', id).order('sort_order').order('created_at');
    return (rows as List).map((r) => Product.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  Future<List<Product>> partnerProducts(String vendorId) async {
    final rows = await _client.from('vendor_products').select().eq('vendor_id', vendorId).eq('active', true).order('sort_order').order('created_at');
    return (rows as List).map((r) => Product.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  Future<String> saveProduct({String? id, required String name, String? description, double? price, required List<String> photoUrls, required List<ProductVariant> variants, required bool active}) async {
    final v = await _client.rpc('save_product', params: {
      'p_id': id,
      'p_name': name,
      'p_description': description,
      'p_price': price,
      'p_photo_urls': photoUrls,
      'p_variants': variants.map((v) => v.toJson()).toList(),
      'p_active': active,
    });
    return v as String;
  }

  Future<void> deleteProduct(String id) => _client.rpc('delete_product', params: {'p_id': id});

  /// Every active partner, for the directory.
  Future<List<PublicVendor>> allPartners() async {
    final rows = await _client.from('vendors_public').select().order('name');
    return (rows as List).map((r) => PublicVendor.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  Future<void> recordView(String vendorId) => _client.rpc('view_partner', params: {'p_vendor': vendorId});

  /// A partner as members see it.
  Future<PublicVendor?> publicVendor(String id) async {
    final row = await _client.from('vendors_public').select().eq('id', id).maybeSingle();
    return row == null ? null : PublicVendor.fromMap(row);
  }

  Future<List<Event>> vendorEvents(String id) async {
    final rows = await _client
        .from('events_with_counts')
        .select()
        .eq('vendor_id', id)
        .eq('status', 'active')
        .gte('starts_at', DateTime.now().subtract(const Duration(hours: 6)).toUtc().toIso8601String())
        .order('starts_at', ascending: true)
        .limit(20);
    return rows.map(Event.fromMap).toList();
  }

  // ----------------------------------------------------------- vouchers ---

  Future<List<Voucher>> myVouchers() async => _rows(await _client.rpc('my_vendor_vouchers')).map(Voucher.fromMap).toList();

  Future<String> saveVoucher({
    String? id,
    required String title,
    String? description,
    String? terms,
    required DiscountKind kind,
    required double value,
    required double minSpend,
    required int pointsCost,
    int? maxClaims,
    required int perUser,
    DateTime? startsAt,
    DateTime? endsAt,
    required bool active,
    String? productId,
  }) async {
    final v = await _client.rpc('save_voucher', params: {
      'p_product_id': productId,
      'p_id': id,
      'p_title': title,
      'p_description': description,
      'p_terms': terms,
      'p_kind': kind.db,
      'p_value': value,
      'p_min_spend': minSpend,
      'p_points_cost': pointsCost,
      'p_max_claims': maxClaims,
      'p_per_user': perUser,
      'p_starts': startsAt?.toUtc().toIso8601String(),
      'p_ends': endsAt?.toUtc().toIso8601String(),
      'p_active': active,
    });
    return v as String;
  }

  Future<void> setVoucherActive(String id, bool active) => _client.rpc('set_voucher_active', params: {'p_id': id, 'p_active': active});

  // --------------------------------------------------------------- shop ---

  Future<List<Voucher>> shop() async => _rows(await _client.rpc('shop_vouchers', params: {'p_limit': 100})).map(Voucher.fromMap).toList();

  /// Returns the new claim id and how many points were spent.
  Future<({String id, int pointsSpent})> claim(String voucherId) async {
    final m = ((await _client.rpc('claim_voucher', params: {'p_voucher': voucherId})) as Map).cast<String, dynamic>();
    return (id: m['id'] as String, pointsSpent: (m['points_spent'] as num?)?.toInt() ?? 0);
  }

  Future<List<VoucherClaim>> wallet() async => _rows(await _client.rpc('my_vouchers', params: {'p_limit': 100})).map(VoucherClaim.fromMap).toList();

  Future<String> claimPayload(String claimId) async => await _client.rpc('voucher_claim_payload', params: {'p_claim': claimId}) as String;

  // ---------------------------------------------------------- redeeming ---

  Future<ClaimLookup> lookup({required String claimId, required String code}) async {
    final m = ((await _client.rpc('lookup_voucher_claim', params: {'p_claim': claimId, 'p_code': code})) as Map).cast<String, dynamic>();
    return ClaimLookup.fromMap(m);
  }

  Future<RedeemResult> redeem({required String claimId, required String code, required double bill, String? receiptUrl, String? note}) async {
    final m = ((await _client.rpc('redeem_voucher', params: {
      'p_claim': claimId,
      'p_code': code,
      'p_bill': bill,
      'p_receipt_url': receiptUrl,
      'p_note': note,
    })) as Map)
        .cast<String, dynamic>();
    return RedeemResult.fromMap(m);
  }

  Future<List<Redemption>> myRedemptions() async =>
      _rows(await _client.rpc('my_vendor_redemptions', params: {'p_limit': 100})).map(Redemption.fromMap).toList();

  Future<List<MonthRow>> monthlyReport({String? vendorId}) async =>
      _rows(await _client.rpc('vendor_monthly_report', params: {'p_vendor': vendorId})).map(MonthRow.fromMap).toList();

  Future<List<VendorCommissionRow>> adminCommission(DateTime month) async {
    final d = '${month.year}-${month.month.toString().padLeft(2, '0')}-01';
    return _rows(await _client.rpc('admin_commission_report', params: {'p_month': d})).map(VendorCommissionRow.fromMap).toList();
  }
}

final vendorsRepositoryProvider = Provider<VendorsRepository>((ref) => VendorsRepository(ref.watch(supabaseProvider)));
