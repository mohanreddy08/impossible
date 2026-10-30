import 'dart:async';

import 'package:sqflite/sqflite.dart' show DatabaseException;

import '../core/clock.dart';
import '../data/api/api_client.dart';
import '../data/api/api_exceptions.dart';
import '../data/api/api_models.dart';
import '../data/local/local_store.dart';
import '../data/models/outbox_op.dart';
import '../domain/rules/visit_rules.dart';

class SyncReport {
  SyncReport();
  int sent = 0,
      acknowledged = 0,
      conflicts = 0,
      rejected = 0,
      retryable = 0,
      pulled = 0;
  bool offline = false,
      authFailed = false,
      notConfigured = false,
      completed = false,
      alreadyRunning = false;
  ApiException? error;
  bool get ok => completed && error == null;
}

/// Client side of the backend sync protocol (docs/FLUTTER_INTEGRATION_GUIDE.md section 7).
///  * an operation counts as synced ONLY when the server returns acknowledged == true;
///  * after any transport failure/timeout the outcome is UNKNOWN, so the operation stays pending and is resent (idempotent by op_id);
///  * local data is never deleted because a request failed;
///  * conflicting server records are never overwritten silently: protected entities (with unsynced ops) are skipped by pull.
class SyncEngine {
  SyncEngine({
    required this.store,
    required this.api,
    required this.installationId,
    required this.clock,
    this.onChanged,
    this.batchSize = 200,
    this.recentCompletionDays = 14,
  });
  final LocalStore store;
  final ApiClient api;
  final Future<String> Function() installationId;
  final AppClock clock;
  final void Function()? onChanged;
  final int batchSize, recentCompletionDays;
  bool _running = false;
  bool get isRunning => _running;

  static const _types = ['household', 'visit', 'referral'];

  Future<SyncReport> syncNow({bool pull = true}) async {
    final rep = SyncReport();
    if (_running) {
      rep.alreadyRunning = true;
      return rep;
    }
    _running = true;
    try {
      final pushOk = await _push(rep);
      if (pushOk && pull) await _pull(rep);
      rep.completed = pushOk && (!pull || rep.error == null);
      if (rep.completed) {
        await store.setMeta(
          'last_sync_at',
          '${clock.nowUtc().toIso8601String().split('.').first}Z',
        );
        await store.pruneAcknowledged();
      }
    } on NotConfigured {
      rep.notConfigured = true;
    } finally {
      _running = false;
      onChanged?.call();
    }
    return rep;
  }

  /// Returns false when the cycle must stop (offline, auth failure, server fault).
  Future<bool> _push(SyncReport rep) async {
    final attempted = <String>{};
    final inst = await installationId();
    while (true) {
      final pending = (await store.ops(
        state: OpState.pending,
        limit: batchSize + attempted.length,
      )).where((o) => !attempted.contains(o.opId)).take(batchSize).toList();
      if (pending.isEmpty) return true;
      attempted.addAll(pending.map((o) => o.opId));
      rep.sent += pending.length;
      PushResponse res;
      try {
        res = await api.push(inst, [for (final o in pending) o.toWire()]);
      } on NotConfigured {
        rethrow;
      } on Unauthorized catch (e) {
        rep.authFailed = true;
        rep.error = e;
        return false;
      } on NetworkUnavailable catch (e) {
        await _markAttempt(
          pending,
          'NETWORK',
          'No connection. Your changes are saved on this phone and will be sent again.',
        );
        rep.offline = true;
        rep.error = e;
        return false;
      } on RequestTimeout catch (e) {
        await _markAttempt(
          pending,
          'TIMEOUT',
          'The server took too long. Your changes are saved and will be sent again.',
        );
        rep.offline = true;
        rep.error = e;
        return false;
      } on ApiException catch (e) {
        await _markAttempt(
          pending,
          e.code ?? 'SERVER',
          'The server could not process this batch. Your changes are saved.',
        );
        rep.error = e;
        return false;
      }
      final byId = {
        for (final r in res.results)
          if (r.opId != null) r.opId!: r,
      };
      for (final op in pending) {
        final r = byId[op.opId];
        if (r == null) {
          await _markAttempt(
            [op],
            'NO_RESULT',
            'The server did not report on this change. It will be sent again.',
          );
          rep.retryable++;
          continue;
        }
        await _apply(op, r, rep);
      }
      onChanged?.call();
    }
  }

  Future<void> _markAttempt(
    List<OutboxOp> ops,
    String code,
    String message,
  ) async {
    final now = '${clock.nowUtc().toIso8601String().split('.').first}Z';
    for (final o in ops) {
      await store.updateOp(o.opId, {
        'attempts': o.attempts + 1,
        'last_error_code': code,
        'last_error_message': message,
        'last_attempt_at': now,
      });
    }
  }

  Future<void> _apply(OutboxOp op, PushResult r, SyncReport rep) async {
    final now = '${clock.nowUtc().toIso8601String().split('.').first}Z';
    if (r.acknowledged && r.status == 'ACKNOWLEDGED') {
      await store.updateOp(op.opId, {
        'state': 'ACKNOWLEDGED',
        'attempts': op.attempts + 1,
        'last_error_code': null,
        'last_error_message': null,
        'last_attempt_at': now,
        'conflict_json': r.conflict == null ? null : store.encode(r.conflict!),
      });
      await _afterAck(op, r);
      rep.acknowledged++;
      return;
    }
    switch (r.status) {
      case 'CONFLICT':
        await store.updateOp(op.opId, {
          'state': 'CONFLICT',
          'attempts': op.attempts + 1,
          'last_error_code': r.errorCode,
          'last_error_message': r.errorMessage,
          'conflict_json': r.conflict == null
              ? null
              : store.encode(r.conflict!),
          'last_attempt_at': now,
        });
        rep.conflicts++;
      case 'REJECTED':
        await store.updateOp(op.opId, {
          'state': 'REJECTED',
          'attempts': op.attempts + 1,
          'last_error_code': r.errorCode,
          'last_error_message': r.errorMessage,
          'last_attempt_at': now,
        });
        rep.rejected++;
      default: // FAILED_RETRYABLE or anything not explicitly acknowledged: keep pending, never assume success
        await store.updateOp(op.opId, {
          'attempts': op.attempts + 1,
          'last_error_code': r.errorCode ?? 'TEMPORARY_FAILURE',
          'last_error_message':
              r.errorMessage ??
              'Temporary server problem. It will be sent again.',
          'last_attempt_at': now,
        });
        rep.retryable++;
    }
  }

  Future<void> _afterAck(OutboxOp op, PushResult r) async {
    final table = switch (op.entityType) {
      'household' => 'households',
      'visit' => 'visits',
      _ => 'referrals',
    };
    final idCol = switch (op.entityType) {
      'household' => 'household_id',
      'visit' => 'visit_id',
      _ => 'referral_id',
    };
    if (r.serverVersion != null &&
        !await store.hasUnsyncedOps(op.entityType, op.entityId)) {
      await store.db.update(
        table,
        {'version': r.serverVersion},
        where: '$idCol = ?',
        whereArgs: [op.entityId],
      ); // no later local edit: adopt the server's number exactly
    }
    for (final w in r.warnings) {
      if (op.entityType == 'referral' &&
          w.startsWith('DUPLICATE_FLAGGED:duplicate_of=')) {
        await store.db.update(
          'referrals',
          {'record_state': 'DUPLICATE', 'duplicate_of': w.split('=').last},
          where: 'referral_id = ?',
          whereArgs: [op.entityId],
        );
        await store.db.update(
          'visits',
          {'referral_status': 'NONE', 'referral_id': null},
          where: 'referral_id = ?',
          whereArgs: [op.entityId],
        );
      }
    }
  }

  // ---------------------------------------------------------------- pull
  Future<void> _resetCursors() async {
    for (final t in _types) {
      await store.setMeta('cursor_$t', null);
    }
  }

  Future<void> _pull(SyncReport rep) async {
    try {
      // A different login or server (e.g. the phone is handed to another worker, or an admin signs in) makes the saved sync
      // position wrong: it would pull only the newest changes and miss everything older. Start from the beginning instead.
      final identity = await api.identity();
      final before = await store.meta('pull_identity');
      if (identity != null && before != identity) {
        if (before != null) await _resetCursors(); // first run after an update has no record yet: keep the position
        await store.setMeta('pull_identity', identity);
      }
      for (final type in _types) {
        var cursor = await store.meta('cursor_$type');
        // Server timestamps have 1-second resolution and the filter is strictly "after": a change made in the same second as
        // the stored cursor would be skipped forever. Always overlap by one second (re-applying a pulled record is idempotent).
        cursor = _overlap(cursor);
        for (var page = 0; page < 60; page++) {
          final res = await api.pull(since: cursor, types: [type], limit: 500);
          final (int, String?) applied;
          try {
            applied = await _applyPage(type, res);
          } on DatabaseException catch (e) {
            if (!e.toString().contains('FOREIGN KEY')) rethrow;
            // a record arrived whose parent (e.g. its visit) is not on the phone: the saved position is out of step with the
            // data. Forget it, so the next sync downloads everything again, parents first, and repairs itself.
            await _resetCursors();
            rep.retryable++;
            return;
          }
          final (count, lastTs) = applied;
          rep.pulled += count;
          if (count < 500 || lastTs == null) {
            if (lastTs != null) await store.setMeta('cursor_$type', lastTs);
            break;
          }
          // full page: step back one second so records sharing the boundary timestamp are not skipped (re-fetching is idempotent)
          final back = DateTime.parse(
            lastTs.endsWith('Z') ? lastTs : '${lastTs}Z',
          ).subtract(const Duration(seconds: 1));
          final next = back.toIso8601String().split('.').first;
          if (next == cursor) break; // >500 records in one second: cannot advance; stop instead of looping
          cursor = next;
          await store.setMeta('cursor_$type', cursor);
        }
      }
      // derived household fields may be stale after merging visits: recompute only households without unsynced edits
    } on NotConfigured {
      rethrow;
    } on Unauthorized catch (e) {
      rep.authFailed = true;
      rep.error = e;
    } on NetworkUnavailable catch (e) {
      rep.offline = true;
      rep.error = e;
    } on RequestTimeout catch (e) {
      rep.offline = true;
      rep.error = e;
    } on ApiException catch (e) {
      rep.error = e;
    }
  }

  static String? _overlap(String? ts) {
    if (ts == null) return null;
    final d = DateTime.parse(ts.endsWith('Z') ? ts : '${ts}Z')
        .subtract(const Duration(seconds: 1));
    return d.toIso8601String().split('.').first;
  }

  Future<(int, String?)> _applyPage(String type, PullResponse res) async {
    switch (type) {
      case 'household':
        final l = res.households ?? const [];
        await store.upsertHouseholds(l);
        return (
          l.length,
          l.isEmpty
              ? null
              : l
                    .map((e) => e.lastUpdated)
                    .reduce((a, b) => a.compareTo(b) >= 0 ? a : b),
        );
      case 'visit':
        final l = res.visits ?? const [];
        await store.upsertVisits(l);
        return (
          l.length,
          l.isEmpty
              ? null
              : l
                    .map((e) => e.updatedAt)
                    .reduce((a, b) => a.compareTo(b) >= 0 ? a : b),
        );
      default:
        final l = res.referrals ?? const [];
        await store.upsertReferrals(l);
        return (
          l.length,
          l.isEmpty
              ? null
              : l
                    .map((e) => e.lastUpdated)
                    .reduce((a, b) => a.compareTo(b) >= 0 ? a : b),
        );
    }
  }

  // ---------------------------------------------------------------- user actions on queued changes
  Future<void> retry(String opId) async {
    await store.updateOp(opId, {
      'state': 'PENDING',
      'last_error_code': null,
      'last_error_message': null,
    });
    onChanged?.call();
  }

  /// Give up on a change. Updates are rolled back to the saved "before" snapshot; created records are removed.
  Future<void> discard(String opId) async {
    final op = await store.op(opId);
    if (op == null) return;
    final table = switch (op.entityType) {
      'household' => 'households',
      'visit' => 'visits',
      _ => 'referrals',
    };
    final idCol = switch (op.entityType) {
      'household' => 'household_id',
      'visit' => 'visit_id',
      _ => 'referral_id',
    };
    await store.db.transaction((txn) async {
      if (op.opType == 'update' && op.beforeJson != null) {
        await txn.update(
          table,
          op.beforeJson!.map((k, v) => MapEntry(k, v)),
          where: '$idCol = ?',
          whereArgs: [op.entityId],
        );
      } else if (op.opType == 'create') {
        await txn.delete(table, where: '$idCol = ?', whereArgs: [op.entityId]);
      }
      await txn.delete('sync_outbox', where: 'op_id = ?', whereArgs: [opId]);
      final hh = op.entityType == 'visit'
          ? (op.beforeJson?['household_id'] ?? op.payload['household_id'])
          : null;
      if (hh != null) {
        await recomputeHousehold(
          txn,
          hh as String,
          clock.today(),
          recentDays: recentCompletionDays,
        );
      }
    });
    onChanged?.call();
  }

  /// keepServer: restore the pre-edit snapshot, then adopt the server's values for the conflicting fields and its version.
  /// keepMine: re-queue the same change as a NEW operation based on the server's current version (the server then applies it).
  Future<void> resolveConflict(String opId, {required bool keepServer}) async {
    final op = await store.op(opId);
    if (op == null || op.state != OpState.conflict || op.conflict == null) {
      return;
    }
    final c = op.conflict!;
    final serverVersion = c['server_version'] as int;
    final table = switch (op.entityType) {
      'household' => 'households',
      'visit' => 'visits',
      _ => 'referrals',
    };
    final idCol = switch (op.entityType) {
      'household' => 'household_id',
      'visit' => 'visit_id',
      _ => 'referral_id',
    };
    await store.db.transaction((txn) async {
      if (keepServer) {
        final restore = <String, Object?>{...?op.beforeJson};
        final sv = (c['server_values'] as Map<String, dynamic>? ?? {});
        sv.forEach((field, value) {
          final col = switch (field) {
            'visit_status' => 'visit_status',
            'referral_status' => 'referral_status',
            _ => field,
          };
          restore[col] = value is bool ? (value ? 1 : 0) : value;
        });
        restore['version'] = serverVersion;
        if (restore.isNotEmpty) {
          await txn.update(
            table,
            restore,
            where: '$idCol = ?',
            whereArgs: [op.entityId],
          );
        }
        await txn.delete('sync_outbox', where: 'op_id = ?', whereArgs: [opId]);
      } else {
        await txn.delete('sync_outbox', where: 'op_id = ?', whereArgs: [opId]);
        final fresh = OutboxOp(
          opId:
              '${op.opId.substring(0, 8)}-${DateTime.now().microsecondsSinceEpoch}',
          entityType: op.entityType,
          entityId: op.entityId,
          opType: op.opType,
          baseVersion: serverVersion,
          payload: op.payload,
          beforeJson: op.beforeJson,
          clientCreatedAt:
              '${clock.nowUtc().toIso8601String().split('.').first}Z',
        );
        await store.enqueue(txn, fresh);
        await txn.update(
          table,
          {'version': serverVersion + 1},
          where: '$idCol = ?',
          whereArgs: [op.entityId],
        );
      }
    });
    onChanged?.call();
  }
}
