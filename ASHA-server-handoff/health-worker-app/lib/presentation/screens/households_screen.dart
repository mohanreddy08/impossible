import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../data/local/local_store.dart';
import '../../data/models/household.dart';
import '../../data/models/referral.dart';
import '../../data/models/visit.dart';
import '../../l10n/app_localizations.dart';
import '../../services/data_bus.dart';
import '../../services/field_work_service.dart';
import '../../state/app_services.dart';
import '../format.dart';
import '../validation_text.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';
import '../widgets/house_location_card.dart';
import '../widgets/phone_numbers_card.dart';
import '../widgets/paged_list.dart';
import 'add_household_screen.dart';
import 'referrals_screen.dart';
import 'visit_screen.dart';

(Tone, IconData) householdTone(String status) => switch (status) {
  'OVERDUE' => (Tone.danger, Icons.warning_amber_rounded),
  'DUE_TODAY' => (Tone.info, Icons.today),
  'UPCOMING' => (Tone.neutral, Icons.event_available),
  'COMPLETED' => (Tone.ok, Icons.check_circle_outline),
  _ => (Tone.neutral, Icons.remove_circle_outline),
};

class HouseholdsScreen extends StatefulWidget {
  const HouseholdsScreen({super.key});
  @override
  State<HouseholdsScreen> createState() => _HouseholdsScreenState();
}

class _HouseholdsScreenState extends State<HouseholdsScreen> {
  HouseholdFilter _filter = const HouseholdFilter();
  PagedLoader<Household>? _loader;
  int _seen = -1;
  int _total = 0;
  List<String> _villages = [];
  Timer? _debounce;
  final _scroll = ScrollController();
  final _search = TextEditingController();

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
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    _loader?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = context.read<AppServices>();
    final t = await s.store.countHouseholds(_filter);
    final v = await s.store.villages();
    if (!mounted) return;
    setState(() {
      _total = t;
      _villages = v;
    });
    await _loader?.reset();
  }

  void _setFilter(HouseholdFilter f) {
    _filter = f;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final bus = context.watch<DataBus>();
    _loader ??= PagedLoader(
      (o, n) => s.store.pageHouseholds(_filter, limit: n, offset: o),
    )..addListener(() => mounted ? setState(() {}) : null);
    if (_seen != bus.version) {
      _seen = bus.version;
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
    final leading = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 0),
        child: FilledButton.icon(
          key: const Key('add-family'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AddHouseholdScreen()),
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text(l.addFamily),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, Tk.s8),
        child: TextField(
          key: const Key('household-search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l.searchHouseholds,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l.clear,
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      _setFilter(
                        HouseholdFilter(
                          status: _filter.status,
                          category: _filter.category,
                          village: _filter.village,
                        ),
                      );
                    },
                  ),
          ),
          onChanged: (t) {
            _debounce?.cancel();
            _debounce = Timer(
              const Duration(milliseconds: 300),
              () => _setFilter(
                HouseholdFilter(
                  search: t,
                  status: _filter.status,
                  category: _filter.category,
                  village: _filter.village,
                ),
              ),
            );
          },
        ),
      ),
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Tk.s16),
          children: [
            _FilterMenu(
              label: l.filterStatus,
              value: _filter.status,
              options: {
                for (final st in [
                  'OVERDUE',
                  'DUE_TODAY',
                  'UPCOMING',
                  'COMPLETED',
                  'NO_VISIT_DUE',
                ])
                  st: householdStatusName(l, st),
              },
              onSelected: (v) => _setFilter(
                HouseholdFilter(
                  search: _filter.search,
                  status: v,
                  category: _filter.category,
                  village: _filter.village,
                ),
              ),
            ),
            _FilterMenu(
              label: l.filterCategory,
              value: _filter.category,
              options: {for (final c in followupCategories) c: catName(l, c)},
              onSelected: (v) => _setFilter(
                HouseholdFilter(
                  search: _filter.search,
                  status: _filter.status,
                  category: v,
                  village: _filter.village,
                ),
              ),
            ),
            if (_villages.length > 1)
              _FilterMenu(
                label: l.filterVillage,
                value: _filter.village,
                options: {for (final v in _villages) v: v},
                onSelected: (v) => _setFilter(
                  HouseholdFilter(
                    search: _filter.search,
                    status: _filter.status,
                    category: _filter.category,
                    village: v,
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
    return HeaderScaffold(
      title: l.householdsTitle,
      subtitle: l.householdsCount(_total),
      headerExtra: const OfflineMapChip(),
      child: pagedScrollView<Household>(
        controller: _scroll,
        leading: leading,
        loader: _loader!,
        loading: const LoadingView(),
        empty: EmptyState(icon: Icons.house_outlined, title: l.noResults),
        error: () => ErrorState(message: l.errUnknown, onRetry: _loader!.reset),
        itemBuilder: (c, h) => HouseholdTile(h: h),
      ),
    );
  }
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
  });
  final String label;
  final String? value;
  final Map<String, String> options;
  final ValueChanged<String?> onSelected;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final active = value != null;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        tooltip: label,
        onSelected: (v) => onSelected(v == '__all' ? null : v),
        itemBuilder: (_) => [
          PopupMenuItem(value: '__all', child: Text(l.all)),
          for (final e in options.entries)
            PopupMenuItem(value: e.key, child: Text(e.value)),
        ],
        child: Semantics(
          button: true,
          label: '$label: ${active ? options[value] : l.all}',
          excludeSemantics: true,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? Tk.primaryDark : Colors.white,
              borderRadius: BorderRadius.circular(Tk.rChip),
              border: Border.all(color: active ? Tk.primaryDark : Tk.border),
            ),
            child: Row(
              children: [
                Text(
                  active ? options[value]! : label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : Tk.text,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: active ? Colors.white : Tk.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HouseholdTile extends StatelessWidget {
  const HouseholdTile({super.key, required this.h});
  final Household h;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (tone, icon) = householdTone(h.recordStatus);
    final status = householdStatusName(l, h.recordStatus);
    return AppCard(
      key: ValueKey('hh-${h.householdId}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HouseholdDetailScreen(householdId: h.householdId),
        ),
      ),
      semanticLabel:
          '${h.householdId}. $status. ${l.members(h.memberCount)}. ${l.nextVisitLabel}: ${fmtDate(context, h.nextVisitDueDate)}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    h.householdId,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusBadge(tone: tone, icon: icon, label: status, dense: true),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${h.villageId}  ·  ${l.members(h.memberCount)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.event_outlined, size: 15, color: Tk.textMuted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${l.nextVisitLabel}: ${h.nextVisitDueDate == null ? l.notSet : fmtDate(context, h.nextVisitDueDate)}${h.scheduledCategory == null ? '' : ' · ${catName(l, h.scheduledCategory!)}'}',
                    style: Theme.of(context).textTheme.bodyMedium,
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

class HouseholdDetailScreen extends StatefulWidget {
  const HouseholdDetailScreen({super.key, required this.householdId});
  final String householdId;
  @override
  State<HouseholdDetailScreen> createState() => _HouseholdDetailScreenState();
}

class _HouseholdDetailScreenState extends State<HouseholdDetailScreen> {
  Household? _h;
  List<Visit> _visits = [];
  List<Referral> _refs = [];
  Set<String> _unsyncedV = {}, _unsyncedR = {};
  Map<String, String> _times = {};
  int _limit = 8;
  bool _loading = true, _more = false;
  int _seen = -1;

  Future<void> _load() async {
    final s = context.read<AppServices>();
    final h = await s.store.household(widget.householdId);
    final v = await s.store.visitsForHousehold(
      widget.householdId,
      limit: _limit + 1,
    );
    final r = await s.store.referralsForHousehold(widget.householdId);
    final uv = await s.store.unsyncedEntityIds('visit');
    final ur = await s.store.unsyncedEntityIds('referral');
    final times = await s.store.visitTimes(v.map((e) => e.visitId));
    if (!mounted) return;
    setState(() {
      _h = h;
      _more = v.length > _limit;
      _visits = v.take(_limit).toList();
      _refs = r;
      _unsyncedV = uv;
      _unsyncedR = ur;
      _times = times;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bus = context.watch<DataBus>();
    if (_seen != bus.version) {
      _seen = bus.version;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final h = _h;
    final (tone, icon) = householdTone(h?.recordStatus ?? '');
    return HeaderScaffold(
      title: widget.householdId,
      subtitle: h == null
          ? null
          : '${h.villageId} · ${l.members(h.memberCount)}',
      showBack: true,
      child: _loading
          ? const LoadingView()
          : h == null
          ? EmptyState(icon: Icons.search_off, title: l.noResults)
          : ListView(
              padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 40),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusBadge(
                        tone: tone,
                        icon: icon,
                        label: householdStatusName(l, h.recordStatus),
                      ),
                      const SizedBox(height: 10),
                      _row(
                        context,
                        l.nextVisitLabel,
                        h.nextVisitDueDate == null
                            ? l.notSet
                            : '${fmtDate(context, h.nextVisitDueDate)}${h.scheduledCategory == null ? '' : ' · ${catName(l, h.scheduledCategory!)}'}',
                      ),
                      _row(
                        context,
                        l.lastVisitLabel,
                        h.lastVisitDate == null
                            ? l.lastVisitNone
                            : fmtDate(context, h.lastVisitDate),
                      ),
                      _row(
                        context,
                        l.eligibleFollowups,
                        h.eligibleCategories
                            .map((c) => catName(l, c))
                            .join(', '),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Tk.s12),
                HouseLocationCard(householdId: h.householdId),
                const SizedBox(height: Tk.s12),
                PhoneNumbersCard(householdId: h.householdId),
                const SizedBox(height: Tk.s12),
                OutlinedButton.icon(
                  key: const Key('schedule-visit'),
                  onPressed: () => _schedule(context, h),
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(l.scheduleVisit),
                ),
                SectionHeader(l.householdReferrals),
                if (_refs.isEmpty)
                  Text(l.none, style: Theme.of(context).textTheme.bodySmall)
                else
                  for (final r in _refs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ReferralTile(
                        r: r,
                        unsynced: _unsyncedR.contains(r.referralId),
                      ),
                    ),
                SectionHeader(l.visitHistory),
                if (_visits.isEmpty)
                  Text(
                    l.noHistory,
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  for (final v in _visits)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _VisitRow(
                        v: v,
                        unsynced: _unsyncedV.contains(v.visitId),
                        time: _times[v.visitId],
                      ),
                    ),
                if (_more)
                  TextButton(
                    onPressed: () {
                      _limit += 10;
                      _load();
                    },
                    child: Text(l.loadMore),
                  ),
              ],
            ),
    );
  }

  Widget _row(BuildContext c, String k, String v) => KeyValue(k, v);

  Future<void> _schedule(BuildContext context, Household h) async {
    final s = context.read<AppServices>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Provider<AppServices>.value(
        value: s,
        child: _ScheduleSheet(household: h),
      ),
    );
  }
}

class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.v, required this.unsynced, this.time});
  final Visit v;
  final bool unsynced;
  final String? time; // 'HH:mm', when the worker went (kept on the phone)
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final planned = v.status == 'PLANNED';
    return AppCard(
      padding: const EdgeInsets.all(Tk.s12),
      onTap: planned
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VisitScreen(visitId: v.visitId),
              ),
            )
          : null,
      semanticLabel:
          '${catName(l, v.reason)}. ${visitStatusName(l, v.status)}. ${fmtDate(context, v.actualVisitDate ?? v.scheduledDate)}${unsynced ? '. ${l.unsyncedBadge}' : ''}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    catName(l, v.reason),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${fmtDate(context, v.actualVisitDate ?? v.scheduledDate)}${time == null ? '' : '  ·  ${fmtVisitTime(context, time!)}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (unsynced)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: StatusBadge(
                  tone: Tone.warn,
                  icon: Icons.sync_problem_outlined,
                  label: l.unsyncedBadge,
                  dense: true,
                ),
              ),
            StatusBadge(
              tone: v.status == 'COMPLETED'
                  ? Tone.ok
                  : v.status == 'PLANNED'
                  ? Tone.info
                  : Tone.neutral,
              icon: v.status == 'COMPLETED' ? Icons.check_circle : Icons.event,
              label: visitStatusName(l, v.status),
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.household});
  final Household household;
  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  DateTime? _date;
  late String _cat = widget.household.eligibleCategories.isEmpty
      ? 'ROUTINE'
      : widget.household.eligibleCategories.first;
  String? _err;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Tk.s16,
        0,
        Tk.s16,
        MediaQuery.of(context).viewInsets.bottom + Tk.s16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.scheduleVisit, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _cat,
            decoration: InputDecoration(labelText: l.filterCategory),
            items: [
              for (final c in followupCategories)
                DropdownMenuItem(value: c, child: Text(catName(l, c))),
            ],
            onChanged: (v) => setState(() => _cat = v ?? _cat),
          ),
          const SizedBox(height: 12),
          DateField(
            fieldKey: const Key('schedule-date'),
            label: l.nextVisitDate,
            value: _date,
            onChanged: (d) => setState(() => _date = d),
            errorText: _err,
            first: s.clock.today(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('schedule-save'),
            onPressed: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              if (_date == null) {
                setState(() => _err = l.errNextRequired);
                return;
              }
              try {
                await s.fieldWork.scheduleVisit(
                  widget.household.householdId,
                  _date!,
                  _cat,
                );
                messenger.showSnackBar(SnackBar(content: Text(l.savedOffline)));
                nav.pop();
              } on DomainValidation catch (e) {
                setState(
                  () => _err = validationText(l, 'date', e.errors.values.first),
                );
              }
            },
            child: Text(l.save),
          ),
        ],
      ),
    );
  }
}
