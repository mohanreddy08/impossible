import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';

/// Port of backend `visits/service.py::recompute_household`. Runs inside the caller's transaction.
/// last_visit_date = latest COMPLETED actual date; next due = earliest PLANNED scheduled date (its reason becomes the
/// scheduled category); status OVERDUE/DUE_TODAY/UPCOMING if a planned visit exists, else COMPLETED when the last visit is
/// within [recentDays] (a synthetic-dataset convention, NOT a clinical rule), else NO_VISIT_DUE.
Future<void> recomputeHousehold(
  DatabaseExecutor txn,
  String householdId,
  DateTime today, {
  int recentDays = 14,
}) async {
  final last =
      (await txn.rawQuery(
            "SELECT MAX(actual_visit_date) AS d FROM visits WHERE household_id = ? AND visit_status = 'COMPLETED'",
            [householdId],
          )).first['d']
          as String?;
  final next = await txn.rawQuery(
    "SELECT scheduled_date, visit_reason FROM visits WHERE household_id = ? AND visit_status = 'PLANNED' ORDER BY scheduled_date, visit_id LIMIT 1",
    [householdId],
  );
  String status;
  String? nextDate, cat;
  if (next.isNotEmpty) {
    nextDate = next.first['scheduled_date']! as String;
    cat = next.first['visit_reason']! as String;
    final nd = parseDate(nextDate)!;
    status = nd.isBefore(today)
        ? 'OVERDUE'
        : nd == today
        ? 'DUE_TODAY'
        : 'UPCOMING';
  } else if (last != null &&
      today.difference(parseDate(last)!).inDays <= recentDays) {
    status = 'COMPLETED';
  } else {
    status = 'NO_VISIT_DUE';
  }
  await txn.rawUpdate(
    'UPDATE households SET last_visit_date = ?, next_visit_due_date = ?, scheduled_followup_category = ?, record_status = ?, version = version + 1 WHERE household_id = ?',
    [last, nextDate, cat, status, householdId],
  );
}

enum PriorityBucket { overdue, today, upcoming }

/// Why a visit is where it is on the list. Only dates are used: no clinical risk score exists or is invented.
class VisitPriority {
  const VisitPriority(
    this.bucket,
    this.days,
    this.category,
    this.lastVisit,
    this.hasOpenReferral,
  );
  final PriorityBucket bucket;
  final int
  days; // days overdue (overdue) or days until (upcoming); 0 for today
  final String category;
  final DateTime? lastVisit;
  final bool hasOpenReferral;
}

VisitPriority priorityFor(
  DateTime scheduled,
  DateTime today,
  String category,
  DateTime? lastVisit, {
  bool hasOpenReferral = false,
}) {
  final diff = scheduled.difference(today).inDays;
  if (diff < 0) {
    return VisitPriority(
      PriorityBucket.overdue,
      -diff,
      category,
      lastVisit,
      hasOpenReferral,
    );
  }
  if (diff == 0) {
    return VisitPriority(
      PriorityBucket.today,
      0,
      category,
      lastVisit,
      hasOpenReferral,
    );
  }
  return VisitPriority(
    PriorityBucket.upcoming,
    diff,
    category,
    lastVisit,
    hasOpenReferral,
  );
}
