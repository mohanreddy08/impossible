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
import '../widgets/reveal.dart';
import '../../domain/rules/priority_rules.dart';
import '../../services/priority_service.dart';
import '../widgets/priority_card.dart';
import 'households_screen.dart';
import 'planner_screen.dart';
import 'priority_screen.dart';
import 'referrals_screen.dart';
import 'reports_screen.dart';
import 'sync_screen.dart';
import 'visit_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onGoTo});
  final void Function(int tab) onGoTo;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DashboardCounts? _counts;
  VisitWithHousehold? _next;
  List<HouseholdUrgency> _top = const [];
  bool _loading = true;
  int _seenVersion = -1;

  Future<void> _load() async {
    final s = context.read<AppServices>();
    final today = s.clock.today();
    final counts = await s.store.dashboard(today);
    final todayList = await s.store.plannedVisits('today', today, limit: 1);
    final overdue = await s.store.plannedVisits('overdue', today, limit: 1);
    final top = await PriorityService(s.store).ranked(today, limit: 3);
    if (!mounted) return;
    setState(() {
      _top = top;
      _counts = counts;
      _next = overdue.isNotEmpty
          ? overdue.first
          : (todayList.isNotEmpty ? todayList.first : null);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final bus = context.watch<DataBus>();
    if (_seenVersion != bus.version) {
      _seenVersion = bus.version;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final hour = DateTime.now().hour;
    final greet = hour < 12
        ? l.greetMorning
        : hour < 17
        ? l.greetAfternoon
        : l.greetEvening;
    final c = _counts;
    final now = s.clock.today();
    // very small screens (the header is already in compact mode there) keep only the title: no room for decoration
    final compact = MediaQuery.sizeOf(context).height < 640;
    return HeaderScaffold(
      title: l.homeQuestion,
      subtitle: compact ? greet : null,
      leading: _AshaMark(iconOnly: compact),
      eyebrow: compact
          ? null
          : _Greeting(
              icon: hour < 12
                  ? Icons.wb_sunny_rounded
                  : hour < 17
                  ? Icons.wb_twilight_rounded
                  : Icons.nights_stay_rounded,
              text: '$greet  ·  ${fmtWeekdayDate(context, now)}',
            ),
      headerExtra: compact ? null : const _AccentBar(),
      child: _loading
          ? const LoadingView()
          : (c == null || c.households == 0)
          ? _EmptyHome(
              onDemo: () async {
                await s.demo.load();
                await s.settings.setUseDemoDate(true);
                s.bus.changed();
              },
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 120),
              children: [
                if (_next != null) Reveal(child: _NextVisitCard(item: _next!)),
                const SizedBox(height: Tk.s16),
                Reveal(
                  index: 1,
                  child: TwoColumnGrid(
                    children: [
                      StatTile(
                        count: c.dueToday,
                        label: l.dueToday,
                        icon: Icons.today,
                        tone: Tone.info,
                        onTap: () => _push(const PlannerScreen(initialTab: 1)),
                      ),
                      StatTile(
                        count: c.overdue,
                        label: l.overdue,
                        icon: Icons.warning_amber_rounded,
                        tone: Tone.danger,
                        onTap: () => _push(const PlannerScreen(initialTab: 0)),
                      ),
                      StatTile(
                        count: c.upcoming,
                        label: l.upcoming,
                        icon: Icons.event_available,
                        tone: Tone.neutral,
                        onTap: () => _push(const PlannerScreen(initialTab: 2)),
                      ),
                      StatTile(
                        count: c.pendingReferrals,
                        label: l.pendingReferrals,
                        icon: Icons.local_hospital_outlined,
                        tone: Tone.warn,
                        onTap: () => _push(
                          const ReferralsScreen(initialFilter: 'pending'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_top.isNotEmpty) ...[
                  SectionHeader(
                    l.priorityTitle,
                    trailing: TextButton(
                      key: const Key('priority-see-all'),
                      onPressed: () => _push(const PriorityScreen()),
                      child: Text(l.prioritySeeAll),
                    ),
                  ),
                  for (var i = 0; i < _top.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Tk.s12),
                      child: Reveal(
                        index: 2 + i,
                        child: PriorityCard(
                          item: _top[i],
                          rank: i + 1,
                          onTap: () => _push(
                            HouseholdDetailScreen(
                              householdId: _top[i].householdId,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
                SectionHeader(l.quickActions),
                const SizedBox(height: Tk.s8),
                _QuickAction(
                  icon: Icons.mic,
                  label: l.askQuestion,
                  onTap: () => widget.onGoTo(2),
                  primary: true,
                ),
                const SizedBox(height: Tk.s12),
                TwoColumnGrid(
                  children: [
                    _ActionTile(
                      icon: Icons.event_note,
                      label: l.openPlanner,
                      onTap: () => _push(const PlannerScreen(initialTab: 1)),
                    ),
                    _ActionTile(
                      icon: Icons.local_hospital_outlined,
                      label: l.referralsAction,
                      onTap: () => _push(const ReferralsScreen()),
                    ),
                    _ActionTile(
                      icon: Icons.bar_chart,
                      label: l.reportsAction,
                      onTap: () => _push(const ReportsScreen()),
                    ),
                    _ActionTile(
                      icon: Icons.sync,
                      label: l.syncCentreAction,
                      onTap: () => _push(const SyncScreen()),
                    ),
                  ],
                ),
                const SizedBox(height: Tk.s12),
                Center(
                  child: Text(
                    l.householdsCount(c.households),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }

  void _push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.onDemo});
  final VoidCallback onDemo;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.cloud_download_outlined,
      title: l.emptyHomeTitle,
      body: l.emptyHomeBody,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            key: const Key('load-demo'),
            onPressed: onDemo,
            icon: const Icon(Icons.science_outlined),
            label: Text(l.loadDemo),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const SyncScreen())),
            icon: const Icon(Icons.sync),
            label: Text(l.syncNow),
          ),
        ],
      ),
    );
  }
}

class _NextVisitCard extends StatelessWidget {
  const _NextVisitCard({required this.item});
  final VisitWithHousehold item;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final today = context.read<AppServices>().clock.today();
    final p = priorityFor(
      item.visit.scheduledDate,
      today,
      item.visit.reason,
      null,
      hasOpenReferral: item.hasOpenReferral,
    );
    final reason = switch (p.bucket) {
      PriorityBucket.overdue => l.reasonOverdue(catName(l, p.category), p.days),
      PriorityBucket.today => l.reasonToday(catName(l, p.category)),
      PriorityBucket.upcoming => l.reasonUpcoming(
        catName(l, p.category),
        p.days,
      ),
    };
    return AppCard(
      gradient: Tk.heroGradient,
      padding: const EdgeInsets.all(Tk.s20),
      semanticLabel: '${l.nextVisit}: ${item.visit.householdId}. $reason',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VisitScreen(visitId: item.visit.visitId),
        ),
      ),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    l.nextVisit.toUpperCase(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tk.s8),
            Text(
              item.visit.householdId,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              reason,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: Tk.s16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Tk.tealDeep,
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            VisitScreen(visitId: item.visit.visitId),
                      ),
                    ),
                    icon: const Icon(Icons.edit_note),
                    label: Text(l.recordOutcome),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Tk.s8),
    child: AppCard(
      onTap: onTap,
      gradient: primary ? Tk.heroGradient : null,
      padding: const EdgeInsets.symmetric(horizontal: Tk.s16, vertical: Tk.s16),
      semanticLabel: label,
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: primary
                    ? Colors.white.withValues(alpha: 0.18)
                    : Tk.mintSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: primary ? Colors.white : Tk.primary),
            ),
            const SizedBox(width: Tk.s12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: primary ? Colors.white : Tk.text),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: primary ? Colors.white : Tk.textMuted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    semanticLabel: label,
    padding: const EdgeInsets.symmetric(horizontal: Tk.s12, vertical: Tk.s16),
    child: ExcludeSemantics(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Tk.mintSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Tk.primaryDark, size: 26),
          ),
          const SizedBox(height: Tk.s8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
}

/// The ASHA mark shown at the top-left of Home.
class _AshaMark extends StatelessWidget {
  const _AshaMark({this.iconOnly = false});
  final bool iconOnly;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      padding: EdgeInsets.fromLTRB(8, 6, iconOnly ? 8 : 14, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Tk.rChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 15,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.health_and_safety_rounded,
              size: 20,
              color: Tk.primary,
            ),
          ),
          if (!iconOnly) ...[
            const SizedBox(width: 8),
            const Text(
              'ASHA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Small line above the title: a sun / dusk / moon icon, the greeting and today's date.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: const Color(0xFFFFE9A8)),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    ],
  );
}

/// A short mint bar under the title: a small touch of design that ties into the brand colour.
class _AccentBar extends StatelessWidget {
  const _AccentBar();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 10),
    child: ExcludeSemantics(
      child: SizedBox(
        width: 48,
        height: 5,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFF9FD8CF),
            borderRadius: BorderRadius.all(Radius.circular(3)),
          ),
        ),
      ),
    ),
  );
}
