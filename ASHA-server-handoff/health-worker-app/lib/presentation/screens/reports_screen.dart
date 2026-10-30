import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../data/api/api_models.dart';
import '../../domain/rules/report_rules.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_services.dart';
import '../../state/connectivity_controller.dart';
import '../error_text.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';

/// Hospital-sharing summary. Aggregate counts only, no household or patient identifiers.
/// "Summary from this phone" works offline; the server report adds stored/PDF output when online.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<String> _facilities = [];
  String? _facility;
  int _days = 90;
  ({ReportSummary summary, String freshness, String? lastSyncAt})? _local;
  ServerReport? _server;
  bool _loading = true, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final f = await context.read<AppServices>().store.facilities();
    if (!mounted) return;
    setState(() {
      _facilities = f;
      _facility = f.isEmpty ? null : f.first;
      _loading = false;
    });
    if (_facility != null) await _computeLocal();
  }

  (DateTime, DateTime) _period() {
    final end = context.read<AppServices>().clock.today();
    return (end.subtract(Duration(days: _days)), end);
  }

  Future<void> _computeLocal() async {
    final s = context.read<AppServices>();
    final (a, b) = _period();
    final r = await s.reports.localSummary(_facility!, a, b);
    if (mounted) {
      setState(() {
        _local = r;
        _server = null;
        _error = null;
      });
    }
  }

  Future<void> _server_() async {
    final s = context.read<AppServices>();
    final l = AppLocalizations.of(context);
    final (a, b) = _period();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await s.reports.serverReport(_facility!, a, b);
      if (mounted) setState(() => _server = r);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(String fmt) async {
    final s = context.read<AppServices>();
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await s.reports.shareServerFile(
        _server!.reportId,
        fmt,
        subject: l.localeName == 'te' ? l.shareSubject : 'Referral summary',
      );
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final online = context.watch<ConnectivityController>().online;
    return HeaderScaffold(
      title: l.reportsTitle,
      showBack: true,
      child: _loading
          ? const LoadingView()
          : _facilities.isEmpty
          ? EmptyState(icon: Icons.bar_chart, title: l.noFacilities)
          : ListView(
              padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 40),
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: const Key('report-facility'),
                  initialValue: _facility,
                  decoration: InputDecoration(labelText: l.facilityPick),
                  items: [
                    for (final f in _facilities)
                      DropdownMenuItem(value: f, child: Text(f)),
                  ],
                  onChanged: (v) {
                    setState(() => _facility = v);
                    _computeLocal();
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _days,
                  decoration: InputDecoration(labelText: l.periodLabel),
                  items: [
                    DropdownMenuItem(value: 30, child: Text(l.period30)),
                    DropdownMenuItem(value: 90, child: Text(l.period90)),
                    DropdownMenuItem(value: 180, child: Text(l.period180)),
                  ],
                  onChanged: (v) {
                    setState(() => _days = v ?? 90);
                    _computeLocal();
                  },
                ),
                if (_local != null) ...[
                  SectionHeader(l.reportLocal),
                  _SummaryCard(
                    key: const Key('local-summary'),
                    note: l.reportComputedLocal,
                    recommended: _local!.summary.recommended,
                    planned: _local!.summary.planned,
                    confirmed: _local!.summary.attendanceConfirmed,
                    total: _local!.summary.total,
                    byCategory: _local!.summary.byCategory,
                    excluded: _local!.summary.excluded,
                    freshness: _local!.freshness,
                    lastSyncAt: _local!.lastSyncAt,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('share-local-csv'),
                    onPressed: () =>
                        context.read<AppServices>().reports.shareLocalCsv(
                          _local!.summary,
                          _local!.freshness,
                          _local!.lastSyncAt,
                          subject: l.localeName == 'te'
                              ? l.shareSubject
                              : 'Referral summary (this device)',
                        ),
                    icon: const Icon(Icons.ios_share),
                    label: Text(l.shareCsv),
                  ),
                ],
                const SizedBox(height: Tk.s16),
                FilledButton.icon(
                  key: const Key('server-report'),
                  onPressed: (!online || _busy) ? null : _server_,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_download_outlined),
                  label: Text(l.reportServer),
                ),
                if (!online)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l.reportOnlineOnly,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Banner2(
                      tone: Tone.danger,
                      icon: Icons.error_outline,
                      text: _error!,
                    ),
                  ),
                if (_server != null) ...[
                  SectionHeader(l.reportComputedServer),
                  _SummaryCard(
                    key: const Key('server-summary'),
                    note: l.generatedAt(_server!.generatedAt.substring(0, 10)),
                    recommended: _server!.recommended,
                    planned: _server!.planned,
                    confirmed: _server!.attendanceConfirmed,
                    total: _server!.total,
                    byCategory: _server!.byCategory,
                    excluded: _server!.excluded,
                    freshness: _server!.freshness,
                    lastSyncAt: _server!.lastSyncAt,
                    followUpsDue: _server!.followUpsDue,
                    followUpsDone: _server!.followUpsCompleted,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('share-csv'),
                          onPressed: _busy ? null : () => _share('csv'),
                          icon: const Icon(Icons.table_chart_outlined),
                          label: Text(l.shareCsv),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('share-pdf'),
                          onPressed: _busy ? null : () => _share('pdf'),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: Text(l.sharePdf),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Tk.s16),
                Banner2(
                  tone: Tone.info,
                  icon: Icons.lock_outline,
                  text: l.privacyNoticeReport,
                ),
              ],
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    super.key,
    required this.note,
    required this.recommended,
    required this.planned,
    required this.confirmed,
    required this.total,
    required this.byCategory,
    required this.excluded,
    required this.freshness,
    this.lastSyncAt,
    this.followUpsDue,
    this.followUpsDone,
  });
  final String note, freshness;
  final int recommended, planned, confirmed, total;
  final int? followUpsDue, followUpsDone;
  final Map<String, int> byCategory, excluded;
  final String? lastSyncAt;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget row(String label, int n, IconData icon, Tone tone) {
      final c = toneColors(tone);
      return Semantics(
        label: '$label: $n',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Icon(icon, color: c.fg, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Text(
                '$n',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(color: c.fg),
              ),
            ],
          ),
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(note, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          row(l.countRecommended, recommended, Icons.outlined_flag, Tone.warn),
          row(l.countPlanned, planned, Icons.event, Tone.info),
          row(l.countConfirmed, confirmed, Icons.verified_outlined, Tone.ok),
          const Divider(),
          row(l.countTotal, total, Icons.functions, Tone.neutral),
          if (followUpsDue != null)
            row(l.followUpsDue, followUpsDue!, Icons.event_note, Tone.neutral),
          if (followUpsDone != null)
            row(l.followUpsDone, followUpsDone!, Icons.task_alt, Tone.neutral),
          if (byCategory.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(l.byService, style: Theme.of(context).textTheme.titleMedium),
            for (final e in byCategory.entries)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(catName(l, e.key))),
                    Text(
                      '${e.value}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
          if (excluded.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l.excludedRecords,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final e in excluded.entries)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(e.key.replaceAll('_', ' '))),
                    Text(
                      '${e.value}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          Banner2(
            tone: freshness == 'FRESH'
                ? Tone.ok
                : freshness == 'RECENT'
                ? Tone.info
                : Tone.warn,
            icon: freshness == 'FRESH'
                ? Icons.check_circle_outline
                : Icons.schedule,
            text:
                '${freshnessName(l, freshness)}${lastSyncAt == null ? '' : '\n${l.lastSynced(fmtDateTimeIso(context, lastSyncAt))}'}',
          ),
        ],
      ),
    );
  }
}
