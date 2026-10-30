import '../../core/clock.dart';

const serviceCategories = [
  'ANC',
  'IMMUNISATION',
  'NUTRITION',
  'HYPERTENSION',
  'DIABETES',
  'GENERAL',
];

/// What the user may be TOLD about a referral. `attendanceConfirmed` exists ONLY when the record carries an
/// actual hospital attendance record id; a recommendation or a planned date can never produce it.
enum ReferralPhase {
  recommended,
  planned,
  attendanceConfirmed,
  cancelled,
  invalid,
  duplicate,
}

class Referral {
  const Referral({
    required this.referralId,
    required this.householdId,
    required this.visitId,
    required this.facilityId,
    required this.serviceCategory,
    required this.createdDate,
    this.plannedVisitDate,
    required this.status,
    required this.attendanceConfirmed,
    this.attendanceConfirmationDate,
    this.attendanceRecordId,
    required this.recordState,
    this.duplicateOf,
    required this.lastUpdated,
    required this.version,
  });

  final String referralId,
      householdId,
      visitId,
      facilityId,
      serviceCategory,
      status,
      recordState,
      lastUpdated;
  final DateTime createdDate;
  final DateTime? plannedVisitDate, attendanceConfirmationDate;
  final bool attendanceConfirmed;
  final String? attendanceRecordId, duplicateOf;
  final int version;

  ReferralPhase get phase {
    switch (recordState) {
      case 'CANCELLED':
        return ReferralPhase.cancelled;
      case 'INVALID':
        return ReferralPhase.invalid;
      case 'DUPLICATE':
        return ReferralPhase.duplicate;
    }
    if (status == 'ATTENDANCE_CONFIRMED' &&
        attendanceConfirmed &&
        (attendanceRecordId ?? '').isNotEmpty) {
      return ReferralPhase.attendanceConfirmed;
    }
    if (status == 'PLANNED' || status == 'ATTENDANCE_CONFIRMED') {
      return ReferralPhase
          .planned; // confirmed flag without a record is NOT shown as attended
    }
    return ReferralPhase.recommended;
  }

  /// Open = needs follow-through (recommended or planned, still active).
  bool get isPending =>
      recordState == 'ACTIVE' &&
      (phase == ReferralPhase.recommended || phase == ReferralPhase.planned);

  Referral copyWith({
    String? status,
    DateTime? plannedVisitDate,
    String? recordState,
    String? lastUpdated,
    int? version,
  }) => Referral(
    referralId: referralId,
    householdId: householdId,
    visitId: visitId,
    facilityId: facilityId,
    serviceCategory: serviceCategory,
    createdDate: createdDate,
    plannedVisitDate: plannedVisitDate ?? this.plannedVisitDate,
    status: status ?? this.status,
    attendanceConfirmed: attendanceConfirmed,
    attendanceConfirmationDate: attendanceConfirmationDate,
    attendanceRecordId: attendanceRecordId,
    recordState: recordState ?? this.recordState,
    duplicateOf: duplicateOf,
    lastUpdated: lastUpdated ?? this.lastUpdated,
    version: version ?? this.version,
  );

  factory Referral.fromJson(Map<String, dynamic> j) => Referral(
    referralId: j['referral_id'] as String,
    householdId: j['household_id'] as String,
    visitId: j['visit_id'] as String,
    facilityId: j['facility_id'] as String,
    serviceCategory: j['service_category'] as String,
    createdDate: parseDate(j['referral_created_date'] as String)!,
    plannedVisitDate: parseDate(j['planned_visit_date'] as String?),
    status: j['referral_status'] as String,
    attendanceConfirmed: j['attendance_confirmed'] as bool,
    attendanceConfirmationDate: parseDate(
      j['attendance_confirmation_date'] as String?,
    ),
    attendanceRecordId: j['attendance_record_id'] as String?,
    recordState: j['record_state'] as String,
    duplicateOf: j['duplicate_of'] as String?,
    lastUpdated: j['last_updated'] as String,
    version: j['version'] as int,
  );

  factory Referral.fromRow(Map<String, Object?> r) => Referral(
    referralId: r['referral_id']! as String,
    householdId: r['household_id']! as String,
    visitId: r['visit_id']! as String,
    facilityId: r['facility_id']! as String,
    serviceCategory: r['service_category']! as String,
    createdDate: parseDate(r['referral_created_date']! as String)!,
    plannedVisitDate: parseDate(r['planned_visit_date'] as String?),
    status: r['referral_status']! as String,
    attendanceConfirmed: (r['attendance_confirmed']! as int) == 1,
    attendanceConfirmationDate: parseDate(
      r['attendance_confirmation_date'] as String?,
    ),
    attendanceRecordId: r['attendance_record_id'] as String?,
    recordState: r['record_state']! as String,
    duplicateOf: r['duplicate_of'] as String?,
    lastUpdated: r['last_updated']! as String,
    version: r['version']! as int,
  );

  Map<String, Object?> toRow() => {
    'referral_id': referralId,
    'household_id': householdId,
    'visit_id': visitId,
    'facility_id': facilityId,
    'service_category': serviceCategory,
    'referral_created_date': isoDate(createdDate),
    'planned_visit_date': plannedVisitDate == null
        ? null
        : isoDate(plannedVisitDate!),
    'referral_status': status,
    'attendance_confirmed': attendanceConfirmed ? 1 : 0,
    'attendance_confirmation_date': attendanceConfirmationDate == null
        ? null
        : isoDate(attendanceConfirmationDate!),
    'attendance_record_id': attendanceRecordId,
    'record_state': recordState,
    'duplicate_of': duplicateOf,
    'last_updated': lastUpdated,
    'version': version,
  };
}
