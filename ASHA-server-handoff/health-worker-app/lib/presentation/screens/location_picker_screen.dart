import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../maps/offline_map_source.dart';
import '../widgets/header_scaffold.dart';
import '../widgets/village_map_view.dart';

/// "Pick the house on the map": the offline map with the neighbouring houses; one tap puts the red pin, then "Use this location" returns
/// the point. Works with no internet. Pops with a [LatLng], or null when the worker goes back.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, required this.map, this.initial, this.subtitle});
  final VillageMap map;
  final LatLng? initial;
  final String? subtitle;
  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  LatLng? _at;

  @override
  void initState() {
    super.initState();
    _at = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return HeaderScaffold(
      title: l.h5PickTitle,
      subtitle: widget.subtitle ?? widget.map.name,
      showBack: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s12, Tk.s16, 0),
            child: Row(
              children: [
                const Icon(Icons.touch_app_outlined, color: Tk.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(l.h5PickHelp, style: const TextStyle(fontWeight: FontWeight.w700))),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(Tk.s12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: VillageMapView(
                  key: const Key('picker-map'),
                  map: widget.map,
                  selectedAt: _at,
                  interactive: true,
                  maxScale: 12,
                  onTapAt: (p) => setState(() => _at = p),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.s16, 0, Tk.s16, 2),
            child: Text(
              l.h5MapMadeUp,
              style: const TextStyle(color: Tk.warn, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.s16, 6, Tk.s16, Tk.s16),
            child: FilledButton.icon(
              key: const Key('picker-use'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Tk.minTouch)),
              onPressed: _at == null ? null : () => Navigator.of(context).pop(_at),
              icon: const Icon(Icons.check),
              label: Text(l.h5PickUse),
            ),
          ),
        ],
      ),
    );
  }
}
