import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/clock.dart';
import '../data/local/local_store.dart';
import '../data/models/household.dart';
import '../data/models/outbox_op.dart';
import '../data/models/referral.dart';
import '../data/models/visit.dart';
import '../domain/rules/visit_rules.dart';
import 'data_bus.dart';

/// Thrown for user-fixable input problems. [errors] maps a field key to a stable code that the UI localises.
class DomainValidation implements Exception {
  DomainValidation(this.errors);
  final Map<String, String> errors;
  @override
  String toString() => 'DomainValidation($errors)';
}

class ReferralDraft {
  const ReferralDraft({
    required this.facilityId,
    required this.serviceCategory,
  });
  final String facilityId, serviceCategory;
}

class VisitOutcome {
  const VisitOutcome({
    required this.status,
    this.actualDate,
    this.followupRequired,
    this.nextFollowupDate,
    this.referral,
    this.visitTime,
    this.visitTimeAuto = true,
  });
  final String status; // COMPLETED | MISSED | CANCELLED

  /// 'HH:mm' (24 h) the worker went; saved ON THE PHONE ONLY (the server has no field for a visit's time). Ignored for CANCELLED.
  final String? visitTime;
  final bool visitTimeAuto;
  final DateTime? actualDate, nextFollowupDate;
  final bool? followupRequired;
  final ReferralDraft? referral;
}

const _uuid = Uuid();
String _shortId(String prefix) =>
    '$prefix-${_uuid.v4().replaceAll('-', '').substring(0, 10).toUpperCase()}';
String _ts(DateTime utc) => '${utc.toIso8601String().split('.').first}Z';

/// Offline write path. EVERY change is persisted locally and queued in the outbox inside ONE SQLite transaction,
/// so an app kill can never leave a change that is saved but not queued (or queued but not saved).
class FieldWorkService {
  FieldWorkService(
    this.store,
    this.clock,
    this.bus, {
    this.recentCompletionDays = 14,
    this.onWrite,
  });
  final void Function()? onWrite;
  final LocalStore store;
  final AppClock clock;
  final DataBus bus;
  final int recentCompletionDays;

  OutboxOp _op(
    String type,
    String id,
    String opType,
    Map<String, dynamic> payload, {
    int? base,
    Map<String, dynamic>? before,
  }) => OutboxOp(
    opId: _uuid.v4(),
    entityType: type,
    entityId: id,
    opType: opType,
    baseVersion: base,
    payload: payload,
    beforeJson: before,
    clientCreatedAt: _ts(clock.nowUtc()),
    clientUpdatedAt: _ts(clock.nowUtc()),
  );

  // ---------------------------------------------------------------- households
  static final _villageId = RegExp(r'^[A-Za-z0-9_-]{2,32}$');

  /// Registers a NEW family on this phone and queues it for the server, all in one transaction (works offline). The id is chosen
  /// here (like visits), so a retry can never create the family twice. Returns the new household id.
  Future<String> addHousehold({
    required String villageId,
    required int memberCount,
    required List<String> categories,
  }) async {
    final village = villageId.trim();
    final err = <String, String>{};
    if (!_villageId.hasMatch(village)) err['village'] = 'invalid';
    if (memberCount < 1 || memberCount > 60) err['members'] = 'invalid';
    final cats = <String>[
      for (final c in followupCategories)
        if (categories.contains(c)) c,
    ];
    if (cats.isEmpty) err['categories'] = 'empty';
    final worker = await store.currentWorkerId();
    if (worker == null || worker.isEmpty) err['worker'] = 'unknown';
    if (err.isNotEmpty) throw DomainValidation(err);
    final id = _shortId('HH');
    final now = _ts(clock.nowUtc());
    await store.db.transaction((txn) async {
      final h = Household(
        householdId: id,
        villageId: village,
        assignedWorkerId: worker!,
        memberCount: memberCount,
        eligibleCategories: cats,
        recordStatus: 'NO_VISIT_DUE',
        lastUpdated: now,
        version: 1,
      );
      await txn.insert('households', h.toRow());
      await store.enqueue(
        txn,
        _op('household', id, 'create', {
          'village_id': village,
          'assigned_worker_id': worker,
          'household_member_count': memberCount,
          'eligible_followup_categories': cats,
        }),
      );
    });
    bus.changed();
    onWrite?.call();
    return id;
  }

  // ---------------------------------------------------------------- visits
  Future<void> recordOutcome(String visitId, VisitOutcome o) async {
    final v = await store.visit(visitId);
    if (v == null) throw DomainValidation({'visit': 'notFound'});
    final today = clock.today();
    final err = <String, String>{};
    if (v.status != 'PLANNED') err['status'] = 'alreadyFinal';
    if (!['COMPLETED', 'MISSED', 'CANCELLED'].contains(o.status)) {
      err['status'] = 'invalidStatus';
    }
    if (o.status == 'COMPLETED') {
      if (o.actualDate == null) {
        err['actualDate'] = 'required';
      } else if (o.actualDate!.isAfter(today)) {
        err['actualDate'] = 'future';
      }
    }
    if (o.status != 'CANCELLED' && o.visitTime != null) {
      final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(o.visitTime!);
      if (m == null) {
        err['visitTime'] = 'invalid';
      } else if (o.status == 'COMPLETED' && o.actualDate == today) {
        final n = clock.localNow();
        final mins = int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
        if (mins > n.hour * 60 + n.minute + 1) {
          err['visitTime'] =
              'future'; // a visit cannot have happened later today than now
        }
      }
    }
    final visitDate = o.actualDate ?? v.scheduledDate;
    if (o.followupRequired == false && o.nextFollowupDate != null) {
      err['nextDate'] = 'inconsistent';
    }
    if (o.followupRequired == true &&
        o.nextFollowupDate == null &&
        o.status != 'CANCELLED') {
      err['nextDate'] = 'required';
    }
    if (o.nextFollowupDate != null && !o.nextFollowupDate!.isAfter(visitDate)) {
      err['nextDate'] = 'notAfterVisit';
    }
    if (o.referral != null && o.status != 'COMPLETED') {
      err['referral'] = 'needsCompletedVisit';
    }
    if (err.isNotEmpty) throw DomainValidation(err);

    final now = _ts(clock.nowUtc());
    await store.db.transaction((txn) async {
      final before = v.toRow();
      var updated = v.copyWith(
        status: o.status,
        actualVisitDate: o.status == 'COMPLETED' ? o.actualDate : null,
        followupRequired: o.followupRequired,
        nextFollowupDate: o.nextFollowupDate,
        updatedAt: now,
        version: v.version + 1,
      );
      final payload = <String, dynamic>{
        'visit_status': o.status,
        if (o.status == 'COMPLETED')
          'actual_visit_date': isoDate(o.actualDate!),
        // the server stores the time only on COMPLETED visits (a could-not-visit time stays on the phone)
        if (o.status == 'COMPLETED' && o.visitTime != null)
          'actual_visit_time': o.visitTime,
        if (o.followupRequired != null) 'followup_required': o.followupRequired,
        if (o.nextFollowupDate != null)
          'next_followup_date': isoDate(o.nextFollowupDate!),
        'create_followup_task': false, // the next visit is queued explicitly below with a client-chosen id
      };
      await txn.update(
        'visits',
        updated.toRow(),
        where: 'visit_id = ?',
        whereArgs: [v.visitId],
      );
      if (o.status != 'CANCELLED' && o.visitTime != null) {
        // same transaction as the visit itself: the time and the outcome are saved together or not at all
        await store.putVisitTime(
          txn,
          v.visitId,
          VisitTime(o.visitTime!, o.visitTimeAuto),
          now,
        );
      }
      await store.enqueue(
        txn,
        _op(
          'visit',
          v.visitId,
          'update',
          payload,
          base: v.version,
          before: before,
        ),
      );

      if (o.nextFollowupDate != null && o.followupRequired != false) {
        await _insertPlanned(
          txn,
          v.householdId,
          v.workerId,
          o.nextFollowupDate!,
          v.reason,
          now,
        );
      }
      if (o.referral != null) {
        final rid = _shortId('REF');
        final r = Referral(
          referralId: rid,
          householdId: v.householdId,
          visitId: v.visitId,
          facilityId: o.referral!.facilityId,
          serviceCategory: o.referral!.serviceCategory,
          createdDate: today,
          status: 'RECOMMENDED',
          attendanceConfirmed: false,
          recordState: 'ACTIVE',
          lastUpdated: now,
          version: 1,
        );
        await txn.insert('referrals', r.toRow());
        await store.enqueue(
          txn,
          _op('referral', rid, 'create', {
            'household_id': v.householdId,
            'visit_id': v.visitId,
            'facility_id': r.facilityId,
            'service_category': r.serviceCategory,
            'referral_created_date': isoDate(today),
            'referral_status': 'RECOMMENDED',
          }),
        );
        updated = updated.copyWith(
          referralId: rid,
          referralStatus: 'RECOMMENDED',
        );
        await txn.update(
          'visits',
          updated.toRow(),
          where: 'visit_id = ?',
          whereArgs: [v.visitId],
        );
      }
      await recomputeHousehold(
        txn,
        v.householdId,
        today,
        recentDays: recentCompletionDays,
      );
    });
    bus.changed();
    onWrite?.call();
  }

  Future<void> _insertPlanned(
    DatabaseExecutor txn,
    String householdId,
    String workerId,
    DateTime date,
    String reason,
    String now,
  ) async {
    final id = _shortId('VIS');
    final nv = Visit(
      visitId: id,
      householdId: householdId,
      workerId: workerId,
      scheduledDate: date,
      status: 'PLANNED',
      reason: reason,
      recordedAt: now,
      updatedAt: now,
      version: 1,
    );
    await txn.insert('visits', nv.toRow());
    await store.enqueue(
      txn,
      _op('visit', id, 'create', {
        'household_id': householdId,
        'worker_id': workerId,
        'scheduled_date': isoDate(date),
        'visit_reason': reason,
        'visit_status': 'PLANNED',
      }),
    );
  }

  Future<void> scheduleVisit(
    String householdId,
    DateTime date,
    String category,
  ) async {
    final today = clock.today();
    final err = <String, String>{};
    if (date.isBefore(today)) err['date'] = 'inPast';
    if (!followupCategories.contains(category)) err['category'] = 'invalid';
    if (err.isNotEmpty) throw DomainValidation(err);
    final h = await store.household(householdId);
    if (h == null) throw DomainValidation({'household': 'notFound'});
    await store.db.transaction((txn) async {
      await _insertPlanned(
        txn,
        householdId,
        h.assignedWorkerId,
        date,
        category,
        _ts(clock.nowUtc()),
      );
      await recomputeHousehold(
        txn,
        householdId,
        today,
        recentDays: recentCompletionDays,
      );
    });
    bus.changed();
    onWrite?.call();
  }

  // ---------------------------------------------------------------- referrals
  /// RECOMMENDED -> PLANNED (or change the planned date). Never produces "attendance confirmed": that only comes from the hospital via the server.
  Future<void> planReferral(String referralId, DateTime plannedDate) async {
    final r = await store.referral(referralId);
    if (r == null) throw DomainValidation({'referral': 'notFound'});
    final err = <String, String>{};
    if (r.recordState != 'ACTIVE') err['referral'] = 'notActive';
    if (r.phase == ReferralPhase.attendanceConfirmed) {
      err['referral'] = 'confirmedImmutable';
    }
    if (plannedDate.isBefore(r.createdDate)) {
      err['plannedDate'] = 'beforeCreated';
    }
    if (err.isNotEmpty) throw DomainValidation(err);
    final now = _ts(clock.nowUtc());
    await store.db.transaction((txn) async {
      final before = r.toRow();
      final u = r.copyWith(
        status: 'PLANNED',
        plannedVisitDate: plannedDate,
        lastUpdated: now,
        version: r.version + 1,
      );
      await txn.update(
        'referrals',
        u.toRow(),
        where: 'referral_id = ?',
        whereArgs: [referralId],
      );
      await txn.update(
        'visits',
        {'referral_status': 'PLANNED'},
        where: 'visit_id = ? AND referral_id = ?',
        whereArgs: [r.visitId, referralId],
      );
      await store.enqueue(
        txn,
        _op(
          'referral',
          referralId,
          'update',
          {
            'referral_status': 'PLANNED',
            'planned_visit_date': isoDate(plannedDate),
          },
          base: r.version,
          before: before,
        ),
      );
    });
    bus.changed();
    onWrite?.call();
  }

  Future<void> cancelReferral(String referralId) async {
    final r = await store.referral(referralId);
    if (r == null) throw DomainValidation({'referral': 'notFound'});
    if (r.recordState != 'ACTIVE') {
      throw DomainValidation({'referral': 'notActive'});
    }
    if (r.phase == ReferralPhase.attendanceConfirmed) {
      throw DomainValidation({'referral': 'confirmedImmutable'});
    }
    final now = _ts(clock.nowUtc());
    await store.db.transaction((txn) async {
      final before = r.toRow();
      final u = r.copyWith(
        recordState: 'CANCELLED',
        lastUpdated: now,
        version: r.version + 1,
      );
      await txn.update(
        'referrals',
        u.toRow(),
        where: 'referral_id = ?',
        whereArgs: [referralId],
      );
      await txn.update(
        'visits',
        {'referral_status': 'NONE', 'referral_id': null},
        where: 'visit_id = ? AND referral_id = ?',
        whereArgs: [r.visitId, referralId],
      );
      await store.enqueue(
        txn,
        _op(
          'referral',
          referralId,
          'update',
          {'record_state': 'CANCELLED'},
          base: r.version,
          before: before,
        ),
      );
    });
    bus.changed();
    onWrite?.call();
  }
}
