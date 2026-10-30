import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/domain/rules/priority_rules.dart';
import 'package:health_companion/services/priority_service.dart';

import 'support/builders.dart';
import 'support/harness.dart';

void main() {
  group('scoreHousehold', () {
    test(
      'overdue + open referral + missed visit outranks a visit due today',
      () {
        final a = scoreHousehold(
          householdId: 'A',
          villageId: 'V',
          today: today,
          scheduled: DateTime(2026, 9, 1),
          category: 'ANC',
          openReferrals: 1,
          oldestOpenReferral: DateTime(2026, 10, 1),
          missedRecently: 1,
        );
        final b = scoreHousehold(
          householdId: 'B',
          villageId: 'V',
          today: today,
          scheduled: today,
          category: 'ROUTINE',
        );
        expect(a.score, greaterThan(b.score));
        expect(a.level, UrgencyLevel.urgent);
        expect(b.level, UrgencyLevel.routine);
        expect(
          a.factors.map((f) => f.reason),
          containsAll([
            UrgencyReason.overdue,
            UrgencyReason.openReferral,
            UrgencyReason.missedVisits,
            UrgencyReason.visitType,
          ]),
        );
      },
    );

    test(
      'nothing pending -> score 0, and the visit type alone adds nothing',
      () {
        final u = scoreHousehold(
          householdId: 'C',
          villageId: 'V',
          today: today,
          scheduled: DateTime(2026, 10, 20),
          category: 'ANC',
        );
        expect(u.score, 0);
      },
    );

    test('more overdue days rank higher, capped', () {
      int s(int days) => scoreHousehold(
        householdId: 'x',
        villageId: 'v',
        today: today,
        scheduled: today.subtract(Duration(days: days)),
      ).score;
      expect(s(10), greaterThan(s(2)));
      expect(s(200), s(UrgencyWeights.overdueDayCap));
    });
  });

  test('PriorityService ranks households from the local database', () async {
    final rig = await Rig.create();
    await rig.store.upsertHouseholds([
      hh(
        'HH-A',
        status: 'OVERDUE',
        next: DateTime(2026, 9, 20),
        scheduled: 'ANC',
      ),
      hh('HH-B', status: 'DUE_TODAY', next: today, scheduled: 'ROUTINE'),
      hh('HH-C', status: 'NO_VISIT_DUE'),
    ], respectPending: false);
    await rig.store.upsertVisits([
      vis('V-A', 'HH-A', DateTime(2026, 9, 20), reason: 'ANC'),
      vis('V-B', 'HH-B', today),
    ], respectPending: false);
    await rig.store.upsertReferrals([
      ref(
        'R-A',
        'HH-A',
        'V-A',
        status: 'RECOMMENDED',
        created: DateTime(2026, 10, 5),
      ),
    ], respectPending: false);
    final list = await PriorityService(rig.store).ranked(today);
    expect(list.map((u) => u.householdId), [
      'HH-A',
      'HH-B',
    ]); // HH-C has nothing pending
    expect(list.first.visitId, 'V-A');
    await rig.adb.close();
  });
}
