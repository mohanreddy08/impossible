import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/data/api/api_exceptions.dart';
import 'package:health_companion/data/models/outbox_op.dart';
import 'package:health_companion/services/field_work_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/builders.dart';
import 'support/fake_server.dart';
import 'support/harness.dart';

Future<void> completeVisit(
  Rig rig, {
  bool next = true,
  bool referral = false,
}) => rig.fieldWork.recordOutcome(
  'VIS-1',
  VisitOutcome(
    status: 'COMPLETED',
    actualDate: today,
    followupRequired: next,
    nextFollowupDate: next ? DateTime(2026, 11, 12) : null,
    referral: referral
        ? const ReferralDraft(facilityId: 'FAC-9', serviceCategory: 'ANC')
        : null,
  ),
);

void main() {
  pullOverlapTests();
  sqfliteFfiInit();
  late Rig rig;
  setUp(() async {
    rig = await Rig.create();
    await rig.seedBasic();
  });
  tearDown(() => rig.dispose());

  test('operations are marked synced ONLY after the server acknowledges them, and versions adopt the server number', () async {
    await completeVisit(rig);
    expect((await rig.store.outboxCounts()).pending, 2);
    final rep = await rig.engine.syncNow(pull: false);
    expect(rep.ok, isTrue);
    expect((rep.sent, rep.acknowledged), (2, 2));
    final c = await rig.store.outboxCounts();
    expect((c.pending, c.synced, c.needsAttention), (0, 2, 0));
    expect(
      (await rig.store.visit('VIS-1'))!.version,
      2,
    ); // fake server: base 1 -> 2
    expect(rig.server.applied.length, 2);
    expect(await rig.store.meta('last_sync_at'), isNotNull);
    expect(rig.server.requestHeaders.first['X-API-Key'], 'test-key');
  });

  group('network failure never loses or duplicates data', () {
    test('offline: changes stay pending with a plain-language reason, local data untouched', () async {
      await completeVisit(rig);
      rig.server.down = true;
      final rep = await rig.engine.syncNow(pull: false);
      expect(rep.offline, isTrue);
      expect(rep.ok, isFalse);
      final ops = await rig.store.ops(state: OpState.pending);
      expect(ops.length, 2);
      expect(
        ops.every(
          (o) =>
              o.attempts == 1 &&
              o.lastErrorCode == 'NETWORK' &&
              (o.lastErrorMessage ?? '').contains('saved'),
        ),
        isTrue,
      );
      expect((await rig.store.visit('VIS-1'))!.status, 'COMPLETED');
      expect(
        await rig.store.meta('last_sync_at'),
        isNull,
        reason: 'a failed sync must not look like a successful one',
      );
      expect(rig.server.applied, isEmpty);
    });

    test('lost RESPONSE (server processed it, client never heard): resend does not create duplicates', () async {
      await completeVisit(rig);
      rig.server.dropResponses = true;
      final first = await rig.engine.syncNow(pull: false);
      expect(first.offline, isTrue);
      expect(
        (await rig.store.outboxCounts()).pending,
        2,
        reason: 'client cannot know -> still pending',
      );
      expect(
        rig.server.applied.length,
        2,
        reason: 'server really did process them',
      );

      rig.server.dropResponses = false;
      final second = await rig.engine.syncNow(pull: false);
      expect(second.ok, isTrue);
      expect(
        rig.server.applied.length,
        2,
        reason: 'no second application of the same op_id',
      );
      expect((await rig.store.outboxCounts()).synced, 2);
    });

    test(
      'app restart between failure and retry still sends exactly once',
      () async {
        final path = await tempDbPath();
        final server = FakeServer();
        var r = await Rig.create(dbPath: path, server: server);
        await r.seedBasic();
        await completeVisit(r);
        server.down = true;
        await r.engine.syncNow(pull: false);
        await r.dispose();
        server.down = false;
        r = await Rig.create(dbPath: path, server: server);
        expect((await r.engine.syncNow(pull: false)).ok, isTrue);
        expect(server.applied.length, 2);
        await r.dispose();
      },
    );

    test(
      'the same op ids are used on every retry (stable idempotency)',
      () async {
        await completeVisit(rig);
        final ids = (await rig.store.ops()).map((o) => o.opId).toList();
        rig.server.down = true;
        await rig.engine.syncNow(pull: false);
        rig.server.down = false;
        await rig.engine.syncNow(pull: false);
        expect(rig.server.seenOps.keys.toSet(), ids.toSet());
      },
    );

    test('timeouts and 5xx keep data pending', () async {
      await completeVisit(rig, next: false);
      rig.server.httpStatus = 503;
      final r1 = await rig.engine.syncNow(pull: false);
      expect(r1.error, isA<ServerError>());
      expect((await rig.store.outboxCounts()).pending, 1);
      rig.server.httpStatus = 200;
      expect((await rig.engine.syncNow(pull: false)).ok, isTrue);
    });
  });

  test('FAILED_RETRYABLE from the server is not treated as success', () async {
    await completeVisit(rig, next: false);
    final id = (await rig.store.ops()).single.opId;
    rig.server.forceResult[id] = {
      'status': 'FAILED_RETRYABLE',
      'acknowledged': false,
      'error_code': 'TEMPORARY_FAILURE',
      'error_message': 'operation was not stored; resend it',
    };
    final rep = await rig.engine.syncNow(pull: false);
    expect(rep.retryable, 1);
    final op = (await rig.store.op(id))!;
    expect(op.state, OpState.pending);
    expect(op.attempts, 1);
    rig.server.forceResult.clear();
    expect((await rig.engine.syncNow(pull: false)).acknowledged, 1);
  });

  group('rejected operations', () {
    test(
      'are kept with the server reason, can be retried and then succeed',
      () async {
        await completeVisit(rig, next: false);
        final id = (await rig.store.ops()).single.opId;
        rig.server.forceResult[id] = {
          'status': 'REJECTED',
          'acknowledged': false,
          'error_code': 'NOT_FOUND',
          'error_message': 'household not found',
        };
        final rep = await rig.engine.syncNow(pull: false);
        expect(rep.rejected, 1);
        var op = (await rig.store.op(id))!;
        expect(
          (op.state, op.lastErrorCode, op.lastErrorMessage),
          (OpState.rejected, 'NOT_FOUND', 'household not found'),
        );
        expect((await rig.store.outboxCounts()).failed, 1);
        expect(
          (await rig.store.visit('VIS-1'))!.status,
          'COMPLETED',
          reason: 'local work is preserved',
        );

        rig.server.forceResult.clear();
        await rig.engine.retry(id);
        expect((await rig.store.op(id))!.state, OpState.pending);
        expect((await rig.engine.syncNow(pull: false)).acknowledged, 1);
      },
    );

    test(
      'discarding an update restores the saved snapshot and the household',
      () async {
        await completeVisit(rig);
        final upd = (await rig.store.ops()).firstWhere(
          (o) => o.opType == 'update',
        );
        await rig.engine.discard(upd.opId);
        expect((await rig.store.visit('VIS-1'))!.status, 'PLANNED');
        expect((await rig.store.op(upd.opId)), isNull);
        expect(
          (await rig.store.household('HH-1'))!.nextVisitDueDate,
          isNotNull,
        );
      },
    );
  });

  group('conflicts', () {
    Future<String> makeReferralConflict() async {
      await rig.store.upsertVisits([
        vis(
          'VIS-3',
          'HH-1',
          DateTime(2026, 9, 12),
          status: 'COMPLETED',
          actual: DateTime(2026, 9, 12),
        ),
      ], respectPending: false);
      await rig.store.upsertReferrals([
        ref('REF-X', 'HH-1', 'VIS-3', status: 'RECOMMENDED'),
      ], respectPending: false);
      await rig.fieldWork.planReferral('REF-X', DateTime(2026, 10, 20));
      final id = (await rig.store.ops()).single.opId;
      rig.server.forceResult[id] = conflictResult(
        id,
        serverVersion: 3,
        server: {'referral_status': 'ATTENDANCE_CONFIRMED'},
        client: {'referral_status': 'PLANNED'},
      );
      return id;
    }

    test(
      'a conflict is shown, nothing is overwritten and nothing is acknowledged',
      () async {
        final id = await makeReferralConflict();
        final rep = await rig.engine.syncNow(pull: false);
        expect(rep.conflicts, 1);
        final op = (await rig.store.op(id))!;
        expect(op.state, OpState.conflict);
        expect(op.conflict!['server_values'], {
          'referral_status': 'ATTENDANCE_CONFIRMED',
        });
        expect(op.conflict!['client_values'], {'referral_status': 'PLANNED'});
        expect(
          (await rig.store.referral('REF-X'))!.status,
          'PLANNED',
          reason: 'local edit untouched until the user decides',
        );
        expect((await rig.store.outboxCounts()).conflict, 1);
      },
    );

    test('a pull never overwrites a record that has an unsynced or conflicting local change', () async {
      await makeReferralConflict();
      await rig.engine.syncNow(pull: false);
      rig.server.pullData['referrals'] = [
        {
          'referral_id': 'REF-X',
          'household_id': 'HH-1',
          'visit_id': 'VIS-3',
          'facility_id': 'FAC-1',
          'service_category': 'GENERAL',
          'referral_created_date': '2026-09-01',
          'planned_visit_date': null,
          'referral_status': 'RECOMMENDED',
          'attendance_confirmed': false,
          'attendance_confirmation_date': null,
          'attendance_record_id': null,
          'record_state': 'ACTIVE',
          'duplicate_of': null,
          'last_updated': '2026-10-13T08:00:00',
          'version': 9,
          'synthetic_record': true,
        },
      ];
      final rep = await rig.engine.syncNow();
      expect(rep.ok, isTrue);
      expect((await rig.store.referral('REF-X'))!.status, 'PLANNED');
      expect((await rig.store.referral('REF-X'))!.version, 2);
    });

    test('keep server: local record adopts the server values and version, the op is removed', () async {
      final id = await makeReferralConflict();
      await rig.engine.syncNow(pull: false);
      await rig.engine.resolveConflict(id, keepServer: true);
      final r = (await rig.store.referral('REF-X'))!;
      expect(r.status, 'ATTENDANCE_CONFIRMED');
      expect(r.version, 3);
      expect(await rig.store.op(id), isNull);
      expect((await rig.store.outboxCounts()).conflict, 0);
    });

    test(
      'keep mine: re-queued as a NEW op based on the server version',
      () async {
        final id = await makeReferralConflict();
        await rig.engine.syncNow(pull: false);
        rig.server.forceResult.clear();
        await rig.engine.resolveConflict(id, keepServer: false);
        expect(await rig.store.op(id), isNull);
        final fresh = (await rig.store.ops()).single;
        expect(fresh.opId, isNot(id));
        expect(
          (fresh.state, fresh.baseVersion, fresh.payload['referral_status']),
          (OpState.pending, 3, 'PLANNED'),
        );
        expect((await rig.engine.syncNow(pull: false)).acknowledged, 1);
      },
    );
  });

  group('credentials and configuration', () {
    test(
      '401 stops the cycle, flags auth failure and keeps everything pending',
      () async {
        await completeVisit(rig, next: false);
        rig.server.httpStatus = 401;
        final rep = await rig.engine.syncNow();
        expect(rep.authFailed, isTrue);
        expect(rep.error, isA<Unauthorized>());
        expect((await rig.store.outboxCounts()).pending, 1);
      },
    );

    test('no server address: reported, data safe', () async {
      final r = await Rig.create(configured: false);
      await r.seedBasic();
      await r.fieldWork.recordOutcome(
        'VIS-1',
        VisitOutcome(
          status: 'COMPLETED',
          actualDate: today,
          followupRequired: false,
        ),
      );
      final rep = await r.engine.syncNow();
      expect(rep.notConfigured, isTrue);
      expect((await r.store.outboxCounts()).pending, 1);
      await r.dispose();
    });
  });

  test('duplicate referral flagged by the server is shown as a duplicate, not as a live referral', () async {
    await completeVisit(rig, next: false, referral: true);
    final refOp = (await rig.store.ops()).firstWhere(
      (o) => o.entityType == 'referral',
    );
    rig.server.forceResult[refOp.opId] = {
      'status': 'ACKNOWLEDGED',
      'acknowledged': true,
      'server_version': 1,
      'warnings': ['DUPLICATE_FLAGGED:duplicate_of=REF-OTHER'],
    };
    await rig.engine.syncNow(pull: false);
    final r = (await rig.store.referral(refOp.entityId))!;
    expect((r.recordState, r.duplicateOf), ('DUPLICATE', 'REF-OTHER'));
    expect((await rig.store.visit('VIS-1'))!.referralId, isNull);
  });

  test(
    'a second sync while one is running is refused instead of double-sending',
    () async {
      await completeVisit(rig);
      final a = rig.engine.syncNow(pull: false);
      final b = await rig.engine.syncNow(pull: false);
      expect(b.alreadyRunning, isTrue);
      await a;
      expect(rig.server.applied.length, 2);
    },
  );

  test('pull merges server records and remembers its cursor', () async {
    rig.server.pullData['households'] = [
      {
        'household_id': 'HH-NEW',
        'village_id': 'VIL-2',
        'assigned_worker_id': 'WRK-1',
        'household_member_count': 3,
        'eligible_followup_categories': ['ANC'],
        'last_visit_date': null,
        'next_visit_due_date': null,
        'scheduled_followup_category': null,
        'record_status': 'NO_VISIT_DUE',
        'last_updated': '2026-10-13T07:30:00',
        'version': 4,
        'synthetic_record': true,
      },
    ];
    final rep = await rig.engine.syncNow();
    expect(rep.pulled, 1);
    expect((await rig.store.household('HH-NEW'))!.version, 4);
    expect(await rig.store.meta('cursor_household'), '2026-10-13T07:30:00');
    expect(
      rig.server.requestPaths.where((p) => p.contains('/sync/pull')).length,
      3,
      reason: 'one request per entity type',
    );
  });

  test('ordering: creates are sent after the update on the same visit and a parent before its children', () async {
    await completeVisit(rig, referral: true);
    await rig.engine.syncNow(pull: false);
    final order = rig.server.applied
        .map((o) => '${o['entity_type']}:${o['op_type']}')
        .toList();
    expect(order, ['visit:update', 'visit:create', 'referral:create']);
  });
}

void pullOverlapTests() {
  sqfliteFfiInit();
  test('pull re-requests with a 1-second overlap so same-second server changes are never missed', () async {
    final rig = await Rig.create();
    await rig.store.setMeta('cursor_household', '2026-10-13T17:42:00');
    await rig.engine.syncNow();
    expect(rig.server.pullSince.first, '2026-10-13T17:41:59');
    await rig.dispose();
  });

  test('a different login or server means the saved sync position is dropped (full pull)', () async {
    final rig = await Rig.create();
    await rig.store.setMeta('cursor_visit', '2026-10-13T17:42:00');
    await rig.store.setMeta('pull_identity', 'someone-else');
    await rig.engine.syncNow();
    expect(
      rig.server.pullSince.first,
      isNull,
      reason: 'cursor must be reset so older data is pulled too',
    );
    await rig.dispose();
  });

  test('the same login keeps its saved sync position', () async {
    final rig = await Rig.create();
    await rig.engine.syncNow(); // records which login this phone syncs with
    rig.server.pullSince.clear();
    await rig.store.setMeta('cursor_household', '2026-10-13T17:42:00');
    await rig.engine.syncNow();
    expect(rig.server.pullSince.first, '2026-10-13T17:41:59');
    await rig.dispose();
  });

  test('a record whose visit is missing resets the sync position, and the next sync repairs everything', () async {
    final rig = await Rig.create();
    await rig.store.wipe();
    await rig.engine.syncNow(); // records the login
    await rig.store.setMeta('cursor_household', '2026-10-13T17:42:00');
    rig.server.pullData = {
      'households': [],
      'visits': [],
      'referrals': [
        {
          'referral_id': 'REF-X',
          'household_id': 'HH-X',
          'visit_id': 'VIS-MISSING',
          'facility_id': 'FAC-1',
          'service_category': 'GENERAL',
          'referral_created_date': '2026-10-01',
          'planned_visit_date': null,
          'referral_status': 'RECOMMENDED',
          'attendance_confirmed': false,
          'attendance_confirmation_date': null,
          'attendance_record_id': null,
          'record_state': 'ACTIVE',
          'duplicate_of': null,
          'last_updated': '2026-10-13T08:00:00',
          'version': 1,
        },
      ],
    };
    final rep = await rig.engine.syncNow(); // must not throw
    expect(rep.retryable, greaterThan(0));
    expect(
      await rig.store.meta('cursor_household'),
      isNull,
      reason: 'position forgotten so the next sync pulls everything',
    );
    await rig.dispose();
  });
}
