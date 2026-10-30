import 'package:health_companion/data/models/household.dart';
import 'package:health_companion/data/models/referral.dart';
import 'package:health_companion/data/models/visit.dart';

final today = DateTime(2026, 10, 13);

Household hh(
  String id, {
  String status = 'NO_VISIT_DUE',
  String village = 'VIL-1',
  List<String> cats = const ['ROUTINE'],
  DateTime? next,
  DateTime? last,
  String? scheduled,
  int version = 1,
}) => Household(
  householdId: id,
  villageId: village,
  assignedWorkerId: 'WRK-1',
  memberCount: 4,
  eligibleCategories: cats,
  nextVisitDueDate: next,
  lastVisitDate: last,
  scheduledCategory: scheduled,
  recordStatus: status,
  lastUpdated: '2026-10-01T10:00:00Z',
  version: version,
);

Visit vis(
  String id,
  String hid,
  DateTime sched, {
  String status = 'PLANNED',
  String reason = 'ROUTINE',
  DateTime? actual,
  int version = 1,
  String referralStatus = 'NONE',
  String? referralId,
}) => Visit(
  visitId: id,
  householdId: hid,
  workerId: 'WRK-1',
  scheduledDate: sched,
  actualVisitDate: actual,
  status: status,
  reason: reason,
  referralStatus: referralStatus,
  referralId: referralId,
  recordedAt: '2026-10-01T10:00:00Z',
  updatedAt: '2026-10-01T10:00:00Z',
  version: version,
);

Referral ref(
  String id,
  String hid,
  String vid, {
  String status = 'RECOMMENDED',
  String state = 'ACTIVE',
  String facility = 'FAC-1',
  String cat = 'GENERAL',
  DateTime? created,
  DateTime? planned,
  bool confirmed = false,
  String? record,
  int version = 1,
}) => Referral(
  referralId: id,
  householdId: hid,
  visitId: vid,
  facilityId: facility,
  serviceCategory: cat,
  createdDate: created ?? DateTime(2026, 9, 1),
  plannedVisitDate: planned,
  status: status,
  attendanceConfirmed: confirmed,
  attendanceRecordId: record,
  recordState: state,
  lastUpdated: '2026-10-01T10:00:00Z',
  version: version,
);
