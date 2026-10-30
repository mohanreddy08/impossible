import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/household.dart';
import '../../l10n/app_localizations.dart';
import '../../maps/offline_map_source.dart';
import '../../services/field_work_service.dart';
import '../../state/app_services.dart';
import '../format.dart';
import '../validation_text.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';
import 'households_screen.dart';
import 'location_picker_screen.dart';

/// Register a family that is new to the village. Saved on the phone at once (works offline) and sent to the server when online.
class AddHouseholdScreen extends StatefulWidget {
  const AddHouseholdScreen({super.key});
  @override
  State<AddHouseholdScreen> createState() => _AddHouseholdScreenState();
}

class _AddHouseholdScreenState extends State<AddHouseholdScreen> {
  final _village = TextEditingController();
  List<String> _villages = [];
  int _members = 4;
  final Set<String> _cats = {'ROUTINE'};
  Map<String, String> _errors = {};
  bool _saving = false;
  LatLng? _at; // the house location picked on the map (optional)

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _village.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = context.read<AppServices>();
    final v = await s.store.villagesByUse();
    if (!mounted) return;
    setState(() {
      _villages = v;
      if (_village.text.isEmpty && v.isNotEmpty) {
        _village.text = v.first; // the village you work in most
      }
    });
    try {
      // the villages of the Chandrapuri data are always offered, so a new family there can be put on its village map
      final names = [for (final x in (await s.h5).villages) if (!v.contains(x.name)) x.name];
      if (mounted && names.isNotEmpty) setState(() => _villages = [...v, ...names]);
    } on Object {
      // no Chandrapuri data on this build: only the villages already used
    }
  }

  /// Opens the offline map of the typed village (or the whole block) so the worker can tap where the house is.
  Future<void> _pickLocation() async {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    VillageMap? map;
    String? label;
    try {
      final d = await s.h5;
      final typed = _village.text.trim().toLowerCase();
      final v = d.villages.where((x) => x.name.toLowerCase() == typed).firstOrNull;
      map = v != null ? d.maps[v.slug] : d.block;
      label = v?.name;
    } on Object {
      map = await s.maps.load();
    }
    if (map == null) {
      messenger.showSnackBar(SnackBar(content: Text(l.h5PickNoMap)));
      return;
    }
    final at = await nav.push<LatLng>(MaterialPageRoute<LatLng>(
      builder: (_) => LocationPickerScreen(map: map!, initial: _at, subtitle: label),
    ));
    if (at != null && mounted) setState(() => _at = at);
  }

  Future<void> _save() async {
    if (_saving) {
      return; // a double tap must not add the family twice
    }
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _errors = {};
    });
    try {
      final id = await s.fieldWork.addHousehold(
        villageId: _village.text,
        memberCount: _members,
        categories: _cats.toList(),
      );
      if (_at != null) await s.store.setGeo({id: (_at!.lat, _at!.lng)}); // saved on this phone only, like the phone numbers
      messenger.showSnackBar(SnackBar(content: Text(l.addFamilyDone(id))));
      nav.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HouseholdDetailScreen(householdId: id),
        ),
      );
    } on DomainValidation catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return HeaderScaffold(
      title: l.addFamilyTitle,
      showBack: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 40),
        children: [
          TextField(
            key: const Key('add-village'),
            controller: _village,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l.villageLabel2,
              hintText: l.villageHint,
              errorText: _errors['village'] == null
                  ? null
                  : validationText(l, 'village', _errors['village']!),
            ),
          ),
          if (_villages.length > 1) ...[
            const SizedBox(height: Tk.s8),
            Text(l.villagePick, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in _villages)
                  ActionChip(
                    key: Key('village-$v'),
                    label: Text(v),
                    onPressed: () => setState(() => _village.text = v),
                  ),
              ],
            ),
          ],
          SectionHeader(l.h5PickCardTitle),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_at == null ? Icons.add_location_alt_outlined : Icons.location_on, color: Tk.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _at == null ? l.h5PickNone : l.h5PickedAt(_at!.lat.toStringAsFixed(5), _at!.lng.toStringAsFixed(5)),
                        key: const Key('picked-location-text'),
                        style: TextStyle(fontWeight: FontWeight.w700, color: _at == null ? Tk.textMuted : Tk.text),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('pick-location'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, Tk.minTouch)),
                      onPressed: _pickLocation,
                      icon: const Icon(Icons.map_outlined),
                      label: Text(_at == null ? l.h5PickOpen : l.h5PickChange),
                    ),
                    if (_at != null)
                      TextButton(
                        key: const Key('clear-location'),
                        onPressed: () => setState(() => _at = null),
                        child: Text(l.h5PickClear),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SectionHeader(l.membersLabel),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: Tk.s12,
              vertical: Tk.s8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filledTonal(
                  key: const Key('members-minus'),
                  tooltip: l.membersDecrease,
                  iconSize: 28,
                  constraints: const BoxConstraints(
                    minWidth: 52,
                    minHeight: 52,
                  ),
                  onPressed: _members > 1
                      ? () => setState(() => _members--)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Text(
                  '$_members',
                  key: const Key('members-value'),
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                IconButton.filledTonal(
                  key: const Key('members-plus'),
                  tooltip: l.membersIncrease,
                  iconSize: 28,
                  constraints: const BoxConstraints(
                    minWidth: 52,
                    minHeight: 52,
                  ),
                  onPressed: _members < 60
                      ? () => setState(() => _members++)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          if (_errors['members'] != null)
            _err(validationText(l, 'members', _errors['members']!)),
          SectionHeader(l.followupsLabel),
          Text(l.followupsHint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: Tk.s8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in followupCategories)
                FilterChip(
                  key: Key('cat-$c'),
                  label: Text(catName(l, c)),
                  selected: _cats.contains(c),
                  onSelected: (on) =>
                      setState(() => on ? _cats.add(c) : _cats.remove(c)),
                ),
            ],
          ),
          if (_errors['categories'] != null)
            _err(validationText(l, 'categories', _errors['categories']!)),
          if (_errors['worker'] != null) ...[
            const SizedBox(height: Tk.s12),
            Banner2(
              tone: Tone.warn,
              icon: Icons.info_outline,
              text: validationText(l, 'worker', _errors['worker']!),
            ),
          ],
          const SizedBox(height: Tk.s24),
          FilledButton.icon(
            key: const Key('add-family-save'),
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(l.addFamilySave),
          ),
          const SizedBox(height: 6),
          Text(l.addFamilyNote, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _err(String t) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      t,
      style: const TextStyle(color: Tk.danger, fontWeight: FontWeight.w600),
    ),
  );
}
