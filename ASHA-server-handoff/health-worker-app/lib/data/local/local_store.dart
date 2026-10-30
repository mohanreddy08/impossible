import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../models/household.dart';
import '../models/outbox_op.dart';
import '../models/referral.dart';
import '../models/visit.dart';
import 'database.dart';

class HouseholdFilter {
  const HouseholdFilter({
    this.search = '',
    this.status,
    this.category,
    this.village,
  });
  final String search;
  final String? status, category, village;
}

/// When a worker went on a visit: 'HH:mm' (24 h, phone local time) and whether it is still the automatically filled-in value.
class VisitTime {
  const VisitTime(this.hhmm, this.auto);
  final String hhmm;
  final bool auto;
}

class VisitWithHousehold {
  const VisitWithHousehold(this.visit, this.household, this.hasOpenReferral);
  final Visit visit;
  final Household? household;
  final bool hasOpenReferral;
}

class DashboardCounts {
  const DashboardCounts({
    this.dueToday = 0,
    this.overdue = 0,
    this.upcoming = 0,
    this.pendingReferrals = 0,
    this.households = 0,
  });
  final int dueToday, overdue, upcoming, pendingReferrals, households;
}

class OutboxCounts {
  const OutboxCounts({
    this.pending = 0,
    this.failed = 0,
    this.conflict = 0,
    this.synced = 0,
  });
  final int pending, failed, conflict, synced;
  int get needsAttention => failed + conflict;
  int get unsynced => pending + failed + conflict;
}

/// All SQLite access. Queries are paged/limited so the whole register is never held in memory.
/// A referral counts as attended ONLY with a hospital attendance record. Everything else that is still ACTIVE is "open",
/// including a record flagged confirmed without that evidence (it is displayed as planned, never as attended).
const _trulyConfirmed =
    "referral_status = 'ATTENDANCE_CONFIRMED' AND attendance_confirmed = 1 AND attendance_record_id IS NOT NULL AND attendance_record_id <> ''";
const _openSql = "record_state = 'ACTIVE' AND NOT ($_trulyConfirmed)";

class LocalStore {
  LocalStore(this._adb);
  final AppDatabase _adb;
  Database get db => _adb.db;

  // ---------------- households ----------------
  (String, List<Object?>) _hhWhere(HouseholdFilter f) {
    final w = <String>[], a = <Object?>[];
    if (f.search.trim().isNotEmpty) {
      w.add("household_id LIKE ? ESCAPE '\\'");
      a.add(
        '%${f.search.trim().replaceAll('\\', '').replaceAll('%', '').replaceAll('_', '\\_')}%',
      );
    }
    if (f.status != null) {
      w.add('record_status = ?');
      a.add(f.status);
    }
    if (f.category != null) {
      w.add('eligible_followup_categories LIKE ?');
      a.add('%|${f.category}|%');
    }
    if (f.village != null) {
      w.add('village_id = ?');
      a.add(f.village);
    }
    return (w.isEmpty ? '' : 'WHERE ${w.join(' AND ')}', a);
  }

  Future<List<Household>> pageHouseholds(
    HouseholdFilter f, {
    int limit = 30,
    int offset = 0,
  }) async {
    final (where, args) = _hhWhere(f);
    final rows = await db.rawQuery(
      "SELECT * FROM households $where ORDER BY CASE record_status WHEN 'OVERDUE' THEN 0 WHEN 'DUE_TODAY' THEN 1 WHEN 'UPCOMING' THEN 2 ELSE 3 END, "
      'next_visit_due_date IS NULL, next_visit_due_date, household_id LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return rows.map(Household.fromRow).toList();
  }

  Future<int> countHouseholds(HouseholdFilter f) async {
    final (where, args) = _hhWhere(f);
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM households $where', args),
        ) ??
        0;
  }

  // ---------------- where a house is, and who to call (local only, see migration 6) ----------------
  Future<void> setGeo(Map<String, (double, double)> geo) async {
    final b = db.batch();
    geo.forEach((id, p) {
      b.insert('household_geo', {
        'household_id': id,
        'lat': p.$1,
        'lng': p.$2,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await b.commit(noResult: true);
  }

  Future<int> geoCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM household_geo')) ?? 0;

  /// Every house location saved on this phone (the families added here, and the demo houses).
  Future<Map<String, (double, double)>> geoAll() async {
    final r = await db.query('household_geo');
    return {for (final e in r) e['household_id']! as String: ((e['lat']! as num).toDouble(), (e['lng']! as num).toDouble())};
  }

  Future<void> removeGeo(String householdId) =>
      db.delete('household_geo', where: 'household_id = ?', whereArgs: [householdId]);

  Future<(double, double)?> geoFor(String householdId) async {
    final r = await db.query('household_geo', where: 'household_id = ?', whereArgs: [householdId]);
    return r.isEmpty ? null : ((r.first['lat']! as num).toDouble(), (r.first['lng']! as num).toDouble());
  }

  Future<(String, String?)?> contactsFor(String householdId) async {
    final r = await db.query('household_contacts', where: 'household_id = ?', whereArgs: [householdId]);
    return r.isEmpty ? null : (r.first['phone1']! as String, r.first['phone2'] as String?);
  }

  Future<void> saveContacts(String householdId, String phone1, String? phone2, DateTime now) =>
      db.insert('household_contacts', {
        'household_id': householdId,
        'phone1': phone1,
        'phone2': (phone2 == null || phone2.isEmpty) ? null : phone2,
        'saved_at': now.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Household?> household(String id) async {
    final r = await db.query(
      'households',
      where: 'household_id = ?',
      whereArgs: [id],
    );
    return r.isEmpty ? null : Household.fromRow(r.first);
  }

  /// The worker this phone belongs to: the one most households are assigned to (falls back to the demo worker).
  Future<String?> currentWorkerId() async {
    final r = await db.rawQuery(
      'SELECT assigned_worker_id w, COUNT(*) c FROM households GROUP BY assigned_worker_id ORDER BY c DESC, w LIMIT 1',
    );
    if (r.isNotEmpty) return r.first['w']! as String;
    return meta('demo_worker');
  }

  /// Villages ordered by how many households they hold (most used first).
  Future<List<String>> villagesByUse() async => (await db.rawQuery(
    'SELECT village_id, COUNT(*) c FROM households GROUP BY village_id ORDER BY c DESC, village_id',
  )).map((r) => r['village_id']! as String).toList();

  Future<List<String>> villages() async => (await db.rawQuery(
    'SELECT DISTINCT village_id FROM households ORDER BY village_id',
  )).map((r) => r['village_id']! as String).toList();

  // ---------------- visits ----------------
  Future<Visit?> visit(String id) async {
    final r = await db.query('visits', where: 'visit_id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Visit.fromRow(r.first);
  }

  /// Local-only time of day for visits (see migration v3). Map of visit id -> 'HH:mm'.
  Future<Map<String, String>> visitTimes(Iterable<String> visitIds) async {
    final ids = visitIds.toList();
    if (ids.isEmpty) return {};
    final marks = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT visit_id, visit_time FROM visit_times WHERE visit_id IN ($marks)',
      ids,
    );
    return {
      for (final r in rows)
        r['visit_id']! as String: r['visit_time']! as String,
    };
  }

  Future<VisitTime?> visitTime(String visitId) async {
    final r = await db.query(
      'visit_times',
      where: 'visit_id = ?',
      whereArgs: [visitId],
    );
    return r.isEmpty
        ? null
        : VisitTime(
            r.first['visit_time']! as String,
            (r.first['auto'] as int?) == 1,
          );
  }

  Future<void> putVisitTime(
    DatabaseExecutor ex,
    String visitId,
    VisitTime t,
    String savedAt,
  ) => ex.insert('visit_times', {
    'visit_id': visitId,
    'visit_time': t.hhmm,
    'auto': t.auto ? 1 : 0,
    'saved_at': savedAt,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Visit>> visitsForHousehold(
    String householdId, {
    int limit = 20,
    int offset = 0,
  }) async => (await db.query(
    'visits',
    where: 'household_id = ?',
    whereArgs: [householdId],
    orderBy: 'scheduled_date DESC, visit_id',
    limit: limit,
    offset: offset,
  )).map(Visit.fromRow).toList();

  /// Planned visits for the planner. bucket: overdue | today | upcoming. Order = priority (see rules/visit_rules.dart).
  Future<List<VisitWithHousehold>> plannedVisits(
    String bucket,
    DateTime asOf, {
    int limit = 30,
    int offset = 0,
  }) async {
    final d = isoDate(asOf);
    final cond = switch (bucket) {
      'overdue' => 'v.scheduled_date < ?',
      'today' => 'v.scheduled_date = ?',
      _ => 'v.scheduled_date > ?',
    };
    final order = bucket == 'overdue'
        ? 'v.scheduled_date ASC'
        : 'v.scheduled_date ASC';
    final rows = await db.rawQuery(
      '''SELECT v.*, h.household_member_count AS h_members, h.village_id AS h_village,
           (SELECT COUNT(*) FROM referrals r WHERE r.household_id = v.household_id AND r.record_state = 'ACTIVE'
              AND r.referral_status IN ('RECOMMENDED','PLANNED')) AS open_refs
         FROM visits v LEFT JOIN households h ON h.household_id = v.household_id
         WHERE v.visit_status = 'PLANNED' AND $cond ORDER BY $order, v.visit_id LIMIT ? OFFSET ?''',
      [d, limit, offset],
    );
    return rows
        .map(
          (r) => VisitWithHousehold(
            Visit.fromRow(r),
            null,
            ((r['open_refs'] as int?) ?? 0) > 0,
          ),
        )
        .toList();
  }

  Future<int> countPlanned(String bucket, DateTime asOf) async {
    final cond = switch (bucket) {
      'overdue' => 'scheduled_date < ?',
      'today' => 'scheduled_date = ?',
      _ => 'scheduled_date > ?',
    };
    return Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM visits WHERE visit_status = 'PLANNED' AND $cond",
            [isoDate(asOf)],
          ),
        ) ??
        0;
  }

  Future<DashboardCounts> dashboard(DateTime asOf) async => DashboardCounts(
    dueToday: await countPlanned('today', asOf),
    overdue: await countPlanned('overdue', asOf),
    upcoming: await countPlanned('upcoming', asOf),
    pendingReferrals:
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM referrals WHERE $_openSql'),
        ) ??
        0,
    households:
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM households'),
        ) ??
        0,
  );

  // ---------------- referrals ----------------
  Future<Referral?> referral(String id) async {
    final r = await db.query(
      'referrals',
      where: 'referral_id = ?',
      whereArgs: [id],
    );
    return r.isEmpty ? null : Referral.fromRow(r.first);
  }

  /// filter: all | pending | planned | recommended | confirmed | closed
  Future<List<Referral>> pageReferrals(
    String filter, {
    int limit = 30,
    int offset = 0,
  }) async {
    final cond = switch (filter) {
      'pending' => _openSql,
      'recommended' =>
        "record_state='ACTIVE' AND referral_status='RECOMMENDED'",
      'planned' => "$_openSql AND referral_status <> 'RECOMMENDED'",
      'confirmed' => "record_state='ACTIVE' AND $_trulyConfirmed",
      'closed' => "record_state<>'ACTIVE'",
      _ => '1=1',
    };
    return (await db.query(
      'referrals',
      where: cond,
      orderBy: 'referral_created_date DESC, referral_id',
      limit: limit,
      offset: offset,
    )).map(Referral.fromRow).toList();
  }

  Future<List<Referral>> referralsForHousehold(String householdId) async =>
      (await db.query(
        'referrals',
        where: 'household_id = ?',
        whereArgs: [householdId],
        orderBy: 'referral_created_date DESC',
      )).map(Referral.fromRow).toList();

  Future<List<Referral>> referralsBetween(
    String facilityId,
    DateTime start,
    DateTime end,
  ) async => (await db.query(
    'referrals',
    where: 'facility_id = ? AND referral_created_date BETWEEN ? AND ?',
    whereArgs: [facilityId, isoDate(start), isoDate(end)],
  )).map(Referral.fromRow).toList();

  Future<List<String>> facilities() async => (await db.rawQuery(
    'SELECT DISTINCT facility_id FROM referrals ORDER BY facility_id',
  )).map((r) => r['facility_id']! as String).toList();

  // ---------------- server records (pull / seed) ----------------
  /// Entities with a not-yet-acknowledged local change are never overwritten by a pull.
  Future<Set<String>> protectedEntityIds(String entityType) async =>
      (await db.rawQuery(
        "SELECT DISTINCT entity_id FROM sync_outbox WHERE entity_type = ? AND state IN ('PENDING','REJECTED','CONFLICT')",
        [entityType],
      )).map((r) => r['entity_id']! as String).toSet();

  Future<int> upsertHouseholds(
    List<Household> list, {
    bool respectPending = true,
  }) => _upsert(
    'households',
    'household',
    list.map((e) => (e.householdId, e.toRow())).toList(),
    respectPending,
  );
  Future<int> upsertVisits(
    List<Visit> list, {
    bool respectPending = true,
  }) async {
    final n = await _upsert(
      'visits',
      'visit',
      list.map((e) => (e.visitId, e.toRow())).toList(),
      respectPending,
    );
    // The server now stores the time a visit happened: keep the phone's copy in step. A visit the server has NO time for keeps
    // whatever the phone recorded (older visits, and could-not-visit times, which the server does not store).
    final skip = respectPending
        ? await protectedEntityIds('visit')
        : <String>{};
    final withTime = list
        .where((v) => v.actualVisitTime != null && !skip.contains(v.visitId))
        .toList();
    if (withTime.isNotEmpty) {
      await db.transaction((txn) async {
        for (final v in withTime) {
          await putVisitTime(
            txn,
            v.visitId,
            VisitTime(v.actualVisitTime!, true),
            v.updatedAt,
          );
        }
      });
    }
    return n;
  }

  Future<int> upsertReferrals(
    List<Referral> list, {
    bool respectPending = true,
  }) => _upsert(
    'referrals',
    'referral',
    list.map((e) => (e.referralId, e.toRow())).toList(),
    respectPending,
  );

  Future<int> _upsert(
    String table,
    String type,
    List<(String, Map<String, Object?>)> rows,
    bool respectPending,
  ) async {
    final skip = respectPending ? await protectedEntityIds(type) : <String>{};
    var n = 0;
    await db.transaction((txn) async {
      final b = txn.batch();
      for (final (id, row) in rows) {
        if (skip.contains(id)) continue;
        b.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
        n++;
      }
      await b.commit(noResult: true);
    });
    return n;
  }

  // ---------------- outbox ----------------
  Future<void> enqueue(DatabaseExecutor txn, OutboxOp op) =>
      txn.insert('sync_outbox', op.toRow());

  Future<List<OutboxOp>> ops({
    OpState? state,
    int limit = 200,
    int offset = 0,
    bool includeAck = false,
  }) async {
    final rows = await db.query(
      'sync_outbox',
      where: state != null
          ? 'state = ?'
          : (includeAck ? null : "state <> 'ACKNOWLEDGED'"),
      whereArgs: state != null ? [state.name.toUpperCase()] : null,
      orderBy: 'seq ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(OutboxOp.fromRow).toList();
  }

  Future<OutboxOp?> op(String opId) async {
    final r = await db.query(
      'sync_outbox',
      where: 'op_id = ?',
      whereArgs: [opId],
    );
    return r.isEmpty ? null : OutboxOp.fromRow(r.first);
  }

  Future<OutboxCounts> outboxCounts() async {
    final rows = await db.rawQuery(
      "SELECT state, (last_error_code IS NOT NULL AND state='PENDING') AS errored, COUNT(*) AS n FROM sync_outbox GROUP BY state, errored",
    );
    var pending = 0, failed = 0, conflict = 0, synced = 0;
    for (final r in rows) {
      final n = r['n']! as int;
      switch (r['state']) {
        case 'PENDING':
          pending += n;
        case 'REJECTED':
          failed += n;
        case 'CONFLICT':
          conflict += n;
        case 'ACKNOWLEDGED':
          synced += n;
      }
    }
    return OutboxCounts(
      pending: pending,
      failed: failed,
      conflict: conflict,
      synced: synced,
    );
  }

  Future<bool> hasUnsyncedOps(String entityType, String entityId) async =>
      (Sqflite.firstIntValue(
            await db.rawQuery(
              "SELECT COUNT(*) FROM sync_outbox WHERE entity_type=? AND entity_id=? AND state IN ('PENDING','REJECTED','CONFLICT')",
              [entityType, entityId],
            ),
          ) ??
          0) >
      0;

  Future<Set<String>> unsyncedEntityIds(String entityType) =>
      protectedEntityIds(entityType);

  Future<void> updateOp(String opId, Map<String, Object?> values) =>
      db.update('sync_outbox', values, where: 'op_id = ?', whereArgs: [opId]);

  Future<void> deleteOp(String opId) =>
      db.delete('sync_outbox', where: 'op_id = ?', whereArgs: [opId]);

  Future<void> pruneAcknowledged({int keep = 100}) => db.execute(
    "DELETE FROM sync_outbox WHERE state='ACKNOWLEDGED' AND seq NOT IN (SELECT seq FROM sync_outbox WHERE state='ACKNOWLEDGED' ORDER BY seq DESC LIMIT $keep)",
  );

  // ---------------- meta ----------------
  Future<String?> meta(String k) async {
    final r = await db.query('app_meta', where: 'k = ?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  Future<void> setMeta(String k, String? v) async {
    if (v == null) {
      await db.delete('app_meta', where: 'k = ?', whereArgs: [k]);
    } else {
      await db.insert('app_meta', {
        'k': k,
        'v': v,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<Map<String, int>> rowCounts() async {
    final out = <String, int>{};
    for (final t in [
      'households',
      'visits',
      'referrals',
      'protocol_passages',
      'sync_outbox',
    ]) {
      out[t] =
          Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t')) ??
          0;
    }
    return out;
  }

  /// Removes all local records. Used by "clear local data" in Settings.
  Future<void> wipe() async {
    await db.transaction((txn) async {
      for (final t in [
        'sync_outbox',
        'referrals',
        'ai_cache',
        'passage_vectors',
        'visit_times',
        'visits',
        'household_geo',
        'household_contacts',
        'households',
        'protocol_passages',
        'protocol_documents',
        'app_meta',
      ]) {
        await txn.delete(t);
      }
    });
  }

  String encode(Object o) => jsonEncode(o);
}
