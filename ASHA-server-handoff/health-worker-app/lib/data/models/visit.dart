import '../../core/clock.dart';

const visitStatuses = [
  'PLANNED',
  'COMPLETED',
  'MISSED',
  'RESCHEDULED',
  'CANCELLED',
];

class Visit {
  const Visit({
    required this.visitId,
    required this.householdId,
    required this.workerId,
    required this.scheduledDate,
    this.actualVisitDate,
    this.actualVisitTime,
    required this.status,
    required this.reason,
    this.followupRequired,
    this.nextFollowupDate,
    this.referralStatus = 'NONE',
    this.referralId,
    required this.recordedAt,
    required this.updatedAt,
    required this.version,
  });

  final String visitId,
      householdId,
      workerId,
      status,
      reason,
      referralStatus,
      recordedAt,
      updatedAt;
  final DateTime scheduledDate;
  final DateTime? actualVisitDate, nextFollowupDate;
  final bool? followupRequired;
  final String? referralId;

  /// 'HH:mm' (24 h): when the worker went, as the server returns it (HH:MM:SS -> seconds dropped). Not part of the local visits row.
  final String? actualVisitTime;
  final int version;

  Visit copyWith({
    DateTime? scheduledDate,
    DateTime? actualVisitDate,
    String? status,
    bool? followupRequired,
    DateTime? nextFollowupDate,
    String? referralStatus,
    String? referralId,
    String? updatedAt,
    int? version,
  }) => Visit(
    visitId: visitId,
    householdId: householdId,
    workerId: workerId,
    scheduledDate: scheduledDate ?? this.scheduledDate,
    actualVisitDate: actualVisitDate ?? this.actualVisitDate,
    actualVisitTime: actualVisitTime,
    status: status ?? this.status,
    reason: reason,
    followupRequired: followupRequired ?? this.followupRequired,
    nextFollowupDate: nextFollowupDate ?? this.nextFollowupDate,
    referralStatus: referralStatus ?? this.referralStatus,
    referralId: referralId ?? this.referralId,
    recordedAt: recordedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
  );

  factory Visit.fromJson(Map<String, dynamic> j) => Visit(
    visitId: j['visit_id'] as String,
    householdId: j['household_id'] as String,
    workerId: j['worker_id'] as String,
    scheduledDate: parseDate(j['scheduled_date'] as String)!,
    actualVisitDate: parseDate(j['actual_visit_date'] as String?),
    actualVisitTime: _hhmm(j['actual_visit_time'] as String?),
    status: j['visit_status'] as String,
    reason: j['visit_reason'] as String,
    followupRequired: j['followup_required'] as bool?,
    nextFollowupDate: parseDate(j['next_followup_date'] as String?),
    referralStatus: (j['referral_status'] as String?) ?? 'NONE',
    referralId: j['referral_id'] as String?,
    recordedAt: j['recorded_at'] as String,
    updatedAt: j['updated_at'] as String,
    version: j['version'] as int,
  );

  factory Visit.fromRow(Map<String, Object?> r) => Visit(
    visitId: r['visit_id']! as String,
    householdId: r['household_id']! as String,
    workerId: r['worker_id']! as String,
    scheduledDate: parseDate(r['scheduled_date']! as String)!,
    actualVisitDate: parseDate(r['actual_visit_date'] as String?),
    status: r['visit_status']! as String,
    reason: r['visit_reason']! as String,
    followupRequired: r['followup_required'] == null
        ? null
        : (r['followup_required']! as int) == 1,
    nextFollowupDate: parseDate(r['next_followup_date'] as String?),
    referralStatus: r['referral_status']! as String,
    referralId: r['referral_id'] as String?,
    recordedAt: r['recorded_at']! as String,
    updatedAt: r['updated_at']! as String,
    version: r['version']! as int,
  );

  Map<String, Object?> toRow() => {
    'visit_id': visitId,
    'household_id': householdId,
    'worker_id': workerId,
    'scheduled_date': isoDate(scheduledDate),
    'actual_visit_date': actualVisitDate == null
        ? null
        : isoDate(actualVisitDate!),
    'visit_status': status,
    'visit_reason': reason,
    'followup_required': followupRequired == null
        ? null
        : (followupRequired! ? 1 : 0),
    'next_followup_date': nextFollowupDate == null
        ? null
        : isoDate(nextFollowupDate!),
    'referral_status': referralStatus,
    'referral_id': referralId,
    'recorded_at': recordedAt,
    'updated_at': updatedAt,
    'version': version,
  };
}

/// '08:45:00' or '08:45' -> '08:45'; anything else -> null.
String? _hhmm(String? t) {
  if (t == null) return null;
  final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d(?:\.\d+)?)?$')
      .firstMatch(t);
  return m == null ? null : '${m.group(1)}:${m.group(2)}';
}
