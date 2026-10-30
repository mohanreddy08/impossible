import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:health_companion/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_companion/core/clock.dart';
import 'package:health_companion/data/api/api_client.dart';
import 'package:health_companion/data/local/database.dart';
import 'package:health_companion/data/local/local_store.dart';
import 'package:health_companion/services/data_bus.dart';
import 'package:health_companion/services/field_work_service.dart';
import 'package:health_companion/services/sync_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'builders.dart';
import 'fake_server.dart';

Future<AppDatabase> openTestDb({
  String? path,
  int target = AppDatabase.schemaVersion,
}) async {
  sqfliteFfiInit();
  return AppDatabase.open(
    path: path ?? inMemoryDatabasePath,
    factory: databaseFactoryFfi,
    singleInstance: path != null,
    targetVersion: target,
  );
}

class Rig {
  Rig(
    this.adb,
    this.store,
    this.clock,
    this.bus,
    this.fieldWork,
    this.server,
    this.api,
    this.engine,
  );
  final AppDatabase adb;
  final LocalStore store;
  final AppClock clock;
  final DataBus bus;
  final FieldWorkService fieldWork;
  final FakeServer server;
  final ApiClient api;
  final SyncEngine engine;

  static Future<Rig> create({
    String? dbPath,
    FakeServer? server,
    bool configured = true,
  }) async {
    final adb = await openTestDb(path: dbPath);
    final store = LocalStore(adb);
    final clock = AppClock(
      now: () => DateTime(2026, 10, 13, 9),
      demoDate: today,
    );
    final bus = DataBus();
    final srv = server ?? FakeServer();
    final api = ApiClient(
      client: srv.client(),
      config: () async =>
          configured ? const ApiConfig('http://fake.local', 'test-key') : null,
      timeout: const Duration(seconds: 2),
    );
    final engine = SyncEngine(
      store: store,
      api: api,
      installationId: () async => 'install-test-0001',
      clock: clock,
      onChanged: bus.changed,
    );
    return Rig(
      adb,
      store,
      clock,
      bus,
      FieldWorkService(store, clock, bus),
      srv,
      api,
      engine,
    );
  }

  /// One household with a PLANNED visit due today, as a worker would see it.
  Future<void> seedBasic() async {
    await store.upsertHouseholds([
      hh(
        'HH-1',
        status: 'DUE_TODAY',
        next: today,
        scheduled: 'ANC',
        cats: ['ANC', 'ROUTINE'],
        last: DateTime(2026, 9, 10),
      ),
    ], respectPending: false);
    await store.upsertVisits([
      vis(
        'VIS-OLD',
        'HH-1',
        DateTime(2026, 9, 10),
        status: 'COMPLETED',
        actual: DateTime(2026, 9, 10),
        reason: 'ANC',
      ),
      vis('VIS-1', 'HH-1', today, reason: 'ANC'),
    ], respectPending: false);
    await store.upsertReferrals([
      ref(
        'REF-OLD',
        'HH-1',
        'VIS-OLD',
        status: 'PLANNED',
        planned: DateTime(2026, 10, 20),
        created: DateTime(2026, 9, 11),
      ),
    ], respectPending: false);
  }

  Future<void> dispose() => adb.close();
}

Map<String, dynamic> decode(http.Request r) =>
    jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

Future<String> tempDbPath() async =>
    '${(await Directory.systemTemp.createTemp('hc_test_')).path}/t.db';

Future<(AppSettings, MemorySecretStore, SharedPreferences)>
buildSettingsRig() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secrets = MemorySecretStore();
  final s = AppSettings(prefs, secrets, AppClock());
  await s.load();
  return (s, secrets, prefs);
}
