import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/phone.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_services.dart';
import 'common.dart';

/// "Phone numbers" of a household: Phone 1 (required) and Phone 2 (optional), each with a call button. Saved on this phone only.
class PhoneNumbersCard extends StatefulWidget {
  const PhoneNumbersCard({super.key, required this.householdId, this.launcher});
  final String householdId;

  /// For tests: replaces opening the phone app.
  final Future<bool> Function(Uri)? launcher;
  @override
  State<PhoneNumbersCard> createState() => _PhoneNumbersCardState();
}

class _PhoneNumbersCardState extends State<PhoneNumbersCard> {
  (String, String?)? _numbers;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await context.read<AppServices>().store.contactsFor(
      widget.householdId,
    );
    if (!mounted) return;
    setState(() {
      _numbers = r;
      _loaded = true;
    });
  }

  String _pretty(String n) => '${n.substring(0, 5)} ${n.substring(5)}';

  Future<void> _call(String n) async {
    final l = AppLocalizations.of(context);
    final msg = ScaffoldMessenger.of(context);
    bool ok;
    try {
      ok = await (widget.launcher ?? launchUrl)(Uri(scheme: 'tel', path: n));
    } on Object {
      ok = false;
    }
    if (!ok) msg.showSnackBar(SnackBar(content: Text(l.phoneCannotCall)));
  }

  Future<void> _edit() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PhoneSheet(
        householdId: widget.householdId,
        phone1: _numbers?.$1 ?? '',
        phone2: _numbers?.$2 ?? '',
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final n = _numbers;
    Widget row(String label, String number) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Tk.textMuted, fontSize: 13),
                ),
                Text(
                  _pretty(number),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            key: Key('call-$number'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, Tk.minTouch),
            ),
            onPressed: () => _call(number),
            icon: const Icon(Icons.call),
            label: Text(l.phoneCall(_pretty(number))),
          ),
        ],
      ),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_outlined, color: Tk.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.phonesTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              if (_loaded && n != null)
                TextButton.icon(
                  key: const Key('phones-edit'),
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l.phoneEdit),
                ),
            ],
          ),
          if (_loaded && n == null) ...[
            const SizedBox(height: 6),
            Text(l.phoneNotAdded, style: const TextStyle(color: Tk.textMuted)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('phones-add'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, Tk.minTouch),
              ),
              onPressed: _edit,
              icon: const Icon(Icons.add_call),
              label: Text(l.phoneAdd),
            ),
          ],
          if (n != null) ...[
            row(l.phone1Label, n.$1),
            if (n.$2 != null) row(l.phone2Label, n.$2!),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 15, color: Tk.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l.phoneLocalOnly,
                  style: const TextStyle(color: Tk.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhoneSheet extends StatefulWidget {
  const _PhoneSheet({
    required this.householdId,
    required this.phone1,
    required this.phone2,
  });
  final String householdId, phone1, phone2;
  @override
  State<_PhoneSheet> createState() => _PhoneSheetState();
}

class _PhoneSheetState extends State<_PhoneSheet> {
  late final _c1 = TextEditingController(text: widget.phone1);
  late final _c2 = TextEditingController(text: widget.phone2);
  PhoneProblem? _e1, _e2;
  bool _tried = false;

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    super.dispose();
  }

  void _check() {
    final r = checkPhones(_c1.text, _c2.text);
    _e1 = r.first;
    _e2 = r.second;
  }

  String? _msg(AppLocalizations l, PhoneProblem? p) => switch (p) {
    PhoneProblem.required => l.phoneErrRequired,
    PhoneProblem.invalid => l.phoneErrInvalid,
    PhoneProblem.same => l.phoneErrSame,
    null => null,
  };

  Future<void> _save() async {
    setState(_check);
    _tried = true;
    if (_e1 != null || _e2 != null) return;
    final s = context.read<AppServices>();
    await s.store.saveContacts(
      widget.householdId,
      normalizeIndianMobile(_c1.text)!,
      _c2.text.trim().isEmpty ? null : normalizeIndianMobile(_c2.text),
      s.clock.nowUtc(),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget field(
      Key k,
      TextEditingController c,
      String label,
      PhoneProblem? e,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        key: k,
        controller: c,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
          LengthLimitingTextInputFormatter(16),
        ],
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          errorText: _msg(l, e),
          errorMaxLines: 3,
          prefixIcon: const Icon(Icons.phone),
        ),
        onChanged: (_) {
          if (_tried) setState(_check);
        },
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Tk.s16,
        0,
        Tk.s16,
        MediaQuery.of(context).viewInsets.bottom + Tk.s16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.phonesTitle,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: Tk.s12),
            field(const Key('phone1-field'), _c1, l.phone1Label, _e1),
            field(const Key('phone2-field'), _c2, l.phone2Label, _e2),
            Text(
              l.phoneLocalOnly,
              style: const TextStyle(color: Tk.textMuted, fontSize: 13),
            ),
            const SizedBox(height: Tk.s12),
            FilledButton(
              key: const Key('phones-save'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(Tk.minTouch),
              ),
              onPressed: _save,
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
  }
}
