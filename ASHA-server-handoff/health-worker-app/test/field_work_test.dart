import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/data/local/local_store.dart';
import 'package:health_companion/data/models/outbox_op.dart';
import 'package:health_companion/data/models/referral.dart';
import 'package:health_companion/services/data_bus.dart';
import 'package:health_companion/services/field_work_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/builders.dart';
import 'support/harness.dart';

void main() {
  sqfliteFfiInit();

  group('record a visit offline', () {
    late Rig rig;
    setUp(() async {
      rig = await Rig.create(
        configured: false,
      ); // no server configured at all: pure offline
      await rig.seedBasic();
    });
    tearDown(() => rig.dispose());

    test('completing a visit saves locally, queues ordered operations and recomputes the household', () async {
      await rig.fieldWork.recordOutcome(
        'VIS-1',
        VisitOutcome(
          status: 'COMPLETED',
          actualDate: today,
          followupRequired: true,
          nextFollowupDate: DateTime(2026, 11, 12),
          referral: const ReferralDraft(
            facilityId: 'FAC-9',
            serviceCategory: 'ANC',
          ),
        ),
      );
      final v = (await rig.store.visit('VIS-1'))!;
      expect(v.status, 'COMPLETED');
      expect(v.actualVisitDate, today);
      expect(
        v.version,
        2,
        reason: 'optimistic local bump so the next edit sends the right base_version',
      );
      expect(v.referralStatus, 'RECOMMENDED');

      final ops = await rig.store.ops();
      expect(ops.map((o) => '${o.entityType}:${o.opType}'), [
        'visit:update',
        'visit:create',
        'referral:create',
      ], reason: 'update first, parent before child');
      final upd = ops[0];
      expect(upd.baseVersion, 1);
      expect(upd.payload, {
        'visit_status': 'COMPLETED',
        'actual_visit_date': '2026-10-13',
        'followup_required': true,
        'next_followup_date': '2026-11-12',
        'create_followup_task': false,
      });
      expect(
        upd.beforeJson!['visit_status'],
        'PLANNED',
        reason: 'snapshot kept so a discard can undo',
      );
      expect(ops[1].payload['scheduled_date'], '2026-11-12');
      expect(ops[1].entityId, startsWith('VIS-'));
      expect(ops[2].payload['facility_id'], 'FAC-9');
      expect(ops[2].payload['referral_status'], 'RECOMMENDED');
      expect(
        ops.every((o) => o.state == OpState.pending && o.opId.length >= 8),
        isTrue,
      );
      expect(ops.map((o) => o.opId).toSet().length, 3);

      final h = (await rig.store.household('HH-1'))!;
      expect(h.recordStatus, 'UPCOMING');
      expect(h.nextVisitDueDate, DateTime(2026, 11, 12));
      expect(h.lastVisitDate, today);
      final dash = await rig.store.dashboard(today);
      expect(dash.dueToday, 0);
      expect(dash.upcoming, 1);
    });

    test('a referral is created as RECOMMENDED only: never planned, never attended', () async {
      await rig.fieldWork.recordOutcome(
        'VIS-1',
        VisitOutcome(
          status: 'COMPLETED',
          actualDate: today,
          followupRequired: false,
          referral: const ReferralDraft(
            facilityId: 'FAC-9',
            serviceCategory: 'GENERAL',
          ),
        ),
      );
      final r = (await rig.store.pageReferrals('recommended')).first;
      expect(r.phase, ReferralPhase.recommended);
      expect(r.attendanceConfirmed, isFalse);
      expect(r.attendanceRecordId, isNull);
      expect(r.plannedVisitDate, isNull);
    });

    test('missed visit needs a new date and schedules it', () async {
      await rig.fieldWork.recordOutcome(
        'VIS-1',
        VisitOutcome(
          status: 'MISSED',
          followupRequired: true,
          nextFollowupDate: DateTime(2026, 10, 15),
        ),
      );
      expect((await rig.store.visit('VIS-1'))!.status, 'MISSED');
      expect(
        (await rig.store.household('HH-1'))!.nextVisitDueDate,
        DateTime(2026, 10, 15),
      );
      expect((await rig.store.ops()).map((o) => o.opType), [
        'update',
        'create',
      ]);
    });

    test('validation errors name the field and write NOTHING', () async {
      Future<Map<String, String>> fail(VisitOutcome o) async {
        try {
          await rig.fieldWork.recordOutcome('VIS-1', o);
        } on DomainValidation catch (e) {
          return e.errors;
        }
        return {};
      }

      expect(await fail(const VisitOutcome(status: 'COMPLETED')), {
        'actualDate': 'required',
      });
      expect(
        await fail(
          VisitOutcome(status: 'COMPLETED', actualDate: DateTime(2026, 10, 14)),
        ),
        {'actualDate': 'future'},
      );
      expect(
        await fail(
          VisitOutcome(
            status: 'COMPLETED',
            actualDate: today,
            followupRequired: true,
          ),
        ),
        {'nextDate': 'required'},
      );
      expect(
        await fail(
          VisitOutcome(
            status: 'COMPLETED',
            actualDate: today,
            followupRequired: true,
            nextFollowupDate: today,
          ),
        ),
        {'nextDate': 'notAfterVisit'},
      );
      expect(
        await fail(
          VisitOutcome(
            status: 'COMPLETED',
            actualDate: today,
            followupRequired: false,
            nextFollowupDate: DateTime(2026, 11, 1),
          ),
        ),
        {'nextDate': 'inconsistent'},
      );
      expect(
        await fail(
          const VisitOutcome(
            status: 'MISSED',
            followupRequired: false,
            referral: ReferralDraft(
              facilityId: 'F',
              serviceCategory: 'GENERAL',
            ),
          ),
        ),
        {'referral': 'needsCompletedVisit'},
      );
      expect(await rig.store.ops(), isEmpty);
      expect((await rig.store.visit('VIS-1'))!.status, 'PLANNED');
    });

    test('a visit that is already recorded cannot be recorded twice', () async {
      await rig.fieldWork.recordOutcome(
        'VIS-1',
        VisitOutcome(
          status: 'COMPLETED',
          actualDate: today,
          followupRequired: false,
        ),
      );
      expect(
        () => rig.fieldWork.recordOutcome(
          'VIS-1',
          VisitOutcome(
            status: 'COMPLETED',
            actualDate: today,
            followupRequired: false,
          ),
        ),
        throwsA(isA<DomainValidation>()),
      );
      expect((await rig.store.ops()).length, 1);
    });

    test('scheduling a visit queues a create and validates the date', () async {
      await rig.fieldWork.scheduleVisit(
        'HH-1',
        DateTime(2026, 10, 20),
        'ROUTINE',
      );
      final ops = await rig.store.ops();
      expect(ops.single.opType, 'create');
      expect(ops.single.payload['household_id'], 'HH-1');
      expect(
        () => rig.fieldWork.scheduleVisit(
          'HH-1',
          DateTime(2026, 10, 1),
          'ROUTINE',
        ),
        throwsA(isA<DomainValidation>()),
      );
    });
  });

  group('atomicity: saved and queued together or not at all', () {
    test('if queueing fails midway, nothing from that save remains', () async {
      final rig = await Rig.create();
      await rig.seedBasic();
      final failing = _FailingStore(rig.adb, failOnNth: 2);
      final svc = FieldWorkService(failing, rig.clock, DataBus());
      await expectLater(
        svc.recordOutcome(
          'VIS-1',
          VisitOutcome(
            status: 'COMPLETED',
            actualDate: today,
            followupRequired: true,
            nextFollowupDate: DateTime(2026, 11, 12),
          ),
        ),
        throwsA(anything),
      );
      expect(
        (await rig.store.visit('VIS-1'))!.status,
        'PLANNED',
        reason: 'rolled back',
      );
      expect(await rig.store.ops(), isEmpty);
      expect((await rig.store.household('HH-1'))!.recordStatus, 'DUE_TODAY');
      await rig.dispose();
    });
  });

  group('app restart does not lose saved work', () {
    test('visit outcome and queued ops are still there after closing and reopening the database file', () async {
      final path = await tempDbPath();
      var rig = await Rig.create(dbPath: path, configured: false);
      await rig.seedBasic();
      await rig.fieldWork.recordOutcome(
        'VIS-1',
        VisitOutcome(
          status: 'COMPLETED',
          actualDate: today,
          followupRequired: true,
          nextFollowupDate: DateTime(2026, 11, 12),
        ),
      );
      await rig.dispose(); // process "killed"

      rig = await Rig.create(dbPath: path, configured: false);
      expect((await rig.store.visit('VIS-1'))!.status, 'COMPLETED');
      final ops = await rig.store.ops();
      expect(ops.length, 2);
      expect(ops.every((o) => o.state == OpState.pending), isTrue);
      expect(await rig.store.protectedEntityIds('visit'), contains('VIS-1'));
      await rig.dispose();
    });
  });

  group('referral changes', () {
    late Rig rig;
    setUp(() async {
      rig = await Rig.create();
      await rig.seedBasic();
      await rig.store.upsertVisits([
        vis(
          'VIS-2',
          'HH-1',
          DateTime(2026, 9, 12),
          status: 'COMPLETED',
          actual: DateTime(2026, 9, 12),
        ),
      ], respectPending: false);
      await rig.store.upsertReferrals([
        ref('REF-R', 'HH-1', 'VIS-2', status: 'RECOMMENDED'),
        ref(
          'REF-C',
          'HH-1',
          'VIS-OLD',
          status: 'ATTENDANCE_CONFIRMED',
          confirmed: true,
          record: 'ATT-1',
          planned: DateTime(2026, 9, 20),
        ),
      ], respectPending: false);
    });
    tearDown(() => rig.dispose());

    test(
      'planning moves RECOMMENDED -> PLANNED but never to attendance confirmed',
      () async {
        await rig.fieldWork.planReferral('REF-R', DateTime(2026, 10, 20));
        final r = (await rig.store.referral('REF-R'))!;
        expect(r.phase, ReferralPhase.planned);
        expect(r.attendanceConfirmed, isFalse);
        expect(r.version, 2);
        final op = (await rig.store.ops()).single;
        expect(op.payload, {
          'referral_status': 'PLANNED',
          'planned_visit_date': '2026-10-20',
        });
        expect(op.baseVersion, 1);
      },
    );

    test('planned date cannot precede the referral date; confirmed referrals are immutable', () async {
      expect(
        () => rig.fieldWork.planReferral('REF-R', DateTime(2026, 8, 1)),
        throwsA(isA<DomainValidation>()),
      );
      expect(
        () => rig.fieldWork.planReferral('REF-C', DateTime(2026, 10, 20)),
        throwsA(isA<DomainValidation>()),
      );
      expect(
        () => rig.fieldWork.cancelReferral('REF-C'),
        throwsA(isA<DomainValidation>()),
      );
      expect(await rig.store.ops(), isEmpty);
    });

    test(
      'cancelling queues record_state CANCELLED and clears the visit link',
      () async {
        await rig.fieldWork.cancelReferral('REF-R');
        expect(
          (await rig.store.referral('REF-R'))!.phase,
          ReferralPhase.cancelled,
        );
        expect((await rig.store.ops()).single.payload, {
          'record_state': 'CANCELLED',
        });
      },
    );
  });

  group('referral status is never overstated', () {
    test(
      'a confirmed flag without an attendance record is NOT shown as attended',
      () {
        expect(
          ref(
            'R',
            'H',
            'V',
            status: 'ATTENDANCE_CONFIRMED',
            confirmed: true,
          ).phase,
          ReferralPhase.planned,
        );
        expect(
          ref(
            'R',
            'H',
            'V',
            status: 'ATTENDANCE_CONFIRMED',
            confirmed: false,
            record: 'ATT-1',
          ).phase,
          ReferralPhase.planned,
        );
        expect(
          ref(
            'R',
            'H',
            'V',
            status: 'ATTENDANCE_CONFIRMED',
            confirmed: true,
            record: 'ATT-1',
          ).phase,
          ReferralPhase.attendanceConfirmed,
        );
        expect(
          ref(
            'R',
            'H',
            'V',
            status: 'PLANNED',
            planned: DateTime(2026, 1, 1),
          ).phase,
          ReferralPhase.planned,
        );
        expect(
          ref('R', 'H', 'V', status: 'RECOMMENDED').phase,
          ReferralPhase.recommended,
        );
        expect(
          ref(
            'R',
            'H',
            'V',
            status: 'ATTENDANCE_CONFIRMED',
            confirmed: true,
            record: 'A',
            state: 'CANCELLED',
          ).phase,
          ReferralPhase.cancelled,
        );
        expect(
          ref(
            'R',
            'H',
            'V',
            status: 'RECOMMENDED',
            state: 'DUPLICATE',
          ).isPending,
          isFalse,
        );
      },
    );
  });
}

class _FailingStore extends LocalStore {
  _FailingStore(super.adb, {required this.failOnNth});
  final int failOnNth;
  int _n = 0;
  @override
  Future<void> enqueue(dynamic txn, OutboxOp op) {
    _n++;
    if (_n == failOnNth) {
      throw StateError('simulated disk failure while queueing');
    }
    return super.enqueue(txn, op);
  }
}
