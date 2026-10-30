/// Urgency ordering for the worker's list ("who should I attend first?").
///
/// This is a transparent PROTOTYPE rule built only from fields that exist in the register: how overdue the next visit is,
/// open referrals not yet attended, recently missed visits and the visit type. It is NOT a clinical risk score: the weights
/// below are placeholders for a clinical reviewer to replace. Every household shows the reasons behind its position.
enum UrgencyLevel { urgent, soon, routine }

enum UrgencyReason { overdue, dueToday, openReferral, missedVisits, visitType }

class UrgencyFactor {
  const UrgencyFactor(this.reason, this.value, this.points);
  final UrgencyReason reason;

  /// days overdue / days an open referral has waited / number of missed visits (0 for dueToday, visitType)
  final int value;
  final int points;
}

class HouseholdUrgency {
  const HouseholdUrgency({
    required this.householdId,
    required this.villageId,
    required this.score,
    required this.level,
    required this.factors,
    required this.category,
    this.visitId,
  });
  final String householdId, villageId;
  final int score;
  final UrgencyLevel level;
  final List<UrgencyFactor> factors;
  final String? category, visitId;
}

/// Placeholder weights (see class note). Kept in one place so a reviewer can change them without touching the screens.
abstract final class UrgencyWeights {
  static const overdueBase = 20;
  static const overduePerDay = 1;
  static const overdueDayCap = 45;
  static const dueToday = 15;
  static const openReferral = 25;
  static const referralWaitPerDay = 1;
  static const referralWaitCap = 14;
  static const missedEach = 8;
  static const missedCap = 24;
  static const urgentFrom = 70;
  static const soonFrom = 35;
  static const Map<String, int> visitType = {
    'ANC': 15,
    'HYPERTENSION': 12,
    'DIABETES': 10,
    'IMMUNISATION': 10,
    'NUTRITION': 8,
  };
}

HouseholdUrgency scoreHousehold({
  required String householdId,
  required String villageId,
  required DateTime today,
  String? visitId,
  DateTime? scheduled,
  String? category,
  int openReferrals = 0,
  DateTime? oldestOpenReferral,
  int missedRecently = 0,
}) {
  final f = <UrgencyFactor>[];
  if (scheduled != null) {
    final late = today.difference(scheduled).inDays;
    if (late > 0) {
      final capped = late > UrgencyWeights.overdueDayCap
          ? UrgencyWeights.overdueDayCap
          : late;
      f.add(
        UrgencyFactor(
          UrgencyReason.overdue,
          late,
          UrgencyWeights.overdueBase + capped * UrgencyWeights.overduePerDay,
        ),
      );
    } else if (late == 0) {
      f.add(
        const UrgencyFactor(UrgencyReason.dueToday, 0, UrgencyWeights.dueToday),
      );
    }
  }
  if (openReferrals > 0) {
    final waited = oldestOpenReferral == null
        ? 0
        : today.difference(oldestOpenReferral).inDays.clamp(0, 100000);
    final capped = waited > UrgencyWeights.referralWaitCap
        ? UrgencyWeights.referralWaitCap
        : waited;
    f.add(
      UrgencyFactor(
        UrgencyReason.openReferral,
        waited,
        UrgencyWeights.openReferral +
            capped * UrgencyWeights.referralWaitPerDay,
      ),
    );
  }
  if (missedRecently > 0) {
    final pts = missedRecently * UrgencyWeights.missedEach;
    f.add(
      UrgencyFactor(
        UrgencyReason.missedVisits,
        missedRecently,
        pts > UrgencyWeights.missedCap ? UrgencyWeights.missedCap : pts,
      ),
    );
  }
  final typePts = UrgencyWeights.visitType[category] ?? 0;
  // the visit type only breaks ties between households that are already waiting for something
  if (typePts > 0 && f.isNotEmpty) {
    f.add(UrgencyFactor(UrgencyReason.visitType, 0, typePts));
  }
  final score = f.fold<int>(0, (a, x) => a + x.points);
  return HouseholdUrgency(
    householdId: householdId,
    villageId: villageId,
    score: score,
    level: score >= UrgencyWeights.urgentFrom
        ? UrgencyLevel.urgent
        : score >= UrgencyWeights.soonFrom
        ? UrgencyLevel.soon
        : UrgencyLevel.routine,
    factors: f,
    category: category,
    visitId: visitId,
  );
}
