import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../h5/h5_data.dart';
import '../../h5/h5_visit_list.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_services.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';
import '../widgets/phone_numbers_card.dart';
import '../widgets/village_map_view.dart';
import 'h5_map_screen.dart';

String statusName(AppLocalizations l, String status) => switch (status) {
      'overdue' => l.h5StatusOverdue,
      'due_today' => l.h5StatusToday,
      _ => l.h5StatusWeek,
    };

Color statusColor(String status) => switch (status) {
      'overdue' => Tk.danger,
      'due_today' => Tk.warn,
      _ => Tk.info,
    };

/// A due item as a small chip: "ANC-2 · Overdue".
class H5ItemChip extends StatelessWidget {
  const H5ItemChip(this.row, {super.key});
  final H5VisitRow row;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = statusColor(row.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Tk.rChip), border: Border.all(color: c)),
      child: Text('${row.item} · ${statusName(l, row.status)}', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }
}

/// One house of the Chandrapuri data: who lives there, what is due for each person, phone numbers and where it is on the map.
class H5HouseScreen extends StatelessWidget {
  const H5HouseScreen({super.key, required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<H5Data>(
      future: context.read<AppServices>().h5,
      builder: (context, snap) {
        final d = snap.data;
        final h = d?.byId[householdId];
        if (d == null || h == null) {
          return HeaderScaffold(
            title: l.h5HouseTitle,
            subtitle: householdId,
            showBack: true,
            child: snap.connectionState == ConnectionState.done ? ErrorState(message: l.errUnknown) : const LoadingView(),
          );
        }
        final asha = d.ashas.where((a) => a.id == h.asha).map((a) => a.name).firstOrNull ?? h.asha;
        final people = d.membersOf[h.id] ?? const <H5Member>[];
        final map = d.maps[H5Data.slugOf(h.village)]!;
        final level = d.levelOf(h.id);
        return HeaderScaffold(
          title: h.head,
          subtitle: '${l.h5HouseNo(h.houseNo)} · ${l.h5VillageLine(h.village, asha)}',
          showBack: true,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 40),
            children: [
              AppCard(
                child: Row(children: [
                  Container(width: 10, height: 44, decoration: BoxDecoration(color: levelColor(level), borderRadius: BorderRadius.circular(5))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(levelName(l, level), style: TextStyle(color: levelColor(level), fontWeight: FontWeight.w800, fontSize: 18)),
                      Text(l.h5PeopleCount(people.length), style: const TextStyle(color: Tk.textMuted)),
                    ]),
                  ),
                ]),
              ),
              SectionHeader(l.h5DueNow),
              if ((d.itemsOfHousehold[h.id] ?? const []).isEmpty)
                Text(l.h5NothingDue, style: const TextStyle(color: Tk.textMuted))
              else
                for (final m in people)
                  if ((d.itemsOfMember[m.id] ?? const []).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [for (final r in d.itemsOfMember[m.id]!) H5ItemChip(r)]),
                        ]),
                      ),
                    ),
              SectionHeader(l.h5MembersTitle),
              AppCard(
                child: Column(children: [
                  for (final m in people)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (m.pregnant) ...[
                          Text(l.h5MemberPregnant, style: const TextStyle(color: Tk.danger, fontWeight: FontWeight.w800, fontSize: 13)),
                          const SizedBox(width: 8),
                        ],
                        Text('${m.relation.replaceAll('_', ' ')} · ${m.ageText(d.today)}', style: const TextStyle(color: Tk.textMuted, fontSize: 13)),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: Tk.s12),
              PhoneNumbersCard(householdId: h.id),
              const SizedBox(height: Tk.s12),
              AppCard(
                child: InkWell(
                  key: const Key('h5-house-map'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => H5MapScreen(village: h.village, houseId: h.id))),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 190,
                      child: IgnorePointer(child: VillageMapView(map: map, selectedHouseId: h.id, focus: true)),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l.h5MapMadeUp, style: const TextStyle(color: Tk.warn, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }
}
