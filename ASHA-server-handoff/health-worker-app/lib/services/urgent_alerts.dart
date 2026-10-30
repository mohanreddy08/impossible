import 'dart:async';
import 'dart:ui' show Locale;

import '../domain/rules/priority_rules.dart';
import '../l10n/app_localizations.dart';
import 'alert_notifier.dart';

/// Decides what to notify. Pure: no I/O, so it is easy to test.
///  * [fresh]  = urgent households that were NOT already notified (these raise a notification now)
///  * [keep]   = the IDs to remember as "already notified" (everyone urgent now; households that stopped being urgent drop out,
///               so they can alert again if they become urgent later)
class AlertPlan {
  const AlertPlan({
    required this.fresh,
    required this.keep,
    required this.urgentCount,
  });
  final List<HouseholdUrgency> fresh;
  final Set<String> keep;
  final int urgentCount;
}

AlertPlan planAlerts(
  List<HouseholdUrgency> ranked,
  Set<String> alreadyNotified,
) {
  final urgent = [
    for (final u in ranked)
      if (u.level == UrgencyLevel.urgent) u,
  ];
  final ids = {for (final u in urgent) u.householdId};
  return AlertPlan(
    fresh: [
      for (final u in urgent)
        if (!alreadyNotified.contains(u.householdId)) u,
    ],
    keep: ids,
    urgentCount: urgent.length,
  );
}

/// Turns the plan into notifications. Works fully offline.
class UrgentAlerts {
  UrgentAlerts({
    required this.notifier,
    required this.loadRanked,
    required this.readNotified,
    required this.writeNotified,
    required this.language,
    required this.enabled,
  });
  final AlertNotifier notifier;
  final Future<List<HouseholdUrgency>> Function() loadRanked;
  final Future<Set<String>> Function() readNotified;
  final Future<void> Function(Set<String>) writeNotified;
  final String Function() language;
  final bool Function() enabled;

  static const summaryId = 1; // one summary notification
  static const dailyId = 2; // the morning reminder
  static const _oneBase =
      1000; // up to 3 individual notifications use ids 1000..1002
  static const maxIndividual = 3;

  bool _busy = false;
  bool _again = false;

  /// Call after data changes (sync, a saved visit) and when the app starts. Safe to call often.
  Future<void> refresh() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _run();
      } while (_again);
    } finally {
      _busy = false;
    }
  }

  Future<void> _run() async {
    if (!enabled()) {
      await notifier.cancel(dailyId);
      // forget what was notified: switching alerts back on then tells the worker about everyone urgent right now
      await writeNotified(const {});
      return;
    }
    // no permission: show nothing AND remember nothing, so the alert still comes once the worker allows notifications
    if (!await notifier.canShow()) return;
    final l = lookupAppLocalizations(Locale(language()));
    final ranked = await loadRanked();
    final already = await readNotified();
    final plan = planAlerts(ranked, already);

    if (plan.fresh.isNotEmpty) {
      if (plan.fresh.length <= maxIndividual) {
        for (var i = 0; i < plan.fresh.length; i++) {
          await notifier.show(
            id: _oneBase + i,
            title: l.alertOneTitle(plan.fresh[i].householdId),
            body: l.alertOneBody,
          );
        }
      } else {
        await notifier.show(
          id: summaryId,
          title: l.alertManyTitle(plan.fresh.length),
          body: l.alertManyBody,
        );
      }
    }
    await writeNotified(plan.keep);

    if (plan.urgentCount > 0) {
      await notifier.scheduleDaily(
        id: dailyId,
        title: l.alertManyTitle(plan.urgentCount),
        body: l.alertManyBody,
      );
    } else {
      await notifier.cancel(dailyId);
    }
  }
}
