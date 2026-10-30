import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/referral.dart';
import '../../l10n/app_localizations.dart';
import '../../services/data_bus.dart';
import '../../services/field_work_service.dart';
import '../../state/app_services.dart';
import '../format.dart';
import '../validation_text.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';
import '../widgets/paged_list.dart';

/// Wording/icon/tone for a referral. "Attendance confirmed" appears ONLY for ReferralPhase.attendanceConfirmed
/// (a real hospital attendance record); every other state says attendance is NOT confirmed.
({String label, IconData icon, Tone tone}) phaseStyle(
  AppLocalizations l,
  ReferralPhase p,
) => switch (p) {
  ReferralPhase.recommended => (
    label: l.phaseRecommended,
    icon: Icons.outlined_flag,
    tone: Tone.warn,
  ),
  ReferralPhase.planned => (
    label: l.phasePlanned,
    icon: Icons.event,
    tone: Tone.info,
  ),
  ReferralPhase.attendanceConfirmed => (
    label: l.phaseConfirmed,
    icon: Icons.verified_outlined,
    tone: Tone.ok,
  ),
  ReferralPhase.cancelled => (
    label: l.phaseCancelled,
    icon: Icons.cancel_outlined,
    tone: Tone.neutral,
  ),
  ReferralPhase.invalid => (
    label: l.phaseInvalid,
    icon: Icons.report_outlined,
    tone: Tone.neutral,
  ),
  ReferralPhase.duplicate => (
    label: l.phaseDuplicate,
    icon: Icons.content_copy_outlined,
    tone: Tone.neutral,
  ),
};

class ReferralTile extends StatelessWidget {
  const ReferralTile({super.key, required this.r, this.unsynced = false});
  final Referral r;
  final bool unsynced;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final st = phaseStyle(l, r.phase);
    return AppCard(
      key: ValueKey('ref-${r.referralId}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReferralDetailScreen(referralId: r.referralId),
        ),
      ),
      semanticLabel:
          '${r.householdId}. ${st.label}. ${catName(l, r.serviceCategory)}. ${r.facilityId}${unsynced ? '. ${l.unsyncedBadge}' : ''}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.householdId,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (unsynced)
                  StatusBadge(
                    tone: Tone.warn,
                    icon: Icons.sync_problem_outlined,
                    label: l.unsyncedBadge,
                    dense: true,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            StatusBadge(tone: st.tone, icon: st.icon, label: st.label),
            const SizedBox(height: 6),
            Text(
              '${catName(l, r.serviceCategory)} · ${r.facilityId}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              r.plannedVisitDate != null
                  ? l.plannedOn(fmtDate(context, r.plannedVisitDate))
                  : l.createdOn(fmtDate(context, r.createdDate)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key, this.initialFilter = 'all'});
  final String initialFilter;
  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  late String _filter = widget.initialFilter;
  PagedLoader<Referral>? _loader;
  Set<String> _unsynced = {};
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

  Future<void> _refresh() async {
    final s = context.read<AppServices>();
    final u = await s.store.unsyncedEntityIds('referral');
    if (mounted) setState(() => _unsynced = u);
    await _loader?.reset();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final bus = context.watch<DataBus>();
    _loader ??= PagedLoader(
      (o, n) => s.store.pageReferrals(_filter, limit: n, offset: o),
    )..addListener(() => mounted ? setState(() {}) : null);
    if (_seen != bus.version) {
      _seen = bus.version;
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
    final filters = {
      'all': l.refFilterAll,
      'pending': l.refFilterOpen,
      'recommended': l.refFilterRecommended,
      'planned': l.refFilterPlanned,
      'confirmed': l.refFilterConfirmed,
      'closed': l.refFilterClosed,
    };
    final leading = <Widget>[
      SizedBox(
        height: 68,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s12, Tk.s16, Tk.s8),
          children: [
            for (final e in filters.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Semantics(
                  button: true,
                  selected: _filter == e.key,
                  label: e.value,
                  excludeSemantics: true,
                  child: InkWell(
                    key: ValueKey('ref-filter-${e.key}'),
                    borderRadius: BorderRadius.circular(Tk.rChip),
                    onTap: () {
                      setState(() => _filter = e.key);
                      _refresh();
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: _filter == e.key ? Tk.primaryDark : Colors.white,
                        borderRadius: BorderRadius.circular(Tk.rChip),
                        border: Border.all(
                          color: _filter == e.key ? Tk.primaryDark : Tk.border,
                        ),
                      ),
                      child: Text(
                        e.value,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _filter == e.key ? Colors.white : Tk.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tk.s16),
        child: Banner2(
          tone: Tone.info,
          icon: Icons.info_outline,
          text: l.attendanceNote,
        ),
      ),
    ];
    return HeaderScaffold(
      title: l.referralsTitle,
      showBack: true,
      child: pagedScrollView<Referral>(
        controller: _scroll,
        leading: leading,
        loader: _loader!,
        loading: const LoadingView(),
        empty: EmptyState(
          icon: Icons.local_hospital_outlined,
          title: l.noResults,
        ),
        error: () => ErrorState(message: l.errUnknown, onRetry: _loader!.reset),
        padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s12, Tk.s16, 120),
        itemBuilder: (c, r) =>
            ReferralTile(r: r, unsynced: _unsynced.contains(r.referralId)),
      ),
    );
  }
}

class ReferralDetailScreen extends StatefulWidget {
  const ReferralDetailScreen({super.key, required this.referralId});
  final String referralId;
  @override
  State<ReferralDetailScreen> createState() => _ReferralDetailScreenState();
}

class _ReferralDetailScreenState extends State<ReferralDetailScreen> {
  Referral? _r;
  bool _unsynced = false, _loading = true;
  int _seen = -1;

  Future<void> _load() async {
    final s = context.read<AppServices>();
    final r = await s.store.referral(widget.referralId);
    final u = await s.store.hasUnsyncedOps('referral', widget.referralId);
    if (mounted) {
      setState(() {
        _r = r;
        _unsynced = u;
        _loading = false;
      });
    }
  }

  Future<void> _plan() async {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final messenger = ScaffoldMessenger.of(context);
    final r = _r!;
    final d = await showDatePicker(
      context: context,
      initialDate:
          r.plannedVisitDate ??
          (s.clock.today().isBefore(r.createdDate)
              ? r.createdDate
              : s.clock.today()),
      firstDate: r.createdDate,
      lastDate: DateTime(2035),
      helpText: l.setPlannedDate,
    );
    if (d == null) return;
    try {
      await s.fieldWork.planReferral(
        r.referralId,
        DateTime(d.year, d.month, d.day),
      );
      messenger.showSnackBar(SnackBar(content: Text(l.savedOffline)));
    } on DomainValidation catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            validationText(l, e.errors.keys.first, e.errors.values.first),
          ),
        ),
      );
    }
  }

  Future<void> _cancel() async {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(l.cancelReferralConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.no),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.yes),
          ),
        ],
      ),
    );
    if (ok == true) await s.fieldWork.cancelReferral(widget.referralId);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bus = context.watch<DataBus>();
    if (_seen != bus.version) {
      _seen = bus.version;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final r = _r;
    return HeaderScaffold(
      title: r?.householdId ?? l.referralsTitle,
      subtitle: r == null
          ? null
          : '${catName(l, r.serviceCategory)} · ${r.facilityId}',
      showBack: true,
      child: _loading
          ? const LoadingView()
          : r == null
          ? EmptyState(icon: Icons.search_off, title: l.noResults)
          : ListView(
              padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 40),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Builder(
                        builder: (_) {
                          final st = phaseStyle(l, r.phase);
                          return StatusBadge(
                            tone: st.tone,
                            icon: st.icon,
                            label: st.label,
                          );
                        },
                      ),
                      if (_unsynced)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: StatusBadge(
                            tone: Tone.warn,
                            icon: Icons.sync_problem_outlined,
                            label: l.unsyncedBadge,
                            dense: true,
                          ),
                        ),
                      const SizedBox(height: 12),
                      _Timeline(r: r),
                      const SizedBox(height: 8),
                      Text(
                        l.createdOn(fmtDate(context, r.createdDate)),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (r.plannedVisitDate != null)
                        Text(
                          l.plannedOn(fmtDate(context, r.plannedVisitDate)),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      if (r.phase == ReferralPhase.attendanceConfirmed) ...[
                        Text(
                          l.confirmedOn(
                            fmtDate(context, r.attendanceConfirmationDate),
                          ),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          '${l.attendanceRecordLabel}: ${r.attendanceRecordId}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Tk.s12),
                Banner2(
                  tone: Tone.info,
                  icon: Icons.info_outline,
                  text: l.attendanceNote,
                ),
                if (r.recordState == 'ACTIVE' &&
                    r.phase != ReferralPhase.attendanceConfirmed) ...[
                  const SizedBox(height: Tk.s16),
                  FilledButton.icon(
                    key: const Key('plan-referral'),
                    onPressed: _plan,
                    icon: const Icon(Icons.event),
                    label: Text(
                      r.plannedVisitDate == null
                          ? l.setPlannedDate
                          : l.changePlannedDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('cancel-referral'),
                    onPressed: _cancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(l.cancelReferral),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Three separate steps. The last one is only "done" when a hospital attendance record exists.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.r});
  final Referral r;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final steps = [
      (l.stepRecommended, true),
      (
        l.stepPlanned,
        r.phase == ReferralPhase.planned ||
            r.phase == ReferralPhase.attendanceConfirmed,
      ),
      (l.stepAttended, r.phase == ReferralPhase.attendanceConfirmed),
    ];
    return Column(
      children: [
        for (final (label, done) in steps)
          Semantics(
            label: '$label: ${done ? l.stepDone : l.stepWaiting}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    done ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: done ? Tk.ok : Tk.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    done ? l.stepDone : l.stepWaiting,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
