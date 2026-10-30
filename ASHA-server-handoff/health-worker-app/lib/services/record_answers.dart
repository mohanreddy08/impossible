import '../core/clock.dart';
import '../data/local/local_store.dart';
import '../data/models/household.dart';
import '../domain/rules/priority_rules.dart';
import 'priority_service.dart';

enum RecordIntent {
  priority,
  overdue,
  dueToday,
  openReferrals,
  household,
  householdCount,
}

/// An answer taken from the phone's OWN register (households, visits, referrals). It states facts about records; it never gives
/// medical advice, and it works offline.
class RecordAnswer {
  const RecordAnswer(
    this.intent, {
    this.count = 0,
    this.items = const [],
    this.householdId,
    this.household,
    this.urgency,
  });
  final RecordIntent intent;
  final int count;
  final List<HouseholdUrgency> items;
  final String? householdId;
  final Household? household; // null for intent == household means "not found"
  final HouseholdUrgency? urgency;
}

/// Recognises questions about the worker's own list (English, Telugu script and common spellings) and answers them from the
/// local database. Deliberately narrow: a question is only claimed when it clearly asks about visits, referrals or households.
class RecordAnswerer {
  RecordAnswerer(this.store, this.clock);
  final LocalStore store;
  final AppClock clock;

  static final _id = RegExp(
    r'\bhh-[a-z0-9]+(?:-[a-z0-9]+)*\b',
    caseSensitive: false,
  );
  static final _priority = RegExp(
    r'urgent|priorit|attend (?:\w+ )?first|see (?:\w+ )?first|who (?:should|do|to) .{0,25}(?:first|visit|attend)|most (?:urgent|needy)|అత్యవసర|ప్రాధాన్య|ముందు ఎవరిని|ఎవరిని ముందు',
    caseSensitive: false,
    unicode: true,
  );
  static final _overdue = RegExp(
    r'overdue|ఆలస్య',
    caseSensitive: false,
    unicode: true,
  );
  static final _today = RegExp(
    r'(?:today|ఈ రోజు|నేడు|ఇవాళ).{0,40}(?:visit|due|list|household|schedule|సందర్శ|ఇళ్ల|ఇల్లు|జాబితా)|(?:visit|due|list|household|schedule|సందర్శ|ఇళ్ల|ఇల్లు|జాబితా).{0,40}(?:today|ఈ రోజు|నేడు|ఇవాళ)',
    caseSensitive: false,
    unicode: true,
  );
  static final _referrals = RegExp(
    r'referrals|రెఫరల్',
    caseSensitive: false,
    unicode: true,
  );
  static final _count = RegExp(
    r'how many (?:households|houses|families)|number of (?:households|houses)|ఎన్ని ఇళ్ల',
    caseSensitive: false,
    unicode: true,
  );

  RecordIntent? recognise(String q) {
    if (_id.hasMatch(q)) return RecordIntent.household;
    if (_count.hasMatch(q)) return RecordIntent.householdCount;
    if (_priority.hasMatch(q)) return RecordIntent.priority;
    if (_overdue.hasMatch(q)) return RecordIntent.overdue;
    if (_today.hasMatch(q)) return RecordIntent.dueToday;
    if (_referrals.hasMatch(q)) return RecordIntent.openReferrals;
    return null;
  }

  Future<RecordAnswer?> answer(String q) async {
    final intent = recognise(q);
    if (intent == null) return null;
    final today = clock.today();
    switch (intent) {
      case RecordIntent.household:
        final id = _id.firstMatch(q)!.group(0)!.toUpperCase();
        final h = await store.household(id);
        if (h == null) {
          return RecordAnswer(intent, householdId: id);
        }
        final all = await PriorityService(store).ranked(today);
        final u = all.where((x) => x.householdId == id).firstOrNull;
        return RecordAnswer(intent, householdId: id, household: h, urgency: u);
      case RecordIntent.householdCount:
        final n = (await store.dashboard(today)).households;
        return RecordAnswer(intent, count: n);
      case RecordIntent.priority:
        final all = await PriorityService(store).ranked(today);
        return RecordAnswer(
          intent,
          count: all.length,
          items: all.take(5).toList(),
        );
      case RecordIntent.overdue:
      case RecordIntent.dueToday:
      case RecordIntent.openReferrals:
        final want = switch (intent) {
          RecordIntent.overdue => UrgencyReason.overdue,
          RecordIntent.dueToday => UrgencyReason.dueToday,
          _ => UrgencyReason.openReferral,
        };
        final all = await PriorityService(store).ranked(today);
        final subset = all
            .where((u) => u.factors.any((f) => f.reason == want))
            .toList();
        return RecordAnswer(
          intent,
          count: subset.length,
          items: subset.take(5).toList(),
        );
    }
  }
}
