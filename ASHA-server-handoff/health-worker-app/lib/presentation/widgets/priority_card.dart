import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/rules/priority_rules.dart';
import '../../l10n/app_localizations.dart';
import '../format.dart';
import 'common.dart';

/// One household in the "attend first" list: urgency level (icon + word, never colour alone) and the reasons behind it.
class PriorityCard extends StatelessWidget {
  const PriorityCard({
    super.key,
    required this.item,
    required this.onTap,
    this.rank,
  });
  final HouseholdUrgency item;
  final VoidCallback onTap;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (tone, icon, word) = switch (item.level) {
      UrgencyLevel.urgent => (
        Tone.danger,
        Icons.priority_high_rounded,
        l.priorityUrgent,
      ),
      UrgencyLevel.soon => (Tone.warn, Icons.schedule, l.prioritySoon),
      UrgencyLevel.routine => (
        Tone.neutral,
        Icons.check_circle_outline,
        l.priorityRoutine,
      ),
    };
    final reasons = [
      for (final f in item.factors)
        switch (f.reason) {
          UrgencyReason.overdue => (
            Icons.event_busy,
            l.priorityWhyOverdue(f.value),
          ),
          UrgencyReason.dueToday => (Icons.today, l.priorityWhyToday),
          UrgencyReason.openReferral => (
            Icons.local_hospital_outlined,
            l.priorityWhyReferral(f.value),
          ),
          UrgencyReason.missedVisits => (
            Icons.person_off_outlined,
            l.priorityWhyMissed(f.value),
          ),
          UrgencyReason.visitType => (
            Icons.label_outline,
            l.priorityWhyType(catName(l, item.category ?? '')),
          ),
        },
    ];
    return AppCard(
      onTap: onTap,
      semanticLabel:
          '${item.householdId}. $word. ${reasons.map((r) => r.$2).join('. ')}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (rank != null) ...[
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Tk.mintSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Tk.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: Tk.s12),
                ],
                Expanded(
                  child: Text(
                    item.householdId,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusBadge(tone: tone, icon: icon, label: word, dense: true),
              ],
            ),
            const SizedBox(height: Tk.s8),
            for (final r in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(r.$1, size: 16, color: Tk.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        r.$2,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
