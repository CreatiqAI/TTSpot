/// One sticker check-in and where it is in the pipeline.
enum VerificationStatus {
  pending,
  approved,
  rejected,
  review;

  static VerificationStatus fromDb(String? v) => switch (v) {
        'approved' => approved,
        'rejected' => rejected,
        'review' => review,
        _ => pending,
      };

  String get label => switch (this) {
        pending => 'Checking…',
        approved => 'Approved',
        rejected => 'Not approved',
        review => 'In review',
      };
}

class SpotVerification {
  const SpotVerification({
    required this.id,
    required this.placeId,
    required this.placeName,
    required this.photoUrl,
    required this.status,
    required this.createdAt,
    this.reason,
    this.distanceM,
    this.decidedAt,
    // admin queue only
    this.userId,
    this.username,
    this.avatarUrl,
    this.aiNote,
    this.aiCarPresent,
    this.aiLooksReal,
    this.aiConfidence,
  });

  final String id;
  final String placeId;
  final String placeName;
  final String photoUrl;
  final VerificationStatus status;
  final DateTime createdAt;
  final String? reason;
  final int? distanceM;
  final DateTime? decidedAt;
  final String? userId;
  final String? username;
  final String? avatarUrl;
  final String? aiNote;
  final bool? aiCarPresent;
  final bool? aiLooksReal;
  final double? aiConfidence;

  factory SpotVerification.fromMap(Map<String, dynamic> m) {
    final ai = m['ai_result'] as Map<String, dynamic>?;
    return SpotVerification(
      id: m['id'] as String,
      placeId: m['place_id'] as String,
      placeName: m['place_name'] as String? ?? '',
      photoUrl: m['photo_url'] as String,
      status: VerificationStatus.fromDb(m['status'] as String?),
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      reason: m['reason'] as String?,
      distanceM: (m['distance_m'] as num?)?.toInt(),
      decidedAt: m['decided_at'] == null ? null : DateTime.parse(m['decided_at'] as String).toLocal(),
      userId: m['user_id'] as String?,
      username: m['username'] as String?,
      avatarUrl: m['avatar_url'] as String?,
      aiNote: ai?['note'] as String?,
      aiCarPresent: ai?['car_present'] as bool?,
      aiLooksReal: ai?['looks_real_photo'] as bool?,
      aiConfidence: (ai?['confidence'] as num?)?.toDouble(),
    );
  }
}

/// What the Edge Function answers right after a submission.
class VerifyResult {
  const VerifyResult({required this.status, this.reason, this.points = 0});
  final VerificationStatus status;
  final String? reason;
  final int points;

  factory VerifyResult.fromMap(Map<String, dynamic> m) => VerifyResult(
        status: VerificationStatus.fromDb(m['status'] as String?),
        reason: m['reason'] as String?,
        points: (m['points'] as num?)?.toInt() ?? 0,
      );
}
