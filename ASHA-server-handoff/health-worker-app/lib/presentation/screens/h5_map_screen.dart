import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../h5/h5_data.dart';
import '../../h5/h5_visit_list.dart';
import '../../l10n/app_localizations.dart';
import '../../maps/offline_map_source.dart';
import '../../state/app_services.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';
import '../widgets/village_map_view.dart';
import 'h5_house_screen.dart';
import 'households_screen.dart';

Color levelColor(H5Level l) => switch (l) {
      H5Level.urgent => Tk.danger,
      H5Level.due => const Color(0xFFD98200),
      H5Level.soon => Tk.info,
      H5Level.none => const Color(0xFF3C8D5A),
    };

String levelName(AppLocalizations l, H5Level v) => switch (v) {
      H5Level.urgent => l.h5LegendUrgent,
      H5Level.due => l.h5LegendDue,
      H5Level.soon => l.h5LegendSoon,
      H5Level.none => l.h5LegendNone,
    };

/// The offline map of every house in the data: pick a village (or all six), houses are coloured by how soon they need a visit, tap a
/// house to see who lives there and open it. Families added on this phone appear too. No internet needed.
class H5MapScreen extends StatefulWidget {
  const H5MapScreen({super.key, this.village, this.houseId});

  /// Village name to start in (null = all villages).
  final String? village;

  /// A house to select at the start.
  final String? houseId;
  @override
  State<H5MapScreen> createState() => _H5MapScreenState();
}

class _H5MapScreenState extends State<H5MapScreen> {
  H5Data? _d;
  Map<String, (double, double)> _local = {};
  String? _village; // null = all
  String? _selected;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _village = widget.village;
    _selected = widget.houseId;
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppServices>();
    try {
      final d = await s.h5;
      final geo = await s.store.geoAll();
      if (!mounted) return;
      setState(() {
        _d = d;
        _local = geo;
        if (_selected != null && _village == null && widget.village == null) {
          _village = d.byId[_selected]?.village; // open on the village of the house we were asked to show
        }
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  VillageMap _map(H5Data d) {
    final v = _village;
    return v == null ? d.block : d.maps[d.villageNamed(v)!.slug]!;
  }

  /// Families added on this phone (not in the Chandrapuri data) that lie on the map being shown.
  Map<String, LatLng> _extras(H5Data d, VillageMap m) => {
        for (final e in _local.entries)
          if (!d.byId.containsKey(e.key) &&
              e.value.$1 >= m.minLat - 0.0015 &&
              e.value.$1 <= m.maxLat + 0.0015 &&
              e.value.$2 >= m.minLng - 0.0015 &&
              e.value.$2 <= m.maxLng + 0.0015)
            e.key: LatLng(e.value.$1, e.value.$2),
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = _d;
    return HeaderScaffold(
      title: l.h5MapTitle,
      subtitle: _village ?? l.h5AllVillages,
      showBack: true,
      child: _failed
          ? ErrorState(message: l.errUnknown, onRetry: () {
              setState(() => _failed = false);
              _load();
            })
          : d == null
              ? const LoadingView()
              : _body(context, l, d),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l, H5Data d) {
    final map = _map(d);
    final extras = _extras(d, map);
    final inView = _village == null ? d.households : d.householdsOf(_village!);
    final colors = <String, Color>{
      for (final h in inView) h.id: levelColor(d.levelOf(h.id)),
      for (final id in extras.keys) id: Tk.primary,
    };
    final sel = _selected;
    return Column(
      children: [
        SizedBox(
          height: 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Tk.s12, vertical: 8),
            children: [
              _chip(l.h5AllVillages, _village == null, () => setState(() {
                    _village = null;
                    _selected = null;
                  }), const Key('map-village-all')),
              for (final v in d.villages)
                _chip(v.name, _village == v.name, () => setState(() {
                      _village = v.name;
                      _selected = null;
                    }), Key('map-village-${v.slug}')),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tk.s12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: VillageMapView(
                key: const Key('h5-map'),
                map: map,
                interactive: true,
                maxScale: 10,
                houseColors: colors,
                extraHouses: extras,
                selectedHouseId: sel,
                onHouseTap: (id) => setState(() => _selected = id),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.s16, 8, Tk.s16, 0),
          child: Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final v in H5Level.values)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: levelColor(v), borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 5),
                  Text(levelName(l, v), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              Text(l.h5HousesIn(inView.length + extras.length), style: const TextStyle(fontSize: 13, color: Tk.textMuted)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.s16, 2, Tk.s16, 2),
          child: Text(
            '${l.h5MapMadeUp}  ${l.h5MapAsOf(isoDate(d.today))}',
            style: const TextStyle(color: Tk.warn, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        if (sel != null) _selectedCard(context, l, d, sel) else const SizedBox(height: Tk.s12),
      ],
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap, Key key) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(key: key, label: Text(label), selected: on, onSelected: (_) => onTap()),
      );

  Widget _selectedCard(BuildContext context, AppLocalizations l, H5Data d, String id) {
    final h = d.byId[id];
    if (h == null) {
      // a family added on this phone
      return Padding(
        padding: const EdgeInsets.fromLTRB(Tk.s12, 6, Tk.s12, Tk.s12),
        child: AppCard(
          child: Row(children: [
            Expanded(child: Text(id, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            FilledButton(
              key: const Key('map-open-local'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HouseholdDetailScreen(householdId: id))),
              child: Text(l.h5OpenHouse),
            ),
          ]),
        ),
      );
    }
    final level = d.levelOf(id);
    final todo = d.itemsOfHousehold[id]?.length ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tk.s12, 6, Tk.s12, Tk.s12),
      child: AppCard(
        child: Row(
          children: [
            Container(width: 10, height: 52, decoration: BoxDecoration(color: levelColor(level), borderRadius: BorderRadius.circular(5))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.head, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  Text('${l.h5HouseNo(h.houseNo)} · ${h.village} · ${l.h5PeopleCount(h.members)}',
                      style: const TextStyle(color: Tk.textMuted, fontSize: 13)),
                  Text(todo == 0 ? l.h5LegendNone : '${levelName(l, level)} · $todo',
                      style: TextStyle(color: levelColor(level), fontWeight: FontWeight.w800, fontSize: 13)),
                ],
              ),
            ),
            FilledButton(
              key: const Key('map-open-house'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => H5HouseScreen(householdId: id))),
              child: Text(l.h5OpenHouse),
            ),
          ],
        ),
      ),
    );
  }
}
