import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../data/local/local_store.dart';
import '../../domain/rules/visit_rules.dart';
import '../../l10n/app_localizations.dart';
import '../../services/data_bus.dart';
import '../../state/app_services.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';
import '../widgets/paged_list.dart';
import 'visit_screen.dart';

/// Daily visit planner: PLANNED visits in priority order (overdue first, most overdue first; then today; then soonest upcoming).
/// The ordering uses dates only; each row says why it is where it is. No clinical risk score exists or is invented.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key, this.initialTab = 1, this.embedded = false});
  final int initialTab; // 0 overdue, 1 today, 2 upcoming
  final bool embedded;
  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tabs = [
      (l.bucketOverdue, Icons.warning_amber_rounded, 'overdue'),
      (l.bucketToday, Icons.today, 'today'),
      (l.bucketUpcoming, Icons.event_available, 'upcoming'),
    ];
    final leading = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, Tk.s8),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == _tab,
                  label: tabs[i].$1,
                  excludeSemantics: true,
                  child: InkWell(
                    key: ValueKey('planner-tab-$i'),
                    borderRadius: BorderRadius.circular(Tk.rChip),
                    onTap: () => setState(() => _tab = i),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: i == _tab ? Tk.primaryDark : Colors.white,
                        borderRadius: BorderRadius.circular(Tk.rChip),
                        border: Border.all(
                          color: i == _tab ? Tk.primaryDark : Tk.border,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            tabs[i].$2,
                            size: 16,
                            color: i == _tab ? Colors.white : Tk.primaryDark,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                tabs[i].$1,
                                maxLines: 1,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: i == _tab ? Colors.white : Tk.text,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (i < tabs.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tk.s16),
        child: Text(
          l.priorityExplainer,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ];
    return HeaderScaffold(
      title: l.plannerTitle,
      showBack: !widget.embedded,
      child: _BucketList(
        key: ValueKey(tabs[_tab].$3),
        bucket: tabs[_tab].$3,
        leading: leading,
      ),
    );
  }
}

class _BucketList extends StatefulWidget {
  const _BucketList({super.key, required this.bucket, required this.leading});
  final String bucket;
  final List<Widget> leading;
  @override
  State<_BucketList> createState() => _BucketListState();
}

class _BucketListState extends State<_BucketList> {
  PagedLoader<VisitWithHousehold>? _loader;
  int _seen = -1;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _loader?.loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _loader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppServices>();
    final bus = context.watch<DataBus>();
    _loader ??= PagedLoader(
      (o, n) => s.store.plannedVisits(
        widget.bucket,
        s.clock.today(),
        limit: n,
        offset: o,
      ),
    )..addListener(() => mounted ? setState(() {}) : null);
    if (_seen != bus.version) {
      _seen = bus.version;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loader?.reset());
    }
    final l = AppLocalizations.of(context);
    final today = s.clock.today();
    return pagedScrollView<VisitWithHousehold>(
      controller: _scroll,
      leading: widget.leading,
      loader: _loader!,
      loading: const LoadingView(),
      empty: EmptyState(
        icon: Icons.event_available,
        title: widget.bucket == 'today' ? l.noVisitsToday : l.noResults,
      ),
      error: () => ErrorState(message: l.errUnknown, onRetry: _loader!.reset),
      padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s12, Tk.s16, 120),
      itemBuilder: (c, it) => VisitTile(item: it, today: today),
    );
  }
}

class VisitTile extends StatelessWidget {
  const VisitTile({super.key, required this.item, required this.today});
  final VisitWithHousehold item;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final v = item.visit;
    final p = priorityFor(
      v.scheduledDate,
      today,
      v.reason,
      null,
      hasOpenReferral: item.hasOpenReferral,
    );
    final (tone, icon, bucketLabel) = switch (p.bucket) {
      PriorityBucket.overdue => (
        Tone.danger,
        Icons.warning_amber_rounded,
        l.bucketOverdue,
      ),
      PriorityBucket.today => (Tone.info, Icons.today, l.bucketToday),
      PriorityBucket.upcoming => (
        Tone.neutral,
        Icons.event_available,
        l.bucketUpcoming,
      ),
    };
    final reason = switch (p.bucket) {
      PriorityBucket.overdue => l.reasonOverdue(catName(l, v.reason), p.days),
      PriorityBucket.today => l.reasonToday(catName(l, v.reason)),
      PriorityBucket.upcoming => l.reasonUpcoming(catName(l, v.reason), p.days),
    };
    return AppCard(
      key: ValueKey('visit-${v.visitId}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VisitScreen(visitId: v.visitId),
        ),
      ),
      semanticLabel:
          '${v.householdId}. $bucketLabel. $reason. ${fmtDate(context, v.scheduledDate)}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    v.householdId,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusBadge(
                  tone: tone,
                  icon: icon,
                  label: bucketLabel,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(reason, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: Tk.textMuted,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    fmtDate(context, v.scheduledDate),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (item.hasOpenReferral) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.local_hospital_outlined,
                    size: 16,
                    color: Tk.warn,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      l.openReferralNote,
                      style: const TextStyle(
                        color: Tk.warn,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
