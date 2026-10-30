import '../../data/models/referral.dart';

/// Port of backend `reports/service.py::aggregate` so a basic report can be built on the phone with no server.
/// Recorded referrals only: no predictions, and household visits are never counted as hospital attendance.
class ReportSummary {
  const ReportSummary({
    required this.facilityId,
    required this.periodStart,
    required this.periodEnd,
    required this.recommended,
    required this.planned,
    required this.attendanceConfirmed,
    required this.byCategory,
    required this.excluded,
    this.dataAsOf,
  });
  final String facilityId;
  final DateTime periodStart, periodEnd;
  final int recommended, planned, attendanceConfirmed;
  final Map<String, int> byCategory, excluded;
  final String? dataAsOf;
  int get total => recommended + planned + attendanceConfirmed;
}

ReportSummary aggregateReferrals(
  List<Referral> refs,
  String facilityId,
  DateTime start,
  DateTime end,
) {
  final seen = <String>{};
  final cat = <String, int>{}, excl = <String, int>{};
  var rec = 0, plan = 0, conf = 0;
  String? asOf;
  for (final r in refs) {
    if (!seen.add(r.referralId)) {
      excl['repeated_id'] = (excl['repeated_id'] ?? 0) + 1;
      continue;
    }
    if (r.facilityId != facilityId) {
      excl['other_facility'] = (excl['other_facility'] ?? 0) + 1;
      continue;
    }
    if (r.createdDate.isBefore(start) || r.createdDate.isAfter(end)) {
      excl['outside_period'] = (excl['outside_period'] ?? 0) + 1;
      continue;
    }
    if (r.recordState != 'ACTIVE') {
      final k = r.recordState.toLowerCase();
      excl[k] = (excl[k] ?? 0) + 1;
      continue;
    }
    switch (r.phase) {
      case ReferralPhase.attendanceConfirmed:
        conf++;
      case ReferralPhase.planned:
        plan++;
      default:
        rec++;
    }
    cat[r.serviceCategory] = (cat[r.serviceCategory] ?? 0) + 1;
    if (asOf == null || r.lastUpdated.compareTo(asOf) > 0) asOf = r.lastUpdated;
  }
  return ReportSummary(
    facilityId: facilityId,
    periodStart: start,
    periodEnd: end,
    recommended: rec,
    planned: plan,
    attendanceConfirmed: conf,
    byCategory: cat,
    excluded: excl,
    dataAsOf: asOf,
  );
}

/// FRESH <= 24h, RECENT <= 72h, else STALE_OFFLINE; NOT_PROVIDED when the device has never synced (project policy, not clinical).
String freshnessLabel(DateTime? lastSync, DateTime now) {
  if (lastSync == null) return 'NOT_PROVIDED';
  final h = now.difference(lastSync).inMinutes / 60;
  return h <= 24
      ? 'FRESH'
      : h <= 72
      ? 'RECENT'
      : 'STALE_OFFLINE';
}

String summaryToCsv(
  ReportSummary s,
  String freshness,
  String generatedAt,
  String? lastSyncAt,
) {
  final b = StringBuffer('field,value\n')
    ..writeln('computed_on,this device (offline)')
    ..writeln('facility_id,${s.facilityId}')
    ..writeln(
      'period_start,${s.periodStart.toIso8601String().substring(0, 10)}',
    )
    ..writeln('period_end,${s.periodEnd.toIso8601String().substring(0, 10)}')
    ..writeln('generated_at,$generatedAt')
    ..writeln('last_sync_at,${lastSyncAt ?? ''}')
    ..writeln('data_freshness_label,$freshness')
    ..writeln('count_recommended,${s.recommended}')
    ..writeln('count_planned,${s.planned}')
    ..writeln('count_attendance_confirmed,${s.attendanceConfirmed}')
    ..writeln('count_total_included,${s.total}');
  s.byCategory.forEach((k, v) => b.writeln('service_category_$k,$v'));
  s.excluded.forEach((k, v) => b.writeln('excluded_$k,$v'));
  b.writeln(
    'privacy_notice,"Aggregate counts only. No household or patient identifiers. SYNTHETIC DATA in demo. Recorded referrals, not predicted arrivals; household visits are not hospital attendance."',
  );
  return b.toString();
}
