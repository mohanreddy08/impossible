import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/data/local/database.dart';
import 'package:health_companion/data/local/local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/builders.dart';
import 'support/harness.dart';

void main() {
  sqfliteFfiInit();

  test(
    'fresh database is created at the current schema version with all tables',
    () async {
      final adb = await openTestDb();
      expect(await adb.db.getVersion(), AppDatabase.schemaVersion);
      final tables = (await adb.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name']).toSet();
      expect(
        tables,
        containsAll([
          'households',
          'visits',
          'referrals',
          'protocol_documents',
          'protocol_passages',
          'sync_outbox',
          'app_meta',
        ]),
      );
      final cols = (await adb.db.rawQuery('PRAGMA table_info(sync_outbox)'))
          .map((r) => r['name'])
          .toSet();
      expect(cols, contains('last_attempt_at')); // added by migration v2
      await adb.close();
    },
  );

  test(
    'migration v1 -> v2 preserves existing rows and adds the v2 schema',
    () async {
      final path = await tempDbPath();
      final v1 = await openTestDb(path: path, target: 1);
      expect(await v1.db.getVersion(), 1);
      expect(
        (await v1.db.rawQuery('PRAGMA table_info(sync_outbox)'))
            .map((r) => r['name']),
        isNot(contains('last_attempt_at')),
      );
      final s1 = LocalStore(v1);
      await s1.upsertHouseholds([hh('HH-A')], respectPending: false);
      await v1.db.insert('sync_outbox', {
        'op_id': 'op-keep-0001',
        'idempotency_key': 'op-keep-0001',
        'entity_type': 'household',
        'entity_id': 'HH-A',
        'op_type': 'update',
        'payload': '{"household_member_count":5}',
        'client_created_at': '2026-10-13T09:00:00Z',
        'state': 'PENDING',
        'attempts': 0,
      });
      await v1.close();

      final v2 = await openTestDb(
        path: path,
      ); // reopen at current version -> onUpgrade
      expect(await v2.db.getVersion(), AppDatabase.schemaVersion);
      final s2 = LocalStore(v2);
      expect((await s2.household('HH-A'))!.memberCount, 4);
      final op = await s2.op('op-keep-0001');
      expect(op, isNotNull);
      expect(op!.payload['household_member_count'], 5);
      expect(op.lastAttemptAt, isNull);
      await s2.updateOp('op-keep-0001', {
        'last_attempt_at': '2026-10-13T09:05:00Z',
      });
      expect(
        (await s2.op('op-keep-0001'))!.lastAttemptAt,
        '2026-10-13T09:05:00Z',
      );
      final idx = (await v2.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      )).map((r) => r['name']).toSet();
      expect(
        idx,
        containsAll([
          'ix_outbox_state',
          'ix_outbox_entity',
          'ix_visits_household',
        ]),
      );
      await v2.close();
    },
  );

  test(
    'data survives closing and reopening the database (app restart)',
    () async {
      final path = await tempDbPath();
      var adb = await openTestDb(path: path);
      await LocalStore(adb)
          .upsertHouseholds([hh('HH-R1'), hh('HH-R2')], respectPending: false);
      await adb.close();
      adb = await openTestDb(path: path);
      expect(await LocalStore(adb).countHouseholds(const HouseholdFilter()), 2);
      await adb.close();
    },
  );

  test('foreign keys and CHECK constraints are enforced', () async {
    final adb = await openTestDb();
    final store = LocalStore(adb);
    expect(
      () => store.upsertVisits([
        vis('V-X', 'NO-SUCH-HH', today),
      ], respectPending: false),
      throwsA(isA<Exception>()),
    );
    expect(
      () => adb.db.insert('households', {
        ...hh('HH-BAD').toRow(),
        'record_status': 'NONSENSE',
      }),
      throwsA(isA<Exception>()),
    );
    await adb.close();
  });

  group('paged queries', () {
    late AppDatabase adb;
    late LocalStore store;
    setUp(() async {
      adb = await openTestDb();
      store = LocalStore(adb);
      await store.upsertHouseholds([
        for (var i = 0; i < 95; i++)
          hh(
            'HH-${i.toString().padLeft(3, '0')}',
            status: i < 10
                ? 'OVERDUE'
                : i < 20
                ? 'DUE_TODAY'
                : 'NO_VISIT_DUE',
            village: i.isEven ? 'VIL-A' : 'VIL-B',
            cats: i % 3 == 0 ? ['ANC', 'ROUTINE'] : ['ROUTINE'],
          ),
      ], respectPending: false);
    });
    tearDown(() => adb.close());

    test('limit/offset return pages without loading everything', () async {
      final p1 = await store.pageHouseholds(const HouseholdFilter(), limit: 30);
      final p2 = await store.pageHouseholds(
        const HouseholdFilter(),
        limit: 30,
        offset: 30,
      );
      final p4 = await store.pageHouseholds(
        const HouseholdFilter(),
        limit: 30,
        offset: 90,
      );
      expect((p1.length, p2.length, p4.length), (30, 30, 5));
      expect(
        {
          ...p1.map((e) => e.householdId),
          ...p2.map((e) => e.householdId),
        }.length,
        60,
      );
      expect(await store.countHouseholds(const HouseholdFilter()), 95);
    });

    test('overdue first, then due today, then the rest', () async {
      final p = await store.pageHouseholds(const HouseholdFilter(), limit: 25);
      expect(p.take(10).every((h) => h.recordStatus == 'OVERDUE'), isTrue);
      expect(
        p.skip(10).take(10).every((h) => h.recordStatus == 'DUE_TODAY'),
        isTrue,
      );
    });

    test('search, status, category and village filters combine', () async {
      expect(
        await store.countHouseholds(const HouseholdFilter(search: 'HH-01')),
        10,
      );
      expect(
        await store.countHouseholds(const HouseholdFilter(status: 'OVERDUE')),
        10,
      );
      expect(
        (await store.pageHouseholds(
          const HouseholdFilter(category: 'ANC'),
          limit: 200,
        )).every((h) => h.eligibleCategories.contains('ANC')),
        isTrue,
      );
      expect(
        await store.countHouseholds(
          const HouseholdFilter(village: 'VIL-A', status: 'NO_VISIT_DUE'),
        ),
        greaterThan(0),
      );
      expect(
        await store.countHouseholds(const HouseholdFilter(search: '%')),
        95,
        reason: 'wildcards in user input are neutralised, not treated as match-all patterns that bypass paging',
      );
      expect(
        await store.countHouseholds(const HouseholdFilter(search: 'HH_0')),
        0,
        reason: 'underscore must not act as a single-char wildcard',
      );
    });
  });
}
