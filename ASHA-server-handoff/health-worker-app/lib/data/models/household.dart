import '../../core/clock.dart';

const followupCategories = [
  'ANC',
  'IMMUNISATION',
  'NUTRITION',
  'HYPERTENSION',
  'DIABETES',
  'ROUTINE',
];

class Household {
  const Household({
    required this.householdId,
    required this.villageId,
    required this.assignedWorkerId,
    required this.memberCount,
    required this.eligibleCategories,
    this.lastVisitDate,
    this.nextVisitDueDate,
    this.scheduledCategory,
    required this.recordStatus,
    required this.lastUpdated,
    required this.version,
    this.lat,
    this.lng,
  });

  final String householdId,
      villageId,
      assignedWorkerId,
      recordStatus,
      lastUpdated;
  final int memberCount, version;
  final List<String> eligibleCategories;
  final DateTime? lastVisitDate, nextVisitDueDate;
  final String? scheduledCategory;

  /// Where the house is. Read from the demo seed / a pack only; stored in household_geo, never in the households table.
  final double? lat, lng;

  factory Household.fromJson(Map<String, dynamic> j) => Household(
    householdId: j['household_id'] as String,
    villageId: j['village_id'] as String,
    assignedWorkerId: j['assigned_worker_id'] as String,
    memberCount: j['household_member_count'] as int,
    eligibleCategories: List<String>.from(
      j['eligible_followup_categories'] as List,
    ),
    lastVisitDate: parseDate(j['last_visit_date'] as String?),
    nextVisitDueDate: parseDate(j['next_visit_due_date'] as String?),
    scheduledCategory: j['scheduled_followup_category'] as String?,
    recordStatus: j['record_status'] as String,
    lastUpdated: j['last_updated'] as String,
    version: j['version'] as int,
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
  );

  factory Household.fromRow(Map<String, Object?> r) => Household(
    householdId: r['household_id']! as String,
    villageId: r['village_id']! as String,
    assignedWorkerId: r['assigned_worker_id']! as String,
    memberCount: r['household_member_count']! as int,
    eligibleCategories: (r['eligible_followup_categories']! as String)
        .split('|')
        .where((e) => e.isNotEmpty)
        .toList(),
    lastVisitDate: parseDate(r['last_visit_date'] as String?),
    nextVisitDueDate: parseDate(r['next_visit_due_date'] as String?),
    scheduledCategory: r['scheduled_followup_category'] as String?,
    recordStatus: r['record_status']! as String,
    lastUpdated: r['last_updated']! as String,
    version: r['version']! as int,
  );

  Map<String, Object?> toRow() => {
    'household_id': householdId,
    'village_id': villageId,
    'assigned_worker_id': assignedWorkerId,
    'household_member_count': memberCount,
    'eligible_followup_categories': '|${eligibleCategories.join('|')}|',
    'last_visit_date': lastVisitDate == null ? null : isoDate(lastVisitDate!),
    'next_visit_due_date': nextVisitDueDate == null
        ? null
        : isoDate(nextVisitDueDate!),
    'scheduled_followup_category': scheduledCategory,
    'record_status': recordStatus,
    'last_updated': lastUpdated,
    'version': version,
  };
}
