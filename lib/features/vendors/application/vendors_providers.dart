import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../admin/application/admin_providers.dart';
import '../../points/application/points_providers.dart';
import '../../social/application/notification_providers.dart';
import '../../events/domain/event.dart';
import '../../map/application/map_providers.dart';
import '../data/vendors_repository.dart';
import '../domain/vendor.dart';

/// My shop, or null if I'm not an approved partner.
final myVendorProvider = FutureProvider<Vendor?>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(null);
  return ref.watch(vendorsRepositoryProvider).myVendor();
});

/// My latest application of that kind (any status), or null.
final myPartnerApplicationProvider = FutureProvider.family<PartnerApplication?, ApplicationKind>((ref, kind) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(null);
  return ref.watch(vendorsRepositoryProvider).myApplication(kind);
});

// Every list below watches the user id so a sign-out / sign-in never shows the previous member's data.
final adminPartnerQueueProvider = FutureProvider<List<PartnerApplication>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(vendorsRepositoryProvider).adminQueue();
});

final vendorVouchersProvider = FutureProvider<List<Voucher>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(vendorsRepositoryProvider).myVouchers();
});

final vendorRedemptionsProvider = FutureProvider<List<Redemption>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(vendorsRepositoryProvider).myRedemptions();
});

final vendorProductsProvider = FutureProvider<List<Product>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(vendorsRepositoryProvider).myProducts();
});

/// A partner's products as members see them.
final partnerProductsProvider = FutureProvider.autoDispose.family<List<Product>, String>((ref, id) => ref.watch(vendorsRepositoryProvider).partnerProducts(id));

/// Every active partner (Rewards → Partners).
final partnersDirectoryProvider = FutureProvider<List<PublicVendor>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(vendorsRepositoryProvider).allPartners();
});

/// Count a page view (once per member per day; owners never count).
final partnerViewedProvider = FutureProvider.family<void, String>((ref, id) => ref.watch(vendorsRepositoryProvider).recordView(id).catchError((_) {}));

/// A partner's public page.
final vendorPublicProvider = FutureProvider.autoDispose.family<PublicVendor?, String>((ref, id) => ref.watch(vendorsRepositoryProvider).publicVendor(id));
final vendorEventsProvider = FutureProvider.autoDispose.family<List<Event>, String>((ref, id) => ref.watch(vendorsRepositoryProvider).vendorEvents(id));

final vendorMonthlyProvider = FutureProvider.family<List<MonthRow>, String?>((ref, vendorId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(vendorsRepositoryProvider).monthlyReport(vendorId: vendorId);
});

final adminCommissionProvider = FutureProvider.family<List<VendorCommissionRow>, DateTime>((ref, month) {
  ref.watch(currentUserIdProvider);
  return ref.watch(vendorsRepositoryProvider).adminCommission(month);
});

/// Rewards shop.
final shopVouchersProvider = FutureProvider<List<Voucher>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(vendorsRepositoryProvider).shop();
});

/// My wallet.
final myWalletProvider = FutureProvider<List<VoucherClaim>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(vendorsRepositoryProvider).wallet();
});

final claimPayloadProvider = FutureProvider.family<String, String>((ref, claimId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(vendorsRepositoryProvider).claimPayload(claimId);
});

class VendorActions {
  VendorActions(this._ref);
  final Ref _ref;
  VendorsRepository get _repo => _ref.read(vendorsRepositoryProvider);

  /// Upload one picked photo and get its public URL (product / variant photos).
  Future<String?> upload(XFile photo) => _upload(photo);

  Future<String?> _upload(XFile? photo) async {
    if (photo == null) return null;
    final me = _ref.read(currentUserIdProvider);
    if (me == null) return null;
    final bytes = await photo.readAsBytes();
    return _repo.uploadImage(userId: me, bytes: bytes);
  }

  Future<void> apply({
    ApplicationKind kind = ApplicationKind.vendor,
    required String name,
    required String type,
    String? address,
    String? placeId,
    String? phone,
    String? description,
    String? ssmNo,
    XFile? logo,
    double? lat,
    double? lng,
  }) async {
    final logoUrl = await _upload(logo);
    await _repo.applyPartner(kind: kind, name: name, type: type, address: address, placeId: placeId, phone: phone, description: description, logoUrl: logoUrl, ssmNo: ssmNo, lat: lat, lng: lng);
    _ref.invalidate(myPartnerApplicationProvider(kind));
  }

  Future<void> reviewApplication(String id, {required bool approve, String? note}) async {
    await _repo.reviewApplication(id, approve: approve, note: note);
    _ref.invalidate(adminPartnerQueueProvider);
    _ref.invalidate(adminStatsProvider);
  }

  Future<void> updateShop({String? address, String? phone, String? description, XFile? logo, double? lat, double? lng, String? hours, Map<String, Object?>? hoursJson, List<String>? keptPhotos, List<XFile> newPhotos = const []}) async {
    final logoUrl = await _upload(logo);
    List<String>? photos;
    if (keptPhotos != null) {
      photos = [...keptPhotos];
      for (final f in newPhotos) {
        final url = await _upload(f);
        if (url != null) photos.add(url);
      }
    }
    await _repo.updateMyVendor(address: address, phone: phone, description: description, logoUrl: logoUrl, lat: lat, lng: lng, hours: hours, photoUrls: photos, hoursJson: hoursJson);
    _ref.invalidate(myVendorProvider);
    _ref.invalidate(spotsProvider);
    _ref.invalidate(partnersDirectoryProvider);
  }

  Future<void> saveProduct({String? id, required String name, String? description, double? price, required List<String> keptPhotos, List<XFile> newPhotos = const [], required List<ProductVariant> variants, required bool active}) async {
    final photos = [...keptPhotos];
    for (final f in newPhotos) {
      final url = await _upload(f);
      if (url != null) photos.add(url);
    }
    await _repo.saveProduct(id: id, name: name, description: description, price: price, photoUrls: photos, variants: variants, active: active);
    _ref.invalidate(vendorProductsProvider);
    _ref.invalidate(myVendorProvider);
  }

  Future<void> deleteProduct(String id) async {
    await _repo.deleteProduct(id);
    _ref.invalidate(vendorProductsProvider);
    _ref.invalidate(vendorVouchersProvider);
    _ref.invalidate(myVendorProvider);
  }

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
    final out = await _repo.saveVoucher(
      id: id,
      title: title,
      description: description,
      terms: terms,
      kind: kind,
      value: value,
      minSpend: minSpend,
      pointsCost: pointsCost,
      maxClaims: maxClaims,
      perUser: perUser,
      startsAt: startsAt,
      endsAt: endsAt,
      active: active,
      productId: productId,
    );
    _ref.invalidate(vendorVouchersProvider);
    _ref.invalidate(myVendorProvider);
    _ref.invalidate(shopVouchersProvider);
    return out;
  }

  Future<void> setActive(String id, bool active) async {
    await _repo.setVoucherActive(id, active);
    _ref.invalidate(vendorVouchersProvider);
    _ref.invalidate(myVendorProvider);
    _ref.invalidate(shopVouchersProvider);
  }

  /// Claim from the shop. Returns the new claim id.
  Future<({String id, int pointsSpent})> claim(String voucherId) async {
    final r = await _repo.claim(voucherId);
    _ref.invalidate(shopVouchersProvider);
    _ref.invalidate(myWalletProvider);
    if (r.pointsSpent > 0) {
      _ref.read(pointsActionsProvider).refreshBalance();
      _ref.invalidate(pointHistoryProvider);
    }
    return r;
  }

  Future<ClaimLookup> lookup({required String claimId, required String code}) => _repo.lookup(claimId: claimId, code: code);

  Future<RedeemResult> redeem({required String claimId, required String code, required double bill, XFile? receipt, String? note}) async {
    final receiptUrl = await _upload(receipt);
    final r = await _repo.redeem(claimId: claimId, code: code, bill: bill, receiptUrl: receiptUrl, note: note);
    _ref.invalidate(vendorRedemptionsProvider);
    _ref.invalidate(vendorVouchersProvider);
    _ref.invalidate(myVendorProvider);
    _ref.invalidate(vendorMonthlyProvider(null));
    _ref.invalidate(notificationsProvider);
    return r;
  }
}

final vendorActionsProvider = Provider<VendorActions>((ref) => VendorActions(ref));
