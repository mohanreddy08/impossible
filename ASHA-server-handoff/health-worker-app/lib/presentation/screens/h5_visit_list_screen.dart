import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../h5/h5_data.dart';
import '../../h5/h5_visit_list.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_services.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';
import 'h5_house_screen.dart';

/// The daily visit list made by the VIS rules from the household register of the block: priority 1 (high-risk and due now), 2 (due now),
/// 3 (later this week). One ASHA at a time, or all five. Tap a row to open the house. Everything is worked out on the phone.
class H5VisitListScreen extends StatefulWidget {
  const H5VisitListScreen({super.key});
  @override
  State<H5VisitListScreen> createState() => _H5VisitListScreenState();
}

class _H5VisitListScreenState extends State<H5VisitListScreen> {
  H5Data? _d;
  String? _asha; // null = all
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    context.read<AppServices>().h5.then((d) {
      if (mounted) setState(() => _d = d);
    }, onError: (Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = _d;
    return HeaderScaffold(
      title: l.h5VisitTitle,
      subtitle: d == null ? null : l.h5VisitAsOf(isoDate(d.today), _rows(d).length),
      showBack: true,
      child: _failed
          ? ErrorState(message: l.errUnknown)
          : d == null
              ? const LoadingView()
              : _body(context, l, d),
    );
  }

  List<H5VisitRow> _rows(H5Data d) {
    final rows = _asha == null ? d.visitRows : [for (final r in d.visitRows) if (d.byId[d.memberById[r.memberId]?.householdId]?.asha == _asha) r];
    return [...rows]..sort((a, b) {
        final c = a.priority.compareTo(b.priority);
        if (c != 0) return c;
        final s = a.dueDate.compareTo(b.dueDate);
        return s != 0 ? s : a.memberId.compareTo(b.memberId);
      });
  }

  Widget _body(BuildContext context, AppLocalizations l, H5Data d) {
    final rows = _rows(d);
    final children = <Widget>[];
    for (final p in [1, 2, 3]) {
      final group = [for (final r in rows) if (r.priority == p) r];
      if (group.isEmpty) continue;
      children.add(SectionHeader(
        switch (p) { 1 => l.h5Priority1, 2 => l.h5Priority2, _ => l.h5Priority3 },
        trailing: Text('${group.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ));
      for (final r in group) {
        final m = d.memberById[r.memberId];
        final h = m == null ? null : d.byId[m.householdId];
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            key: Key('visit-${r.memberId}-${r.item}'),
            onTap: h == null ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => H5HouseScreen(householdId: h.id))),
            semanticLabel: '${m?.name} ${r.item}',
            child: Row(children: [
              Container(width: 8, height: 44, decoration: BoxDecoration(color: statusColor(r.status), borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m?.name ?? r.memberId, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(
                    h == null ? '' : '${l.h5HouseNo(h.houseNo)} · ${h.village}${m == null ? '' : ' · ${m.ageText(d.today)}'}',
                    style: const TextStyle(color: Tk.textMuted, fontSize: 13),
                  ),
                  Text('${statusName(l, r.status)} · ${l.h5DueOn(r.dueDate)}', style: TextStyle(color: statusColor(r.status), fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
              Text(r.item, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ]),
          ),
        ));
      }
    }
    return Column(
      children: [
        SizedBox(
          height: 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Tk.s12, vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(key: const Key('visit-asha-all'), label: Text(l.h5AllAshas), selected: _asha == null, onSelected: (_) => setState(() => _asha = null)),
              ),
              for (final a in d.ashas)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(key: Key('visit-asha-${a.id}'), label: Text(a.name), selected: _asha == a.id, onSelected: (_) => setState(() => _asha = a.id)),
                ),
            ],
          ),
        ),
        Expanded(
          child: children.isEmpty
              ? EmptyState(icon: Icons.check_circle_outline, title: l.h5VisitEmpty)
              : ListView(padding: const EdgeInsets.fromLTRB(Tk.s16, 0, Tk.s16, 40), children: children),
        ),
      ],
    );
  }
}
