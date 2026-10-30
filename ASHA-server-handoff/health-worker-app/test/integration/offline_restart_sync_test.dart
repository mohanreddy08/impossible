// Offline -> app restart -> reconnect, against the REAL FastAPI backend (no fakes on the server side).
// Run with tool/run_backend_integration.sh (it starts the backend on a temporary database and sets BACKEND_URL).
//
// The sequence follows the offline-first acceptance steps:
//   1. start online once (pull this worker's records), then lose the network
//   2. record a visit outcome with a follow-up and a referral while offline
//   3. close and reopen the database file (what an app restart does) - both records and the queue are still there
//   4. pending-sync count is unchanged by the restart
//   5. reconnect, but the server's answer is lost on the way back (bad 2G): nothing is marked synced
//   6. sync again: every operation acknowledged (the server recognises the resend as duplicates), queue empty
//   7. the server holds exactly one copy of each record
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/core/clock.dart';
import 'package:health_companion/data/api/api_client.dart';
import 'package:health_companion/data/local/database.dart';
import 'package:health_companion/data/local/local_store.dart';
import 'package:health_companion/services/data_bus.dart';
import 'package:health_companion/services/field_work_service.dart';
import 'package:health_companion/services/sync_engine.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final url = Platform.environment['BACKEND_URL'];
const workerKey = 'it-worker-key', adminKey = 'it-admin-key';
final skip = url == null
    ? 'set BACKEND_URL (use tool/run_backend_integration.sh)'
    : null;
final today = DateTime(2026, 10, 13);

/// Talks to the real server, but can (a) be cut off completely or (b) let one push reach the server and then lose the reply.
class FlakyNetwork extends http.BaseClient {
  final http.Client _inner = http.Client();
  bool down = false;
  bool loseNextPushReply = false;
  final List<String> paths = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    paths.add('${request.method} ${request.url.path}');
    if (down) throw http.ClientException('network unreachable (simulated)');
    final res = await _inner.send(request);
    if (loseNextPushReply && request.url.path.endsWith('/sync/push')) {
      loseNextPushReply = false;
      await res.stream
          .drain<void>(); // the server has processed and committed it
      throw http.ClientException(
        'connection dropped before the reply arrived (simulated)',
      );
    }
    return res;
  }
}

Future<Map<String, dynamic>> admin(String path) async {
  final r = await http.get(
    Uri.parse('$url$path'),
    headers: {'X-API-Key': adminKey},
  );
  return jsonDecode(r.body) as Map<String, dynamic>;
}

void main() {
  sqfliteFfiInit();
  final dir = Directory.systemTemp.createTempSync('asha_restart_');
  final dbPath = '${dir.path}/app.db';
  final net = FlakyNetwork();
  late AppDatabase adb;
  late LocalStore store;
  late SyncEngine engine;
  late FieldWorkService work;
  late String visitId, householdId;

  Future<void> openApp() async {
    adb = await AppDatabase.open(
      path: dbPath,
      factory: databaseFactoryFfi,
      singleInstance: true,
    );
    store = LocalStore(adb);
    final clock = AppClock(
      now: () => DateTime(2026, 10, 13, 9),
      demoDate: today,
    );
    final bus = DataBus();
    engine = SyncEngine(
      store: store,
      api: ApiClient(
        client: net,
        config: () async => ApiConfig(url!, workerKey),
        timeout: const Duration(seconds: 20),
      ),
      installationId: () async => 'it-restart-install-0001',
      clock: clock,
      onChanged: bus.changed,
    );
    work = FieldWorkService(store, clock, bus);
  }

  tearDownAll(() async {
    if (url != null) await adb.close();
    dir.deleteSync(recursive: true);
  });

  test('1. first start online: this worker\'s records are pulled into the phone database', () async {
    await openApp();
    final rep = await engine.syncNow();
    expect(rep.ok, isTrue, reason: '${rep.error}');
    expect(rep.pulled, greaterThan(0));
  }, skip: skip);

  test('2. offline: a visit outcome with follow-up and a referral is saved locally and queued', () async {
    net.down = true;
    // an upcoming visit, so this file does not touch the records the other integration file uses
    final v = (await store.plannedVisits(
      'upcoming',
      today,
      limit: 50,
    )).last.visit;
    visitId = v.visitId;
    householdId = v.householdId;
    await work.recordOutcome(
      visitId,
      VisitOutcome(
        status: 'COMPLETED',
        actualDate: today,
        followupRequired: true,
        nextFollowupDate: DateTime(2026, 11, 20),
        referral: const ReferralDraft(
          facilityId: 'FAC-SYN-01',
          serviceCategory: 'GENERAL',
        ),
      ),
    );
    expect(
      (await store.outboxCounts()).pending,
      3,
      reason: 'visit update + follow-up visit + referral',
    );
    final rep = await engine.syncNow();
    expect(rep.ok, isFalse);
    expect(rep.offline, isTrue);
    final c = await store.outboxCounts();
    expect(
      (c.pending, c.synced),
      (3, 0),
      reason: 'a failed sync never drops or marks anything',
    );
  }, skip: skip);

  test('3+4. app restart (database closed and reopened): records and the 3 pending operations survive', () async {
    await adb.close();
    await openApp();
    expect((await store.visit(visitId))!.status, 'COMPLETED');
    expect((await store.outboxCounts()).pending, 3);
  }, skip: skip);

  test('5. reconnect but the reply is lost on the way back: the server stored it, the phone does NOT claim it is synced', () async {
    net.down = false;
    net.loseNextPushReply = true;
    final rep = await engine.syncNow();
    expect(rep.ok, isFalse);
    final c = await store.outboxCounts();
    expect(c.synced, 0);
    expect(c.pending + c.failed, 3, reason: 'still queued for a resend');
  }, skip: skip);

  test('6. sync again: all three acknowledged (recognised as duplicates), queue empty', () async {
    final rep = await engine.syncNow();
    expect(rep.ok, isTrue, reason: '${rep.error}');
    expect((rep.acknowledged, rep.conflicts, rep.rejected), (3, 0, 0));
    final c = await store.outboxCounts();
    expect((c.pending, c.needsAttention, c.synced), (0, 0, 3));
  }, skip: skip);

  test('7. the server holds exactly one copy of each record (independent admin check)', () async {
    final visits =
        ((await admin(
                  '/api/v1/visits?household_id=$householdId&limit=200',
                ))['items']
                as List)
            .cast<Map<String, dynamic>>();
    expect(
      visits.where((x) => x['visit_id'] == visitId).single['visit_status'],
      'COMPLETED',
    );
    expect(
      visits.where(
        (x) =>
            x['visit_status'] == 'PLANNED' &&
            x['scheduled_date'] == '2026-11-20',
      ),
      hasLength(1),
      reason: 'the follow-up visit was not created twice by the resend',
    );
    final refs =
        ((await admin(
                  '/api/v1/referrals?household_id=$householdId&limit=200',
                ))['items']
                as List)
            .cast<Map<String, dynamic>>();
    expect(
      refs.where((x) => x['visit_id'] == visitId),
      hasLength(1),
      reason: 'the referral was not created twice',
    );
  }, skip: skip);
}
