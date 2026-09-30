/// A car's paperwork, one row of `car_documents`. Owner-only (RLS): nobody
/// else can read it, not even with the car id.
class CarDocuments {
  const CarDocuments({
    required this.carId,
    this.roadTaxExpiry,
    this.insurer,
    this.policyNo,
    this.insuranceExpiry,
    this.ncdPct,
    this.sumInsured,
    this.note,
    this.puspakomDue,
    this.serviceDueOn,
    this.serviceDueKm,
  });

  final String carId;
  /// LKM (road tax) expiry.
  final DateTime? roadTaxExpiry;
  final String? insurer;
  final String? policyNo;
  final DateTime? insuranceExpiry;
  /// No-claim discount, e.g. 55.
  final double? ncdPct;
  final double? sumInsured;
  final String? note;
  final DateTime? puspakomDue;
  final DateTime? serviceDueOn;
  final int? serviceDueKm;

  bool get isEmpty =>
      roadTaxExpiry == null &&
      _blank(insurer) &&
      _blank(policyNo) &&
      insuranceExpiry == null &&
      ncdPct == null &&
      sumInsured == null &&
      _blank(note) &&
      puspakomDue == null &&
      serviceDueOn == null &&
      serviceDueKm == null;

  /// The dated things to keep an eye on, in the order the chips show them.
  List<DocDue> get dues => [
        if (roadTaxExpiry != null) DocDue(DocKind.roadTax, roadTaxExpiry!),
        if (insuranceExpiry != null) DocDue(DocKind.insurance, insuranceExpiry!),
        if (puspakomDue != null) DocDue(DocKind.puspakom, puspakomDue!),
        if (serviceDueOn != null) DocDue(DocKind.service, serviceDueOn!),
      ];

  /// Anything expired or under two weeks away.
  List<DocDue> get urgent => dues.where((d) => d.urgent).toList();

  static bool _blank(String? s) => (s ?? '').trim().isEmpty;
  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

  factory CarDocuments.fromMap(Map<String, dynamic> m) => CarDocuments(
        carId: m['car_id'] as String,
        roadTaxExpiry: _date(m['road_tax_expiry']),
        insurer: m['insurer'] as String?,
        policyNo: m['policy_no'] as String?,
        insuranceExpiry: _date(m['insurance_expiry']),
        ncdPct: (m['ncd_pct'] as num?)?.toDouble(),
        sumInsured: (m['sum_insured'] as num?)?.toDouble(),
        note: m['note'] as String?,
        puspakomDue: _date(m['puspakom_due']),
        serviceDueOn: _date(m['service_due_on']),
        serviceDueKm: (m['service_due_km'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() {
    String? day(DateTime? d) => d == null ? null : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    String? text(String? s) => _blank(s) ? null : s!.trim();
    return {
      'car_id': carId,
      'road_tax_expiry': day(roadTaxExpiry),
      'insurer': text(insurer),
      'policy_no': text(policyNo),
      'insurance_expiry': day(insuranceExpiry),
      'ncd_pct': ncdPct,
      'sum_insured': sumInsured,
      'note': text(note),
      'puspakom_due': day(puspakomDue),
      'service_due_on': day(serviceDueOn),
      'service_due_km': serviceDueKm,
    };
  }
}

enum DocKind {
  roadTax('Road tax', expires: true),
  insurance('Insurance', expires: true),
  puspakom('PUSPAKOM', expires: false),
  service('Service', expires: false);

  const DocKind(this.label, {required this.expires});
  final String label;

  /// Road tax and insurance run out; inspection and service fall due.
  final bool expires;
}

/// One dated document and how far off it is, counted in calendar days.
class DocDue {
  DocDue(this.kind, this.date, {DateTime? now}) : daysLeft = _daysBetween(now ?? DateTime.now(), date);

  final DocKind kind;
  final DateTime date;
  /// Negative once it has passed.
  final int daysLeft;

  /// Red: expired, due today, or under two weeks away.
  bool get urgent => daysLeft < 14;

  /// "Road tax · 23 days left", "Insurance · expired 3 days ago",
  /// "PUSPAKOM · due in 5 days", "Service · till 12 Mar 2027".
  String get text => '${kind.label} · $when';

  String get when {
    final d = daysLeft;
    if (d < 0) return '${kind.expires ? 'expired' : 'overdue'} ${_days(-d)}${kind.expires ? ' ago' : ''}';
    if (d == 0) return kind.expires ? 'expires today' : 'due today';
    if (d > 60) return '${kind.expires ? 'till' : 'due'} ${formatDay(date)}';
    return kind.expires ? '${_days(d)} left' : 'due in ${_days(d)}';
  }

  static String _days(int n) => n == 1 ? '1 day' : '$n days';

  static int _daysBetween(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "12 Mar 2027" for a calendar day (no weekday, no time zone shift).
String formatDay(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Malaysian no-claim discount steps.
const kNcdSteps = <double>[0, 25, 30, 38.33, 45, 55];

String formatNcd(double v) => '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}%';
