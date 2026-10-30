// Runs the app's REAL ApiClient / SyncEngine / QaService against the REAL FastAPI backend (no fakes).
// Not part of the normal run: it needs the server. Use tool/run_backend_integration.sh (starts the backend on a temp
// database loaded from the project's synthetic datasets, runs this file, stops the server).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/core/clock.dart';
import 'package:health_companion/data/api/api_client.dart';
import 'package:health_companion/data/api/api_exceptions.dart';
import 'package:health_companion/data/local/database.dart';
import 'package:health_companion/data/local/local_store.dart';
import 'package:health_companion/data/models/outbox_op.dart';
import 'package:health_companion/data/models/household.dart';
import 'package:health_companion/data/models/referral.dart';
import 'package:health_companion/domain/safety/safety_engine.dart';
import 'package:health_companion/services/data_bus.dart';
import 'package:health_companion/services/demo_data.dart';
import 'package:health_companion/services/field_work_service.dart';
import 'package:health_companion/services/protocol_library.dart';
import 'package:health_companion/services/qa_service.dart';
import 'package:health_companion/services/sync_engine.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final url = Platform.environment['BACKEND_URL'];
const workerKey = 'it-worker-key',
    adminKey = 'it-admin-key',
    hospKey = 'it-hosp-key';
final skip = url == null
    ? 'set BACKEND_URL (use tool/run_backend_integration.sh)'
    : null;
final today = DateTime(2026, 10, 13);

class CountingClient extends http.BaseClient {
  CountingClient(this._inner);
  final http.Client _inner;
  final List<String> paths = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    paths.add('${request.method} ${request.url.path}');
    return _inner.send(request);
  }
}

Future<Map<String, dynamic>> raw(
  String method,
  String path, {
  String key = adminKey,
  Object? body,
}) async {
  final req = http.Request(method, Uri.parse('$url$path'))
    ..headers['X-API-Key'] = key;
  if (body != null) {
    req.headers['content-type'] = 'application/json';
    req.body = jsonEncode(body);
  }
  final res = await http.Response.fromStream(await http.Client().send(req));
  return {
    'status': res.statusCode,
    'json': res.body.isEmpty ? null : jsonDecode(res.body),
  };
}

void main() {
  sqfliteFfiInit();
  late AppDatabase adb;
  late LocalStore store;
  late ApiClient api;
  late SyncEngine engine;
  late FieldWorkService work;
  late CountingClient counting;
  late AppClock clock;

  Future<void> build(String key) async {
    adb = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    store = LocalStore(adb);
    clock = AppClock(now: () => DateTime(2026, 10, 13, 9), demoDate: today);
    counting = CountingClient(http.Client());
    api = ApiClient(
      client: counting,
      config: () async => ApiConfig(url!, key),
      timeout: const Duration(seconds: 20),
    );
    final bus = DataBus();
    engine = SyncEngine(
      store: store,
      api: api,
      installationId: () async => 'it-install-0001',
      clock: clock,
      onChanged: bus.changed,
    );
    work = FieldWorkService(store, clock, bus);
  }

  setUpAll(() async => build(workerKey));
  tearDownAll(() async {
    if (url != null) await adb.close();
  });

  test('server is reachable and healthy', () async {
    expect(await api.health(), isTrue);
  }, skip: skip);

  group('authentication', () {
    test(
      'a wrong key is rejected as Unauthorized (401), never as a crash',
      () async {
        final bad = ApiClient(
          client: http.Client(),
          config: () async => ApiConfig(url!, 'wrong-key'),
        );
        await expectLater(bad.pull(), throwsA(isA<Unauthorized>()));
        final none = ApiClient(
          client: http.Client(),
          config: () async => ApiConfig(url!, null),
        );
        await expectLater(none.query('hello'), throwsA(isA<Unauthorized>()));
      },
    );

    test(
      'the sync engine keeps queued data and flags the auth failure',
      () async {
        await build('wrong-key');
        await store.upsertHouseholds([_hh('HH-AUTH')], respectPending: false);
        await store.db.insert('sync_outbox', {
          'op_id': 'op-auth-0001',
          'idempotency_key': 'op-auth-0001',
          'entity_type': 'household',
          'entity_id': 'HH-AUTH',
          'op_type': 'update',
          'base_version': 1,
          'payload': '{"household_member_count":3}',
          'client_created_at': '2026-10-13T09:00:00Z',
          'state': 'PENDING',
          'attempts': 0,
        });
        final rep = await engine.syncNow();
        expect(rep.authFailed, isTrue);
        expect((await store.outboxCounts()).pending, 1);
        await adb.close();
        await build(workerKey);
      },
    );
  }, skip: skip);

  group('pull (worker-scoped data)', () {
    test('a worker key receives exactly that worker\'s synthetic records, typed and parseable', () async {
      final rep = await engine.syncNow();
      expect(rep.ok, isTrue, reason: '${rep.error}');
      final seedStore = await _seedCounts();
      expect(
        await store.countHouseholds(const HouseholdFilter()),
        seedStore.$1,
      );
      expect((await store.rowCounts())['visits'], seedStore.$2);
      expect((await store.rowCounts())['referrals'], seedStore.$3);
      final hh = await store.pageHouseholds(
        const HouseholdFilter(),
        limit: 500,
      );
      expect(hh.every((h) => h.assignedWorkerId == 'WRK-SYN-001'), isTrue);
      expect((await store.meta('last_sync_at')), isNotNull);
    });

    test(
      'the same pull again is idempotent (no duplicates, no growth)',
      () async {
        final before = await store.rowCounts();
        expect((await engine.syncNow()).ok, isTrue);
        expect(await store.rowCounts(), before);
      },
    );

    test('derived dashboard figures from pulled data equal those from the bundled demo seed (same ids, versions, rules)', () async {
      final seedAdb = await AppDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      final seedStore = LocalStore(seedAdb);
      await DemoData(
        seedStore,
        loader: () => File('assets/demo/demo_seed.json').readAsString(),
      ).load();
      final a = await store.dashboard(today),
          b = await seedStore.dashboard(today);
      expect(
        (a.dueToday, a.overdue, a.upcoming, a.pendingReferrals),
        (b.dueToday, b.overdue, b.upcoming, b.pendingReferrals),
      );
      await seedAdb.close();
    });
  }, skip: skip);

  group('offline work -> sync (real server rules)', () {
    late String visitId, householdId;
    test('record a visit with a follow-up and a referral offline, then sync: all three operations acknowledged', () async {
      final v = (await store.plannedVisits(
        'today',
        today,
        limit: 1,
      )).first.visit;
      visitId = v.visitId;
      householdId = v.householdId;
      await work.recordOutcome(
        visitId,
        VisitOutcome(
          status: 'COMPLETED',
          actualDate: today,
          followupRequired: true,
          nextFollowupDate: DateTime(2026, 11, 12),
          referral: const ReferralDraft(
            facilityId: 'FAC-SYN-01',
            serviceCategory: 'GENERAL',
          ),
        ),
      );
      expect((await store.outboxCounts()).pending, 3);
      final rep = await engine.syncNow();
      expect(rep.ok, isTrue, reason: '${rep.error}');
      expect(
        (rep.acknowledged, rep.conflicts, rep.rejected, rep.retryable),
        (3, 0, 0, 0),
      );
      final c = await store.outboxCounts();
      expect((c.pending, c.needsAttention), (0, 0));
    });

    test('the server really stored them (checked with an independent admin request)', () async {
      final r = await raw(
        'GET',
        '/api/v1/visits?household_id=$householdId&limit=200',
      );
      final items = (r['json']['items'] as List).cast<Map<String, dynamic>>();
      expect(
        items.firstWhere((x) => x['visit_id'] == visitId)['visit_status'],
        'COMPLETED',
      );
      expect(
        items.where(
          (x) =>
              x['visit_status'] == 'PLANNED' &&
              x['scheduled_date'] == '2026-11-12',
        ),
        isNotEmpty,
      );
      final refs =
          (await raw(
                'GET',
                '/api/v1/referrals?household_id=$householdId&limit=200',
              ))['json']['items']
              as List;
      final mine = refs.cast<Map<String, dynamic>>().firstWhere(
        (x) => x['visit_id'] == visitId,
      );
      expect(mine['referral_status'], 'RECOMMENDED');
      expect(mine['attendance_confirmed'], false);
      expect(mine['status_label'], contains('NOT confirmed'));
    });

    test('resending the same operations is idempotent: the server answers duplicate=true and nothing doubles', () async {
      final ops = await store.ops(state: OpState.acknowledged, limit: 10);
      expect(ops, isNotEmpty);
      final before = (await raw(
        'GET',
        '/api/v1/visits?household_id=$householdId&limit=200',
      ))['json']['total'];
      final res = await api.push('it-install-0001', [
        for (final o in ops) o.toWire(),
      ]);
      expect(res.results.every((r) => r.duplicate && r.acknowledged), isTrue);
      expect(
        (await raw(
          'GET',
          '/api/v1/visits?household_id=$householdId&limit=200',
        ))['json']['total'],
        before,
      );
    });

    test('after a pull the local rows adopt the server versions (client optimistic numbers match the server)', () async {
      await engine.syncNow();
      final local = (await store.visit(visitId))!;
      final server = (await raw(
        'GET',
        '/api/v1/visits?household_id=$householdId&limit=200',
      ))['json']['items'].firstWhere((x) => x['visit_id'] == visitId);
      expect(local.version, server['version']);
      expect(local.referralStatus, server['referral_status']);
      final h = (await store.household(householdId))!;
      final sh = (await raw('GET', '/api/v1/households/$householdId'))['json'];
      expect(
        (
          h.recordStatus,
          h.nextVisitDueDate?.toIso8601String().substring(0, 10),
        ),
        (sh['record_status'], sh['next_visit_due_date']),
      );
    });
  }, skip: skip);

  group('conflict handling against the real server', () {
    test('a stale update to a protected field is NOT applied; the user keeps the server version; confirmed only appears with its hospital record', () async {
      final r = (await store.pageReferrals('planned', limit: 200)).firstWhere(
        (x) =>
            x.status == 'PLANNED' &&
            x.plannedVisitDate != null &&
            !x.plannedVisitDate!.isAfter(today) &&
            x.version == 1,
      );
      // 1) the hospital/admin confirms attendance on the server (a different actor)
      final conf = await raw(
        'PATCH',
        '/api/v1/referrals/${r.referralId}',
        key: hospKey,
        body: {
          'referral_status': 'ATTENDANCE_CONFIRMED',
          'attendance_record_id': 'ATT-IT-0001',
          'attendance_confirmation_date': '2026-10-13',
        },
      );
      expect(conf['status'], 200);
      // 2) meanwhile the worker (offline, stale) changes the planned date
      await work.planReferral(
        r.referralId,
        today.add(const Duration(days: 20)),
      );
      final rep = await engine.syncNow(pull: false);
      expect(rep.conflicts, 1);
      final op = (await store.ops(state: OpState.conflict)).single;
      expect(
        op.conflict!['server_values'],
        containsPair('planned_visit_date', isNotNull),
      );
      expect(op.conflict!['resolution'], 'NOT_APPLIED_FLAGGED_FOR_REVIEW');
      final serverNow = (await raw(
        'GET',
        '/api/v1/referrals?household_id=${r.householdId}&limit=200',
      ))['json']['items'].firstWhere((x) => x['referral_id'] == r.referralId);
      expect(serverNow['referral_status'], 'ATTENDANCE_CONFIRMED');
      expect(
        serverNow['planned_visit_date'],
        isNot(
          today
              .add(const Duration(days: 20))
              .toIso8601String()
              .substring(0, 10),
        ),
        reason: 'stale change was not applied',
      );
      // 3) user chooses the server's version
      await engine.resolveConflict(op.opId, keepServer: true);
      expect((await store.outboxCounts()).conflict, 0);
      // local row must NOT claim attendance until the real record arrives with the pull
      expect(
        (await store.referral(r.referralId))!.phase,
        isNot(ReferralPhase.attendanceConfirmed),
      );
      await engine.syncNow();
      final after = (await store.referral(r.referralId))!;
      expect(
        (after.phase, after.attendanceRecordId),
        (ReferralPhase.attendanceConfirmed, 'ATT-IT-0001'),
      );
    });

    test('a worker key can never set ATTENDANCE_CONFIRMED: the server rejects it and the app shows it as rejected, not synced', () async {
      final r = (await store.pageReferrals('planned', limit: 200)).firstWhere(
        (x) =>
            x.status == 'PLANNED' &&
            x.plannedVisitDate != null &&
            !x.plannedVisitDate!.isAfter(today),
      );
      final res = await api.push('it-install-0001', [
        {
          'op_id': 'op-forbidden-0001',
          'entity_type': 'referral',
          'entity_id': r.referralId,
          'op_type': 'update',
          'base_version': r.version,
          'payload': {
            'referral_status': 'ATTENDANCE_CONFIRMED',
            'attendance_record_id': 'ATT-FAKE-1',
            'attendance_confirmation_date': '2026-10-13',
          },
        },
      ]);
      expect(res.results.single.status, 'REJECTED');
      expect(res.results.single.acknowledged, isFalse);
    });

    test('malformed operations are rejected individually without blocking valid ones', () async {
      final res = await api.push('it-install-0001', [
        {'op_id': 'bad', 'entity_type': 'nonsense'},
      ]);
      expect(res.results.single.status, 'REJECTED');
      expect(res.results.single.errorCode, 'MALFORMED_OPERATION');
    });
  }, skip: skip);

  group(
    'health Q&A with the real safety engine and an EMPTY protocol corpus',
    () {
      late QaService qa;
      setUp(() {
        final engineSafety = SafetyEngine.fromJsonString(
          File('assets/safety/danger_rules.json').readAsStringSync(),
        );
        qa = QaService(
          engine: engineSafety,
          api: api,
          loadIndex: () => ProtocolLibrary(store, api).loadIndex(),
        );
      });

      test('a normal clinical question -> INSUFFICIENT_EVIDENCE from the server (no invented answer)', () async {
        final r = await qa.ask(
          'How many antenatal check-ups should a pregnant woman have?',
        );
        expect(r.outcome, QaOutcome.insufficientEvidence);
        expect(r.evidence, isEmpty);
        expect(r.fromDevice, isFalse);
      });

      test('a danger sign is escalated ON THE DEVICE and the server is never contacted', () async {
        counting.paths.clear();
        final r = await qa.ask('Pregnant woman is bleeding heavily right now');
        expect(r.outcome, QaOutcome.escalationRequired);
        expect(r.clinicallyValidated, isFalse);
        expect(counting.paths.where((p) => p.contains('health-qa')), isEmpty);
      });

      test('dosage request is refused on the device', () async {
        expect(
          (await qa.ask('What dose of amoxicillin should I give a child?'))
              .outcome,
          QaOutcome.outOfScope,
        );
      });

      test("the server's own answer to an escalation question agrees with the device (same ruleset)", () async {
        final s = await api.query(
          'Pregnant woman is bleeding heavily right now',
        );
        expect(s.outcome, 'ESCALATION_REQUIRED');
        expect(s.safety.ruleIds, contains('DSR-BLEEDING-SEVERE'));
        expect(s.safety.clinicallyValidated, isFalse);
        expect(s.answerText, isNull);
      });

      test('protocol library: nothing is approved on the server yet, so nothing is stored on the device', () async {
        expect(await ProtocolLibrary(store, api).refreshFromServer(), 0);
        expect(await ProtocolLibrary(store, api).approvedPassageCount(), 0);
      });
    },
    skip: skip,
  );

  group('reports from the real server', () {
    test('typed summary + real CSV and PDF files', () async {
      final fac = (await store.facilities()).first;
      final rep = await api.reportSummary(
        facilityId: fac,
        periodStart: '2026-01-01',
        periodEnd: '2026-10-13',
        lastSyncAt: await store.meta('last_sync_at'),
      );
      expect(
        rep.total,
        rep.recommended + rep.planned + rep.attendanceConfirmed,
      );
      expect(rep.byCategory.values.fold<int>(0, (a, b) => a + b), rep.total);
      expect(rep.privacyNotice.toLowerCase(), contains('aggregate'));
      final csv = utf8.decode(await api.reportFile(rep.reportId, 'csv'));
      expect(csv, contains('facility_id,$fac'));
      final pdf = await api.reportFile(rep.reportId, 'pdf');
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(csv.contains('HH-SYN'), isFalse);
    });

    test('a worker cannot read another scope\'s report', () async {
      final adminReport = (await raw(
        'POST',
        '/api/v1/reports/summary',
        body: {
          'facility_id': 'FAC-SYN-01',
          'period_start': '2026-01-01',
          'period_end': '2026-10-13',
        },
      ))['json'];
      final r = await raw(
        'GET',
        '/api/v1/reports/${adminReport['report_id']}',
        key: workerKey,
      );
      expect(r['status'], 404);
    });
  }, skip: skip);
}

Household _hh(String id) => Household(
  householdId: id,
  villageId: 'V',
  assignedWorkerId: 'WRK-SYN-001',
  memberCount: 4,
  eligibleCategories: const ['ROUTINE'],
  recordStatus: 'NO_VISIT_DUE',
  lastUpdated: '2026-10-01T10:00:00Z',
  version: 1,
);

Future<(int, int, int)> _seedCounts() async {
  final j = jsonDecode(
    File('assets/demo/demo_seed.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return (
    (j['households'] as List).length,
    (j['visits'] as List).length,
    (j['referrals'] as List).length,
  );
}
