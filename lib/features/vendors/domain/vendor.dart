// Business partners (vendors), vouchers, claims, redemptions.

double _num(Object? v) => (v as num?)?.toDouble() ?? 0;
int _int(Object? v) => (v as num?)?.toInt() ?? 0;
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// What a partner application is for.
enum ApplicationKind {
  vendor, club;
  String get db => name;
  static ApplicationKind fromDb(String? v) => v == 'club' ? club : vendor;
}

/// Options shown in the vendor application form (db value, label). Partners
/// are the businesses car people spend on: parts, accessories, workshops.
const kBusinessTypes = <(String, String)>[
  ('accessories', 'Parts & accessories'),
  ('workshop', 'Workshop / tuning'),
  ('detailing', 'Detailing / tint / PPF'),
  ('tyres', 'Tyres & rims'),
  ('bodyshop', 'Body & paint'),
  ('audio', 'Audio & electronics'),
  ('carwash', 'Car wash'),
  ('cafe', 'Café / hangout'),
  ('other', 'Other'),
];

String businessTypeLabel(String type) => switch (type) {
      'club' => 'Car club',
      'restaurant' => 'Restaurant / mamak',
      'petrol' => 'Petrol / car wash',
      _ => kBusinessTypes.where((t) => t.$1 == type).map((t) => t.$2).firstOrNull ?? 'Other',
    };

enum ApplicationStatus {
  pending, approved, rejected;
  static ApplicationStatus fromDb(String v) => switch (v) { 'approved' => approved, 'rejected' => rejected, _ => pending };
}

class PartnerApplication {
  const PartnerApplication({
    required this.id,
    this.kind = ApplicationKind.vendor,
    required this.businessName,
    required this.businessType,
    required this.status,
    required this.createdAt,
    this.address,
    this.placeId,
    this.placeName,
    this.phone,
    this.ssmNo,
    this.description,
    this.logoUrl,
    this.reason,
    this.decidedAt,
    this.userId,
    this.username,
    this.avatarUrl,
  });

  final String id;
  final ApplicationKind kind;
  final String businessName;
  final String businessType;
  final ApplicationStatus status;
  final DateTime createdAt;
  final String? address;
  final String? placeId;
  final String? placeName;
  final String? phone;
  final String? ssmNo;
  final String? description;
  final String? logoUrl;
  final String? reason;
  final DateTime? decidedAt;
  // admin queue only
  final String? userId;
  final String? username;
  final String? avatarUrl;

  factory PartnerApplication.fromMap(Map<String, dynamic> m) => PartnerApplication(
        id: m['id'] as String,
        kind: ApplicationKind.fromDb(m['kind'] as String?),
        businessName: m['business_name'] as String,
        businessType: m['business_type'] as String? ?? 'other',
        status: ApplicationStatus.fromDb(m['status'] as String? ?? 'pending'),
        createdAt: _date(m['created_at'])!,
        address: m['address'] as String?,
        placeId: m['place_id'] as String?,
        placeName: m['place_name'] as String?,
        phone: m['phone'] as String?,
        ssmNo: m['ssm_no'] as String?,
        description: m['description'] as String?,
        logoUrl: m['logo_url'] as String?,
        reason: m['reason'] as String?,
        decidedAt: _date(m['decided_at']),
        userId: m['user_id'] as String?,
        username: m['username'] as String?,
        avatarUrl: m['avatar_url'] as String?,
      );
}

/// My shop, with the 30-day headline numbers.
class Vendor {
  const Vendor({
    required this.id,
    required this.name,
    required this.type,
    required this.active,
    required this.commissionRate,
    required this.createdAt,
    this.address,
    this.placeId,
    this.phone,
    this.description,
    this.logoUrl,
    this.liveVouchers = 0,
    this.redemptions30d = 0,
    this.bill30d = 0,
    this.commission30d = 0,
  });

  final String id;
  final String name;
  final String type;
  final bool active;
  final double commissionRate;
  final DateTime createdAt;
  final String? address;
  final String? placeId;
  final String? phone;
  final String? description;
  final String? logoUrl;
  final int liveVouchers;
  final int redemptions30d;
  final double bill30d;
  final double commission30d;

  factory Vendor.fromMap(Map<String, dynamic> m) => Vendor(
        id: m['id'] as String,
        name: m['name'] as String,
        type: m['type'] as String? ?? 'other',
        active: m['active'] as bool? ?? true,
        commissionRate: _num(m['commission_rate']),
        createdAt: _date(m['created_at'])!,
        address: m['address'] as String?,
        placeId: m['place_id'] as String?,
        phone: m['phone'] as String?,
        description: m['description'] as String?,
        logoUrl: m['logo_url'] as String?,
        liveVouchers: _int(m['live_vouchers']),
        redemptions30d: _int(m['redemptions_30d']),
        bill30d: _num(m['bill_30d']),
        commission30d: _num(m['commission_30d']),
      );
}

enum DiscountKind {
  percent, amount, freebie;
  static DiscountKind fromDb(String v) => switch (v) { 'amount' => amount, 'freebie' => freebie, _ => percent };
  String get db => name;
}

/// A vendor's offer. Used for both the shop listing and the vendor's own list.
class Voucher {
  const Voucher({
    required this.id,
    required this.title,
    required this.kind,
    required this.value,
    required this.minSpend,
    required this.pointsCost,
    required this.claimsCount,
    required this.perUserLimit,
    required this.startsAt,
    required this.active,
    this.description,
    this.terms,
    this.maxClaims,
    this.endsAt,
    this.createdAt,
    this.vendorId,
    this.vendorName,
    this.vendorType,
    this.vendorLogo,
    this.vendorAddress,
    this.placeId,
    this.myClaims = 0,
    this.myActiveClaim,
    this.redemptions = 0,
  });

  final String id;
  final String title;
  final DiscountKind kind;
  final double value;
  final double minSpend;
  final int pointsCost;
  final int claimsCount;
  final int perUserLimit;
  final DateTime startsAt;
  final bool active;
  final String? description;
  final String? terms;
  final int? maxClaims;
  final DateTime? endsAt;
  final DateTime? createdAt;
  // shop listing
  final String? vendorId;
  final String? vendorName;
  final String? vendorType;
  final String? vendorLogo;
  final String? vendorAddress;
  final String? placeId;
  final int myClaims;
  final String? myActiveClaim;
  // vendor list
  final int redemptions;

  /// "10% off", "RM 5 off", "Free item".
  String get headline => switch (kind) {
        DiscountKind.percent => '${value % 1 == 0 ? value.toInt() : value}% off',
        DiscountKind.amount => 'RM ${value % 1 == 0 ? value.toInt() : value.toStringAsFixed(2)} off',
        DiscountKind.freebie => 'Free item',
      };

  bool get soldOut => maxClaims != null && claimsCount >= maxClaims!;
  bool get ended => endsAt != null && endsAt!.isBefore(DateTime.now());
  int? get left => maxClaims == null ? null : (maxClaims! - claimsCount).clamp(0, maxClaims!);

  factory Voucher.fromMap(Map<String, dynamic> m) => Voucher(
        id: m['id'] as String,
        title: m['title'] as String,
        kind: DiscountKind.fromDb(m['discount_kind'] as String? ?? 'percent'),
        value: _num(m['discount_value']),
        minSpend: _num(m['min_spend']),
        pointsCost: _int(m['points_cost']),
        claimsCount: _int(m['claims_count']),
        perUserLimit: _int(m['per_user_limit']) == 0 ? 1 : _int(m['per_user_limit']),
        startsAt: _date(m['starts_at']) ?? DateTime.now(),
        active: m['active'] as bool? ?? true,
        description: m['description'] as String?,
        terms: m['terms'] as String?,
        maxClaims: m['max_claims'] == null ? null : _int(m['max_claims']),
        endsAt: _date(m['ends_at']),
        createdAt: _date(m['created_at']),
        vendorId: m['vendor_id'] as String?,
        vendorName: m['vendor_name'] as String?,
        vendorType: m['vendor_type'] as String?,
        vendorLogo: m['vendor_logo'] as String?,
        vendorAddress: m['vendor_address'] as String?,
        placeId: m['place_id'] as String?,
        myClaims: _int(m['my_claims']),
        myActiveClaim: m['my_active_claim'] as String?,
        redemptions: _int(m['redemptions']),
      );
}

enum ClaimStatus {
  active, redeemed, expired, cancelled;
  static ClaimStatus fromDb(String v) => switch (v) { 'redeemed' => redeemed, 'expired' => expired, 'cancelled' => cancelled, _ => active };
  String get label => switch (this) { active => 'Ready to use', redeemed => 'Used', expired => 'Expired', cancelled => 'Cancelled' };
}

/// A voucher in my wallet.
class VoucherClaim {
  const VoucherClaim({
    required this.id,
    required this.voucherId,
    required this.title,
    required this.kind,
    required this.value,
    required this.minSpend,
    required this.vendorId,
    required this.vendorName,
    required this.status,
    required this.pointsSpent,
    required this.claimedAt,
    required this.expiresAt,
    this.terms,
    this.vendorLogo,
    this.vendorAddress,
    this.placeId,
    this.redeemedAt,
  });

  final String id;
  final String voucherId;
  final String title;
  final DiscountKind kind;
  final double value;
  final double minSpend;
  final String vendorId;
  final String vendorName;
  final ClaimStatus status;
  final int pointsSpent;
  final DateTime claimedAt;
  final DateTime expiresAt;
  final String? terms;
  final String? vendorLogo;
  final String? vendorAddress;
  final String? placeId;
  final DateTime? redeemedAt;

  String get headline => switch (kind) {
        DiscountKind.percent => '${value % 1 == 0 ? value.toInt() : value}% off',
        DiscountKind.amount => 'RM ${value % 1 == 0 ? value.toInt() : value.toStringAsFixed(2)} off',
        DiscountKind.freebie => 'Free item',
      };

  factory VoucherClaim.fromMap(Map<String, dynamic> m) => VoucherClaim(
        id: m['id'] as String,
        voucherId: m['voucher_id'] as String,
        title: m['title'] as String,
        kind: DiscountKind.fromDb(m['discount_kind'] as String? ?? 'percent'),
        value: _num(m['discount_value']),
        minSpend: _num(m['min_spend']),
        vendorId: m['vendor_id'] as String,
        vendorName: m['vendor_name'] as String? ?? 'Partner',
        status: ClaimStatus.fromDb(m['status'] as String? ?? 'active'),
        pointsSpent: _int(m['points_spent']),
        claimedAt: _date(m['claimed_at'])!,
        expiresAt: _date(m['expires_at'])!,
        terms: m['terms'] as String?,
        vendorLogo: m['vendor_logo'] as String?,
        vendorAddress: m['vendor_address'] as String?,
        placeId: m['place_id'] as String?,
        redeemedAt: _date(m['redeemed_at']),
      );
}

/// What the vendor sees after scanning a customer's voucher QR.
class ClaimLookup {
  const ClaimLookup({
    required this.claimId,
    required this.status,
    required this.title,
    required this.kind,
    required this.value,
    required this.minSpend,
    required this.commissionRate,
    required this.expiresAt,
    this.terms,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.redeemedAt,
  });

  final String claimId;
  final ClaimStatus status;
  final String title;
  final DiscountKind kind;
  final double value;
  final double minSpend;
  final double commissionRate;
  final DateTime expiresAt;
  final String? terms;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final DateTime? redeemedAt;

  String get headline => switch (kind) {
        DiscountKind.percent => '${value % 1 == 0 ? value.toInt() : value}% off',
        DiscountKind.amount => 'RM ${value % 1 == 0 ? value.toInt() : value.toStringAsFixed(2)} off',
        DiscountKind.freebie => 'Free item',
      };

  factory ClaimLookup.fromMap(Map<String, dynamic> m) => ClaimLookup(
        claimId: m['claim_id'] as String,
        status: ClaimStatus.fromDb(m['status'] as String? ?? 'active'),
        title: m['title'] as String,
        kind: DiscountKind.fromDb(m['discount_kind'] as String? ?? 'percent'),
        value: _num(m['discount_value']),
        minSpend: _num(m['min_spend']),
        commissionRate: _num(m['commission_rate']),
        expiresAt: _date(m['expires_at'])!,
        terms: m['terms'] as String?,
        username: m['username'] as String?,
        displayName: m['display_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        redeemedAt: _date(m['redeemed_at']),
      );
}

class Redemption {
  const Redemption({
    required this.id,
    required this.title,
    required this.billAmount,
    required this.commissionRate,
    required this.commissionAmount,
    required this.createdAt,
    this.username,
    this.avatarUrl,
    this.receiptUrl,
    this.note,
  });

  final String id;
  final String title;
  final double billAmount;
  final double commissionRate;
  final double commissionAmount;
  final DateTime createdAt;
  final String? username;
  final String? avatarUrl;
  final String? receiptUrl;
  final String? note;

  factory Redemption.fromMap(Map<String, dynamic> m) => Redemption(
        id: m['id'] as String,
        title: m['title'] as String,
        billAmount: _num(m['bill_amount']),
        commissionRate: _num(m['commission_rate']),
        commissionAmount: _num(m['commission_amount']),
        createdAt: _date(m['created_at'])!,
        username: m['username'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        receiptUrl: m['receipt_url'] as String?,
        note: m['note'] as String?,
      );
}

class RedeemResult {
  const RedeemResult({required this.id, required this.bill, required this.commission, required this.rate, required this.title});
  final String id;
  final double bill;
  final double commission;
  final double rate;
  final String title;

  factory RedeemResult.fromMap(Map<String, dynamic> m) => RedeemResult(
        id: m['id'] as String,
        bill: _num(m['bill']),
        commission: _num(m['commission']),
        rate: _num(m['rate']),
        title: m['title'] as String? ?? '',
      );
}

class MonthRow {
  const MonthRow({required this.month, required this.redemptions, required this.billTotal, required this.commissionTotal});
  final DateTime month;
  final int redemptions;
  final double billTotal;
  final double commissionTotal;

  factory MonthRow.fromMap(Map<String, dynamic> m) => MonthRow(
        month: DateTime.parse(m['month'] as String),
        redemptions: _int(m['redemptions']),
        billTotal: _num(m['bill_total']),
        commissionTotal: _num(m['commission_total']),
      );
}

class VendorCommissionRow {
  const VendorCommissionRow({required this.vendorId, required this.vendorName, required this.redemptions, required this.billTotal, required this.commissionTotal, this.ownerUsername});
  final String vendorId;
  final String vendorName;
  final String? ownerUsername;
  final int redemptions;
  final double billTotal;
  final double commissionTotal;

  factory VendorCommissionRow.fromMap(Map<String, dynamic> m) => VendorCommissionRow(
        vendorId: m['vendor_id'] as String,
        vendorName: m['vendor_name'] as String,
        ownerUsername: m['owner_username'] as String?,
        redemptions: _int(m['redemptions']),
        billTotal: _num(m['bill_total']),
        commissionTotal: _num(m['commission_total']),
      );
}

/// "RM 1,234.50"
String rm(double v) {
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final b = StringBuffer();
  final digits = parts[0];
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return 'RM $b.${parts[1]}';
}
