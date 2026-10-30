import '../core/clock.dart';
import '../data/local/local_store.dart';
import '../domain/rules/priority_rules.dart';

/// Builds the ranked "attend first" list from the phone's own database (works offline).
class PriorityService {
  PriorityService(this.store);
  final LocalStore store;

  Future<List<HouseholdUrgency>> ranked(DateTime today, {int? limit}) async {
    final missedSince = isoDate(today.subtract(const Duration(days: 90)));
    final rows = await store.db.rawQuery(
      '''SELECT h.household_id, h.village_id,
        (SELECT v.visit_id FROM visits v WHERE v.household_id = h.household_id AND v.visit_status = 'PLANNED' ORDER BY v.scheduled_date, v.visit_id LIMIT 1) AS visit_id,
        (SELECT v.scheduled_date FROM visits v WHERE v.household_id = h.household_id AND v.visit_status = 'PLANNED' ORDER BY v.scheduled_date, v.visit_id LIMIT 1) AS sched,
        (SELECT v.visit_reason FROM visits v WHERE v.household_id = h.household_id AND v.visit_status = 'PLANNED' ORDER BY v.scheduled_date, v.visit_id LIMIT 1) AS reason,
        (SELECT COUNT(*) FROM referrals r WHERE r.household_id = h.household_id AND r.record_state = 'ACTIVE' AND r.attendance_confirmed = 0 AND r.referral_status IN ('RECOMMENDED','PLANNED')) AS open_refs,
        (SELECT MIN(r.referral_created_date) FROM referrals r WHERE r.household_id = h.household_id AND r.record_state = 'ACTIVE' AND r.attendance_confirmed = 0 AND r.referral_status IN ('RECOMMENDED','PLANNED')) AS oldest_ref,
        (SELECT COUNT(*) FROM visits v WHERE v.household_id = h.household_id AND v.visit_status = 'MISSED' AND v.scheduled_date >= ?) AS missed
        FROM households h''',
      [missedSince],
    );
    final out = <HouseholdUrgency>[];
    for (final r in rows) {
      final u = scoreHousehold(
        householdId: r['household_id']! as String,
        villageId: r['village_id']! as String,
        today: today,
        visitId: r['visit_id'] as String?,
        scheduled: parseDate(r['sched'] as String?),
        category: r['reason'] as String?,
        openReferrals: (r['open_refs'] as int?) ?? 0,
        oldestOpenReferral: parseDate(r['oldest_ref'] as String?),
        missedRecently: (r['missed'] as int?) ?? 0,
      );
      if (u.score > 0) out.add(u);
    }
    out.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.householdId.compareTo(b.householdId);
    });
    return limit == null ? out : out.take(limit).toList();
  }
}
