import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database with explicit, versioned migrations. Table/column names mirror the backend models
/// (see health-worker-backend/docs/mobile_sqlite_schema.sql) plus device-only tables (sync_outbox, app_meta).
///
/// v1: base schema.  v2: sync_outbox.last_attempt_at, outbox state index, visits(household, date) index.
/// v5: passage_vectors (search vectors for protocol passages, built on the phone for ANY passage, so real documents need no extra step).
/// v4: ai_cache (the last AI answers, keyed by a one-way hash of the question: the question text is never stored).
/// v3: visit_times (device-only: the time of day a worker went on a visit; the server has no field for it).
/// To change the schema: add a new entry to [migrations], bump [schemaVersion], add a migration test.
class AppDatabase {
  AppDatabase._(this.db);
  final Database db;

  static const schemaVersion = 6;

  static const Map<int, List<String>> migrations = {
    1: [
      '''CREATE TABLE households (
        household_id TEXT PRIMARY KEY, village_id TEXT NOT NULL, assigned_worker_id TEXT NOT NULL,
        household_member_count INTEGER NOT NULL CHECK (household_member_count >= 1),
        eligible_followup_categories TEXT NOT NULL,
        last_visit_date TEXT, next_visit_due_date TEXT, scheduled_followup_category TEXT,
        record_status TEXT NOT NULL CHECK (record_status IN ('UPCOMING','DUE_TODAY','OVERDUE','COMPLETED','NO_VISIT_DUE')),
        last_updated TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
      'CREATE INDEX ix_hh_due ON households(next_visit_due_date)',
      'CREATE INDEX ix_hh_status ON households(record_status)',
      '''CREATE TABLE visits (
        visit_id TEXT PRIMARY KEY, household_id TEXT NOT NULL REFERENCES households(household_id), worker_id TEXT NOT NULL,
        scheduled_date TEXT NOT NULL, actual_visit_date TEXT,
        visit_status TEXT NOT NULL CHECK (visit_status IN ('PLANNED','COMPLETED','MISSED','RESCHEDULED','CANCELLED')),
        visit_reason TEXT NOT NULL, followup_required INTEGER, next_followup_date TEXT,
        referral_status TEXT NOT NULL DEFAULT 'NONE' CHECK (referral_status IN ('NONE','RECOMMENDED','PLANNED','ATTENDANCE_CONFIRMED')),
        referral_id TEXT, recorded_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
      'CREATE INDEX ix_visits_status_sched ON visits(visit_status, scheduled_date)',
      '''CREATE TABLE referrals (
        referral_id TEXT PRIMARY KEY, household_id TEXT NOT NULL REFERENCES households(household_id),
        visit_id TEXT NOT NULL REFERENCES visits(visit_id), facility_id TEXT NOT NULL, service_category TEXT NOT NULL,
        referral_created_date TEXT NOT NULL, planned_visit_date TEXT,
        referral_status TEXT NOT NULL CHECK (referral_status IN ('RECOMMENDED','PLANNED','ATTENDANCE_CONFIRMED')),
        attendance_confirmed INTEGER NOT NULL DEFAULT 0, attendance_confirmation_date TEXT, attendance_record_id TEXT,
        record_state TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (record_state IN ('ACTIVE','CANCELLED','INVALID','DUPLICATE')),
        duplicate_of TEXT, last_updated TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
      'CREATE INDEX ix_ref_state ON referrals(record_state, referral_status)',
      '''CREATE TABLE protocol_documents (
        document_id TEXT PRIMARY KEY, title TEXT, issuing_authority TEXT, version TEXT, publication_date TEXT, language TEXT,
        source_verification_status TEXT NOT NULL, approved_for_retrieval INTEGER NOT NULL)''',
      '''CREATE TABLE protocol_passages (
        passage_id TEXT PRIMARY KEY, document_id TEXT NOT NULL REFERENCES protocol_documents(document_id), section_id TEXT,
        section_title TEXT, page_number INTEGER, passage_text TEXT NOT NULL, language TEXT,
        approved_for_retrieval INTEGER NOT NULL, source_verification_status TEXT NOT NULL)''',
      '''CREATE TABLE sync_outbox (
        seq INTEGER PRIMARY KEY AUTOINCREMENT, op_id TEXT NOT NULL UNIQUE, idempotency_key TEXT NOT NULL UNIQUE,
        entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, op_type TEXT NOT NULL CHECK (op_type IN ('create','update')),
        base_version INTEGER, payload TEXT NOT NULL, before_json TEXT, client_created_at TEXT NOT NULL, client_updated_at TEXT,
        state TEXT NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING','ACKNOWLEDGED','REJECTED','CONFLICT')),
        attempts INTEGER NOT NULL DEFAULT 0, last_error_code TEXT, last_error_message TEXT, conflict_json TEXT)''',
      'CREATE TABLE app_meta (k TEXT PRIMARY KEY, v TEXT)',
    ],
    2: [
      'ALTER TABLE sync_outbox ADD COLUMN last_attempt_at TEXT',
      'CREATE INDEX ix_outbox_state ON sync_outbox(state, seq)',
      'CREATE INDEX ix_outbox_entity ON sync_outbox(entity_type, entity_id)',
      'CREATE INDEX ix_visits_household ON visits(household_id, scheduled_date)',
    ],
    // Kept OUT of the visits table on purpose: a pull from the server replaces visit rows (INSERT OR REPLACE) and would wipe a
    // local-only column. visit_time is 'HH:mm' (24 h, phone local time); auto = 1 while it is the value filled in when the form
    // opened, 0 once the worker changed it.
    3: [
      'CREATE TABLE visit_times (visit_id TEXT PRIMARY KEY, visit_time TEXT NOT NULL, auto INTEGER NOT NULL DEFAULT 1, saved_at TEXT NOT NULL)',
    ],
    4: [
      'CREATE TABLE ai_cache (key_hash TEXT PRIMARY KEY, answer TEXT NOT NULL, saved_at TEXT NOT NULL)',
    ],
    5: [
      'CREATE TABLE passage_vectors (passage_id TEXT PRIMARY KEY, embedder_id TEXT NOT NULL, text_hash TEXT NOT NULL, vec BLOB NOT NULL)',
    ],
    // Where a house is, and its phone numbers. Kept OUT of the households table on purpose (like visit_times): a pull from the server
    // replaces household rows and would wipe a local-only column. Phone numbers are personal data: they stay on this phone, are never
    // sent to the server, and are removed by "Delete all data on this phone".
    6: [
      'CREATE TABLE household_geo (household_id TEXT PRIMARY KEY, lat REAL NOT NULL, lng REAL NOT NULL)',
      'CREATE TABLE household_contacts (household_id TEXT PRIMARY KEY, phone1 TEXT NOT NULL, phone2 TEXT, saved_at TEXT NOT NULL)',
    ],
  };

  static Future<void> _apply(Database db, int from, int to) async {
    for (var v = from + 1; v <= to; v++) {
      for (final sql in migrations[v]!) {
        await db.execute(sql);
      }
    }
  }

  /// [targetVersion] below [schemaVersion] exists so tests can build a genuine v1 database and upgrade it.
  static Future<AppDatabase> open({
    String? path,
    DatabaseFactory? factory,
    int targetVersion = schemaVersion,
    bool singleInstance = true,
  }) async {
    final f = factory ?? databaseFactory;
    final resolved =
        path ?? p.join(await f.getDatabasesPath(), 'health_companion.db');
    final db = await f.openDatabase(
      resolved,
      options: OpenDatabaseOptions(
        version: targetVersion,
        singleInstance:
            singleInstance, // tests open many throw-away in-memory databases
        onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, v) => _apply(d, 0, v),
        onUpgrade: (d, from, to) => _apply(d, from, to),
      ),
    );
    return AppDatabase._(db);
  }

  Future<void> close() => db.close();
}
