import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../data/local/local_store.dart' show VisitTime;
import '../../data/models/household.dart';
import '../../data/models/referral.dart';
import '../../data/models/visit.dart';
import '../../l10n/app_localizations.dart';
import '../../services/field_work_service.dart';
import '../../state/app_services.dart';
import '../format.dart';
import '../validation_text.dart';
import '../widgets/choice_tile.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';

/// Visit details + "record outcome" form. Saving is local and immediate; the change is queued for sync.
class VisitScreen extends StatefulWidget {
  const VisitScreen({super.key, required this.visitId});
  final String visitId;
  @override
  State<VisitScreen> createState() => _VisitScreenState();
}

class _VisitScreenState extends State<VisitScreen> {
  Visit? _visit;
  Household? _hh;
  List<String> _facilities = [];
  bool _loading = true, _saving = false;
  String _outcome = 'COMPLETED';
  DateTime? _actual, _next;
  // WHEN the worker went: taken from the phone's clock the moment the form opens. Read-only on purpose: not editable by the worker.
  String _time = '00:00';
  VisitTime? _savedTime; // for a visit that is already recorded
  bool _followup = false, _referral = false;
  String? _facility, _service = 'GENERAL';
  Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppServices>();
    final v = await s.store.visit(widget.visitId);
    final h = v == null ? null : await s.store.household(v.householdId);
    final f = await s.store.facilities();
    final saved = await s.store.visitTime(widget.visitId);
    final now = s.clock.localNow();
    if (!mounted) return;
    setState(() {
      _visit = v;
      _hh = h;
      _facilities = f;
      _facility = f.isEmpty ? null : f.first;
      _actual = s.clock.today();
      _time = hhmmOf(now.hour, now.minute); // the moment this visit was opened
      _savedTime = saved;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _saving = true;
      _errors = {};
    });
    try {
      await s.fieldWork.recordOutcome(
        widget.visitId,
        VisitOutcome(
          status: _outcome,
          actualDate: _outcome == 'COMPLETED' ? _actual : null,
          visitTime: _outcome == 'CANCELLED' ? null : _time,
          followupRequired: _outcome == 'CANCELLED' ? null : _followup,
          nextFollowupDate: _outcome == 'CANCELLED' || !_followup
              ? null
              : _next,
          referral: _referral && _outcome == 'COMPLETED' && _facility != null
              ? ReferralDraft(
                  facilityId: _facility!,
                  serviceCategory: _service ?? 'GENERAL',
                )
              : null,
        ),
      );
      messenger.showSnackBar(SnackBar(content: Text(l.savedOffline)));
      nav.pop();
    } on DomainValidation catch (e) {
      setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final v = _visit;
    return HeaderScaffold(
      title: l.visitDetails,
      subtitle: v?.householdId,
      showBack: true,
      child: _loading
          ? const LoadingView()
          : v == null
          ? EmptyState(icon: Icons.search_off, title: l.noResults)
          : ListView(
              padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 40),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              catName(l, v.reason),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          StatusBadge(
                            tone: v.status == 'PLANNED'
                                ? Tone.info
                                : v.status == 'COMPLETED'
                                ? Tone.ok
                                : Tone.neutral,
                            icon: v.status == 'COMPLETED'
                                ? Icons.check_circle
                                : Icons.event,
                            label: visitStatusName(l, v.status),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _kv(
                        context,
                        l.nextVisitLabel,
                        fmtDate(context, v.scheduledDate),
                      ),
                      if (_savedTime != null)
                        _kv(
                          context,
                          l.visitTimeLabel,
                          fmtVisitTime(context, _savedTime!.hhmm),
                        ),
                      if (_hh != null) ...[
                        _kv(context, l.villageLabel, _hh!.villageId),
                        _kv(
                          context,
                          l.lastVisitLabel,
                          _hh!.lastVisitDate == null
                              ? l.lastVisitNone
                              : fmtDate(context, _hh!.lastVisitDate),
                        ),
                        _kv(
                          context,
                          l.eligibleFollowups,
                          _hh!.eligibleCategories
                              .map((c) => catName(l, c))
                              .join(', '),
                        ),
                      ],
                    ],
                  ),
                ),
                if (v.status != 'PLANNED')
                  Padding(
                    padding: const EdgeInsets.only(top: Tk.s16),
                    child: Banner2(
                      tone: Tone.info,
                      icon: Icons.info_outline,
                      text: l.errAlreadyFinal,
                    ),
                  )
                else ...[
                  SectionHeader(l.outcomeLabel),
                  ChoiceTile(
                    key: const Key('outcome-completed'),
                    label: l.outcomeCompleted,
                    icon: Icons.check_circle_outline,
                    selected: _outcome == 'COMPLETED',
                    onTap: () => setState(() {
                      _outcome = 'COMPLETED';
                      _followup = false;
                    }),
                  ),
                  ChoiceTile(
                    key: const Key('outcome-missed'),
                    label: l.outcomeMissed,
                    icon: Icons.home_outlined,
                    selected: _outcome == 'MISSED',
                    onTap: () => setState(() {
                      _outcome = 'MISSED';
                      _followup = true;
                      _referral = false;
                    }),
                  ),
                  ChoiceTile(
                    key: const Key('outcome-cancelled'),
                    label: l.outcomeCancelled,
                    icon: Icons.cancel_outlined,
                    selected: _outcome == 'CANCELLED',
                    onTap: () => setState(() {
                      _outcome = 'CANCELLED';
                      _followup = false;
                      _referral = false;
                    }),
                  ),
                  if (_outcome != 'CANCELLED') ...[
                    const SizedBox(height: 8),
                    _WhenTile(
                      date: fmtDate(context, _actual),
                      time: fmtVisitTime(context, _time),
                      caption: l.visitTimeAuto,
                      note: l.visitTimeLocal,
                      error: _err(l, 'visitTime') ?? _err(l, 'actualDate'),
                    ),
                  ],
                  if (_outcome != 'CANCELLED') ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const Key('followup-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.followupNeeded),
                      value: _followup,
                      onChanged: (x) => setState(() => _followup = x),
                    ),
                    if (_followup)
                      DateField(
                        fieldKey: const Key('next-date'),
                        label: l.nextVisitDate,
                        value: _next,
                        onChanged: (d) => setState(() => _next = d),
                        errorText: _err(l, 'nextDate'),
                        first: s.clock.today(),
                      ),
                    if (!_followup && _errors['nextDate'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _err(l, 'nextDate')!,
                          style: const TextStyle(
                            color: Tk.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                  if (_outcome == 'COMPLETED') ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const Key('referral-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.recommendReferral),
                      value: _referral,
                      onChanged: _facilities.isEmpty
                          ? null
                          : (x) => setState(() => _referral = x),
                    ),
                    if (_facilities.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l.noFacilitiesKnown,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (_referral) ...[
                      DropdownButtonFormField<String>(
                        key: const Key('facility-field'),
                        initialValue: _facility,
                        decoration: InputDecoration(labelText: l.facilityLabel),
                        items: [
                          for (final f in _facilities)
                            DropdownMenuItem(value: f, child: Text(f)),
                        ],
                        onChanged: (x) => setState(() => _facility = x),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _service,
                        decoration: InputDecoration(labelText: l.serviceLabel),
                        items: [
                          for (final c in serviceCategories)
                            DropdownMenuItem(
                              value: c,
                              child: Text(catName(l, c)),
                            ),
                        ],
                        onChanged: (x) => setState(() => _service = x),
                      ),
                    ],
                  ],
                  if (_errors['referral'] != null || _errors['status'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Banner2(
                        tone: Tone.danger,
                        icon: Icons.error_outline,
                        text: _err(
                          l,
                          _errors.containsKey('referral')
                              ? 'referral'
                              : 'status',
                        )!,
                      ),
                    ),
                  const SizedBox(height: Tk.s20),
                  FilledButton.icon(
                    key: const Key('save-visit'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(l.save),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.savedOffline,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
    );
  }

  String? _err(AppLocalizations l, String field) =>
      _errors[field] == null ? null : validationText(l, field, _errors[field]!);

  Widget _kv(BuildContext c, String k, String v) => KeyValue(k, v);
}

/// Date and time of the visit: read-only. Shows what the phone recorded when the visit was opened; nothing here can be edited.
class _WhenTile extends StatelessWidget {
  const _WhenTile({
    required this.date,
    required this.time,
    required this.caption,
    required this.note,
    this.error,
  });
  final String date, time, caption, note;
  final String? error;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        container: true,
        label:
            '${AppLocalizations.of(context).visitTimeLabel}: $date, $time. $caption',
        excludeSemantics: true,
        child: AppCard(
          key: const Key('visit-time'),
          padding: const EdgeInsets.symmetric(
            horizontal: Tk.s16,
            vertical: Tk.s12,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Tk.mintSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: Tk.primaryDark,
                ),
              ),
              const SizedBox(width: Tk.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).visitTimeLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      date,
                      key: const Key('visit-date-value'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      time,
                      key: const Key('visit-time-value'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(caption, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(
                Icons.lock_outline_rounded,
                color: Tk.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            error!,
            style: const TextStyle(
              color: Tk.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 6, left: 4, bottom: 10),
        child: Text(note, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}
