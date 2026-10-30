import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../maps/offline_map_source.dart';
import '../../state/app_services.dart';
import '../screens/h5_map_screen.dart';
import 'common.dart';
import 'header_scaffold.dart';
import 'village_map_view.dart';

/// The "Offline map" chip on the Households screen. Tap: the map of every house in the data (colour = how soon it needs a visit).
class OfflineMapChip extends StatelessWidget {
  const OfflineMapChip({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    return FutureBuilder<List<Object?>>(
      future: Future.wait<Object?>([s.maps.isAvailable(), s.h5.then<int?>((d) => d.households.length, onError: (Object _) => null)]),
      builder: (context, snap) {
        final demoOk = (snap.data?[0] as bool?) ?? false;
        final n = snap.data?[1] as int?;
        final ok = n != null || demoOk;
        final text = n != null ? l.h5MapChip(n) : (demoOk ? l.mapChipAvailable : l.mapChipMissing);
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Semantics(
            button: true,
            label: text,
            excludeSemantics: true,
            child: InkWell(
              key: const Key('offline-map-chip'),
              borderRadius: BorderRadius.circular(Tk.rChip),
              onTap: ok ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const H5MapScreen())) : null,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: ok ? Tk.okBg : Tk.neutralBg,
                  borderRadius: BorderRadius.circular(Tk.rChip),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(ok ? Icons.map : Icons.map_outlined, size: 20, color: ok ? Tk.ok : Tk.neutral),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(text, style: TextStyle(color: ok ? Tk.ok : Tk.neutral, fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                    if (ok) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 20, color: Tk.ok),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "House location": a small offline map around this house. Tap for the big map.
class HouseLocationCard extends StatefulWidget {
  const HouseLocationCard({super.key, required this.householdId});
  final String householdId;
  @override
  State<HouseLocationCard> createState() => _HouseLocationCardState();
}

class _HouseLocationCardState extends State<HouseLocationCard> {
  late final Future<VillageMap?> _map;
  late final Future<(double, double)?> _geo;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppServices>();
    _geo = s.store.geoFor(widget.householdId);
    _map = _pickMap(s);
  }

  /// The demo pack when this house is one of its houses; otherwise the Chandrapuri village map that covers the saved point (a family
  /// added on this phone, located with the map picker).
  Future<VillageMap?> _pickMap(AppServices s) async {
    final demo = await s.maps.load();
    if (demo != null && demo.houses.containsKey(widget.householdId)) return demo;
    final g = await _geo;
    if (g == null) return demo;
    try {
      return (await s.h5).mapContaining(LatLng(g.$1, g.$2)) ?? demo;
    } on Object {
      return demo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppCard(
      child: FutureBuilder<List<Object?>>(
        future: Future.wait<Object?>([_map, _geo]),
        builder: (context, snap) {
          final map = snap.data?[0] as VillageMap?;
          final geo = snap.data?[1] as (double, double)?;
          final ready = snap.connectionState == ConnectionState.done;
          final show = map != null && geo != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.place_outlined, color: Tk.primary),
                  const SizedBox(width: 8),
                  Text(
                    l.houseLocationTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!ready)
                const SizedBox(height: 190)
              else if (!show)
                Text(
                  l.houseLocationNone,
                  style: const TextStyle(color: Tk.textMuted),
                )
              else ...[
                Semantics(
                  button: true,
                  label:
                      '${l.houseLocationTitle} ${widget.householdId}. ${l.houseLocationOpen}',
                  excludeSemantics: true,
                  child: InkWell(
                    key: const Key('house-map-open'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HouseMapScreen(
                          map: map,
                          householdId: widget.householdId,
                          at: LatLng(geo.$1, geo.$2),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 190,
                        child: IgnorePointer(
                          child: VillageMapView(
                            map: map,
                            selectedAt: LatLng(geo.$1, geo.$2),
                            focus: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.open_in_full,
                      size: 16,
                      color: Tk.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l.houseLocationOpen,
                        style: const TextStyle(
                          color: Tk.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                if (map.id.startsWith('DEMO') || map.id.startsWith('H5'))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l.mapDemoNote,
                      style: const TextStyle(
                        color: Tk.warn,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The big map: the whole village, pan and pinch-zoom, with the red pin on this house. Works with no internet.
class HouseMapScreen extends StatelessWidget {
  const HouseMapScreen({
    super.key,
    required this.map,
    required this.householdId,
    this.at,
  });
  final VillageMap map;
  final String householdId;

  /// Where to put the pin (defaults to the house's point in the pack).
  final LatLng? at;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return HeaderScaffold(
      title: l.houseLocationTitle,
      subtitle: householdId,
      showBack: true,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(Tk.s12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: VillageMapView(
                  map: map,
                  selectedHouseId: householdId,
                  selectedAt: at,
                  interactive: true,
                ),
              ),
            ),
          ),
          if (map.id.startsWith('DEMO') || map.id.startsWith('H5'))
            Padding(
              padding: const EdgeInsets.fromLTRB(Tk.s16, 0, Tk.s16, Tk.s12),
              child: Text(
                l.mapDemoNote,
                style: const TextStyle(
                  color: Tk.warn,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
