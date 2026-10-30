import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/data/local/database.dart';
import 'package:health_companion/data/local/local_store.dart';
import 'package:health_companion/data/models/visit.dart';
import 'package:health_companion/presentation/screens/households_screen.dart';
import 'package:health_companion/presentation/screens/visit_screen.dart';
import 'package:health_companion/services/field_work_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'support/builders.dart';
import 'support/harness.dart';

VisitOutcome completed({String? time, bool auto = true, DateTime? date}) =>
    VisitOutcome(
      status: 'COMPLETED',
      actualDate: date ?? today,
      followupRequired: false,
      visitTime: time,
      visitTimeAuto: auto,
    );

void main() {
  sqfliteFfiInit();

  group('the time of a visit is saved on the phone', () {
    late Rig rig;
    setUp(() async {
      rig = await Rig.create(configured: false);
      await rig.seedBasic(); // the test clock says 09:00 on the day
    });
    tearDown(() => rig.dispose());

    test('completing a visit stores the time with the outcome, and remembers if it was filled in automatically', () async {
      await rig.fieldWork.recordOutcome('VIS-1', completed(time: '08:45'));
      final t = (await rig.store.visitTime('VIS-1'))!;
      expect(t.hhmm, '08:45');
      expect(t.auto, isTrue);
    });

    test('a time the worker changed is stored as NOT automatic', () async {
      await rig.fieldWork.recordOutcome(
        'VIS-1',
        completed(time: '07:30', auto: false),
      );
      expect((await rig.store.visitTime('VIS-1'))!.auto, isFalse);
    });

    test(
      'a missed visit also keeps the time the worker went to the door',
      () async {
        await rig.fieldWork.recordOutcome(
          'VIS-1',
          VisitOutcome(
            status: 'MISSED',
            followupRequired: true,
            nextFollowupDate: DateTime(2026, 10, 20),
            visitTime: '08:10',
          ),
        );
        expect((await rig.store.visitTime('VIS-1'))!.hhmm, '08:10');
      },
    );

    test('a cancelled visit stores no time', () async {
      await rig.fieldWork.recordOutcome(
        'VIS-1',
        const VisitOutcome(status: 'CANCELLED', visitTime: '08:10'),
      );
      expect(await rig.store.visitTime('VIS-1'), isNull);
    });

    test(
      'no time given -> nothing stored (older callers keep working)',
      () async {
        await rig.fieldWork.recordOutcome('VIS-1', completed());
        expect(await rig.store.visitTime('VIS-1'), isNull);
      },
    );

    test('a time later than now, on today\'s date, is refused and NOTHING is saved', () async {
      await expectLater(
        rig.fieldWork.recordOutcome('VIS-1', completed(time: '23:59')),
        throwsA(
          isA<DomainValidation>().having(
            (e) => e.errors['visitTime'],
            'visitTime',
            'future',
          ),
        ),
      );
      expect((await rig.store.visit('VIS-1'))!.status, 'PLANNED');
      expect(await rig.store.visitTime('VIS-1'), isNull);
    });

    test('a time earlier today is fine, and a time on an earlier date can be any time of day', () async {
      await rig.fieldWork.recordOutcome(
        'VIS-1',
        completed(time: '09:00', date: today),
      );
      await rig.store.db.delete('visit_times');
      await rig.store.db.update('visits', {
        'visit_status': 'PLANNED',
        'actual_visit_date': null,
      });
      await rig.fieldWork.recordOutcome(
        'VIS-1',
        completed(time: '23:59', date: today.subtract(const Duration(days: 1))),
      );
      expect((await rig.store.visitTime('VIS-1'))!.hhmm, '23:59');
    });

    test('a malformed time is refused', () async {
      await expectLater(
        rig.fieldWork.recordOutcome('VIS-1', completed(time: '25:99')),
        throwsA(
          isA<DomainValidation>().having(
            (e) => e.errors['visitTime'],
            'visitTime',
            'invalid',
          ),
        ),
      );
    });

    test('a COMPLETED visit sends the time to the server as HH:mm', () async {
      await rig.fieldWork.recordOutcome('VIS-1', completed(time: '08:45'));
      final ops = await rig.store.db.query(
        'sync_outbox',
        where: "entity_type = 'visit'",
      );
      expect(
        ops.any(
          (o) =>
              o['payload'].toString().contains('"actual_visit_time":"08:45"'),
        ),
        isTrue,
      );
    });

    test('a could-not-visit time is NOT sent (the server stores a time only on COMPLETED visits), but is kept on the phone', () async {
      await rig.fieldWork.recordOutcome(
        'VIS-1',
        VisitOutcome(
          status: 'MISSED',
          followupRequired: true,
          nextFollowupDate: DateTime(2026, 10, 20),
          visitTime: '08:10',
        ),
      );
      final ops = await rig.store.db.query('sync_outbox');
      for (final o in ops) {
        expect(o['payload'].toString().contains('actual_visit_time'), isFalse);
      }
      expect((await rig.store.visitTime('VIS-1'))!.hhmm, '08:10');
    });

    test('a visit pulled from the server WITH a time updates the phone\'s copy (HH:MM:SS from the server is read as HH:mm)', () async {
      final v = Visit.fromJson({
        'visit_id': 'VIS-PULL',
        'household_id': 'HH-1',
        'worker_id': 'WRK-1',
        'scheduled_date': '2026-10-01',
        'actual_visit_date': '2026-10-02',
        'actual_visit_time': '14:05:00',
        'visit_status': 'COMPLETED',
        'visit_reason': 'ANC',
        'followup_required': false,
        'next_followup_date': null,
        'referral_status': 'NONE',
        'referral_id': null,
        'recorded_at': '2026-10-02T09:00:00',
        'updated_at': '2026-10-02T09:00:00',
        'version': 2,
      });
      expect(v.actualVisitTime, '14:05');
      await rig.store.upsertVisits([v], respectPending: false);
      expect((await rig.store.visitTime('VIS-PULL'))!.hhmm, '14:05');
    });

    test('a pulled visit the server has NO time for keeps the time the phone recorded', () async {
      await rig.fieldWork.recordOutcome('VIS-1', completed(time: '08:45'));
      final v = (await rig.store.visit('VIS-1'))!;
      await rig.store.upsertVisits([
        v,
      ], respectPending: false); // server row without a time
      expect((await rig.store.visitTime('VIS-1'))!.hhmm, '08:45');
    });

    test('a malformed time from the server is ignored, not stored', () {
      final j = {
        'visit_id': 'V',
        'household_id': 'H',
        'worker_id': 'W',
        'scheduled_date': '2026-10-01',
        'actual_visit_time': '99:99',
        'visit_status': 'PLANNED',
        'visit_reason': 'ANC',
        'recorded_at': 'x',
        'updated_at': 'x',
        'version': 1,
      };
      expect(Visit.fromJson(j).actualVisitTime, isNull);
    });

    test('a pull from the server that replaces the visit row does NOT erase the saved time', () async {
      await rig.fieldWork.recordOutcome('VIS-1', completed(time: '08:45'));
      final v = (await rig.store.visit('VIS-1'))!;
      await rig.store.upsertVisits([
        v,
      ], respectPending: false); // what a server pull does
      expect((await rig.store.visitTime('VIS-1'))!.hhmm, '08:45');
    });

    test('wiping the phone\'s data removes the times too', () async {
      await rig.fieldWork.recordOutcome('VIS-1', completed(time: '08:45'));
      await rig.store.wipe();
      expect(await rig.store.visitTime('VIS-1'), isNull);
    });

    test('visitTimes() returns many at once', () async {
      await rig.fieldWork.recordOutcome('VIS-1', completed(time: '08:45'));
      final m = await rig.store.visitTimes(['VIS-1', 'VIS-NOPE']);
      expect(m, {'VIS-1': '08:45'});
      expect(await rig.store.visitTimes([]), isEmpty);
    });
  });

  test('an existing v2 database upgrades to v3 keeping its data and gains the visit_times table', () async {
    final path = await tempDbPath();
    final v2 = await openTestDb(path: path, target: 2);
    await LocalStore(v2).upsertHouseholds([hh('HH-A')], respectPending: false);
    await v2.close();
    final v3 = await openTestDb(path: path);
    expect(await v3.db.getVersion(), AppDatabase.schemaVersion);
    expect(AppDatabase.schemaVersion, greaterThanOrEqualTo(3));
    expect((await LocalStore(v3).household('HH-A')), isNotNull);
    expect(await LocalStore(v3).visitTime('VIS-X'), isNull); // table exists
    await v3.close();
  });

  group('the visit form', () {
    uiTest('opening a visit fills in the current time by itself, and says so', (
      t,
    ) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      final id = (await t.runAsync(
        () => rig.services.store.plannedVisits(
          'overdue',
          rig.services.clock.today(),
          limit: 1,
        ),
      ))!.first.visit.visitId;
      await pumpApp(
        t,
        rig,
        home: VisitScreen(visitId: id),
        size: const Size(412, 1400),
      );
      await settle(t, maxRounds: 20);
      expect(find.byKey(const Key('visit-time')), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const Key('visit-time-value'))).data,
        '9:00 AM',
      ); // the harness clock is 09:00
      expect(
        find.text(
          'Recorded automatically when you opened this visit. It cannot be changed.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Saved with the visit and sent to the server when you are online.',
        ),
        findsOneWidget,
      );
      expect(
        t.widget<Text>(find.byKey(const Key('visit-date-value'))).data,
        '13 Oct 2026',
      ); // the date is detected too
    });

    uiTest(
      'saving stores that automatic time; the finished visit then shows it',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        final id = (await t.runAsync(
          () => rig.services.store.plannedVisits(
            'overdue',
            rig.services.clock.today(),
            limit: 1,
          ),
        ))!.first.visit.visitId;
        await pumpApp(
          t,
          rig,
          home: VisitScreen(visitId: id),
          size: const Size(412, 1400),
        );
        await settle(t, maxRounds: 20);
        await t.ensureVisible(find.byKey(const Key('save-visit')));
        await t.tap(find.byKey(const Key('save-visit')));
        await settle(t, maxRounds: 25);
        final saved = await t.runAsync(() => rig.services.store.visitTime(id));
        expect(saved!.hhmm, '09:00');
        expect(saved.auto, isTrue);
      },
    );

    uiTest(
      'the date and time CANNOT be changed: no picker, no date field, no tappable row',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        final id = (await t.runAsync(
          () => rig.services.store.plannedVisits(
            'overdue',
            rig.services.clock.today(),
            limit: 1,
          ),
        ))!.first.visit.visitId;
        await pumpApp(
          t,
          rig,
          home: VisitScreen(visitId: id),
          size: const Size(412, 1400),
        );
        await settle(t, maxRounds: 20);
        await t.tap(find.byKey(const Key('visit-time')));
        await settle(t, maxRounds: 10);
        expect(find.byType(TimePickerDialog), findsNothing);
        expect(find.byType(DatePickerDialog), findsNothing);
        expect(find.byKey(const Key('actual-date')), findsNothing);
        expect(find.byIcon(Icons.calendar_today), findsNothing);
        expect(find.byIcon(Icons.edit_outlined), findsNothing);
        expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      },
    );

    uiTest(
      'saving records the date AND time that were detected when the form opened',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        final id = (await t.runAsync(
          () => rig.services.store.plannedVisits(
            'overdue',
            rig.services.clock.today(),
            limit: 1,
          ),
        ))!.first.visit.visitId;
        await pumpApp(
          t,
          rig,
          home: VisitScreen(visitId: id),
          size: const Size(412, 1400),
        );
        await settle(t, maxRounds: 20);
        await t.ensureVisible(find.byKey(const Key('save-visit')));
        await t.tap(find.byKey(const Key('save-visit')));
        await settle(t, maxRounds: 25);
        final v = await t.runAsync(() => rig.services.store.visit(id));
        expect(v!.status, 'COMPLETED');
        expect(v.actualVisitDate, rig.services.clock.today());
        expect(
          (await t.runAsync(() => rig.services.store.visitTime(id)))!.hhmm,
          '09:00',
        );
      },
    );

    uiTest('a cancelled visit shows no time row', (t) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      final id = (await t.runAsync(
        () => rig.services.store.plannedVisits(
          'overdue',
          rig.services.clock.today(),
          limit: 1,
        ),
      ))!.first.visit.visitId;
      await pumpApp(
        t,
        rig,
        home: VisitScreen(visitId: id),
        size: const Size(412, 1400),
      );
      await settle(t, maxRounds: 20);
      await t.tap(find.byKey(const Key('outcome-cancelled')));
      await settle(t, maxRounds: 6);
      expect(find.byKey(const Key('visit-time')), findsNothing);
    });

    uiTest('a household\'s visit history shows when the worker went', (
      t,
    ) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      final hid = (await t.runAsync(() async {
        final st = rig.services.store;
        final first = (await st.plannedVisits(
          'overdue',
          rig.services.clock.today(),
          limit: 1,
        )).first;
        await rig.services.fieldWork.recordOutcome(
          first.visit.visitId,
          VisitOutcome(
            status: 'COMPLETED',
            actualDate: rig.services.clock.today(),
            followupRequired: false,
            visitTime: '08:05',
          ),
        );
        return first.visit.householdId;
      }))!;
      await pumpApp(
        t,
        rig,
        home: HouseholdDetailScreen(householdId: hid),
        size: const Size(412, 3000),
      );
      await settle(t, maxRounds: 25);
      expect(find.textContaining('8:05 AM'), findsOneWidget);
    });
  });
}
