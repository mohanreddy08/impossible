import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/outbox_op.dart';
import '../../l10n/app_localizations.dart';
import '../../services/data_bus.dart';
import '../../state/app_services.dart';
import '../../state/sync_controller.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';

String opTitle(AppLocalizations l, OutboxOp o) =>
    switch ((o.entityType, o.opType)) {
      ('visit', 'create') => l.opNewVisit,
      ('visit', 'update') => l.opVisitOutcome,
      ('referral', 'create') => l.opNewReferral,
      ('referral', 'update') => l.opReferralUpdate,
      ('household', 'create') => l.opNewHousehold,
      _ => l.opHouseholdUpdate,
    };

/// Plain-language reason for the last problem. Codes are the client's own (NETWORK, TIMEOUT...) or the server's error_code.
String opErrorText(AppLocalizations l, OutboxOp o) {
  switch (o.lastErrorCode) {
    case null:
      return '';
    case 'NETWORK':
      return l.syncOffline;
    case 'TIMEOUT':
      return l.errTimeout;
    case 'UNAUTHORIZED':
      return l.errUnauthorized;
    case 'TEMPORARY_FAILURE':
    case 'NO_RESULT':
    case 'SERVER':
      return l.syncServerError;
    default:
      return o.lastErrorMessage ?? o.lastErrorCode!;
  }
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  List<OutboxOp> _ops = [];
  List<OutboxOp> _done = [];
  bool _loading = true;
  int _seen = -1;

  Future<void> _load() async {
    final s = context.read<AppServices>();
    final all = await s.store.ops(limit: 100);
    final done = await s.store.ops(state: OpState.acknowledged, limit: 10);
    await s.sync.refresh();
    if (mounted) {
      setState(() {
        _ops = all;
        _done = done.reversed.toList();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final sync = context.watch<SyncController>();
    final bus = context.watch<DataBus>();
    if (_seen != bus.version) {
      _seen = bus.version;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final c = sync.counts;
    final rep = sync.lastReport;
    String? bannerText;
    Tone bannerTone = Tone.warn;
    if (sync.link == ServerLink.authFailed) {
      bannerText = l.syncAuthFailed;
      bannerTone = Tone.danger;
    } else if (sync.link == ServerLink.notConfigured) {
      bannerText = l.syncNotConfigured;
    } else if (sync.link == ServerLink.unreachable) {
      bannerText = (rep?.offline ?? false) ? l.syncOffline : l.syncServerError;
    }
    final pending = _ops.where((o) => o.state == OpState.pending).toList();
    final failed = _ops.where((o) => o.state == OpState.rejected).toList();
    final conflict = _ops.where((o) => o.state == OpState.conflict).toList();
    return HeaderScaffold(
      title: l.syncTitle,
      subtitle: sync.lastSyncAt == null
          ? l.neverSynced
          : l.lastSynced(fmtDateTimeIso(context, sync.lastSyncAt)),
      showBack: true,
      showStatus: false,
      child: _loading
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 40),
              children: [
                if (bannerText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Banner2(
                      tone: bannerTone,
                      icon: bannerTone == Tone.danger
                          ? Icons.vpn_key_off_outlined
                          : Icons.cloud_off,
                      text: bannerText,
                    ),
                  ),
                FilledButton.icon(
                  key: const Key('sync-now'),
                  onPressed: sync.syncing ? null : () => sync.syncNow(),
                  icon: sync.syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync),
                  label: Text(sync.syncing ? l.syncing : l.syncNow),
                ),
                if (rep != null && rep.ok && !sync.syncing)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: (rep.rejected + rep.conflicts + rep.retryable) == 0
                        ? Banner2(
                            tone: Tone.ok,
                            icon: Icons.check_circle_outline,
                            text: l.syncResultOk(rep.acknowledged),
                          )
                        : Banner2(
                            tone: Tone.warn,
                            icon: Icons.warning_amber_rounded,
                            text: l.syncNeedsAttention,
                          ),
                  ),
                const SizedBox(height: 12),
                Banner2(
                  tone: Tone.info,
                  icon: Icons.info_outline,
                  text: l.syncNeverSentWarning,
                ),
                const SizedBox(height: 12),
                TwoColumnGrid(
                  children: [
                    StatTile(
                      count: c.pending,
                      label: l.sectionPending,
                      icon: Icons.schedule_send_outlined,
                      tone: Tone.warn,
                    ),
                    StatTile(
                      count: c.failed,
                      label: l.sectionFailed,
                      icon: Icons.error_outline,
                      tone: Tone.danger,
                    ),
                    StatTile(
                      count: c.conflict,
                      label: l.sectionConflict,
                      icon: Icons.compare_arrows,
                      tone: Tone.danger,
                    ),
                    StatTile(
                      count: c.synced,
                      label: l.sectionSynced,
                      icon: Icons.cloud_done_outlined,
                      tone: Tone.ok,
                    ),
                  ],
                ),
                if (_ops.isEmpty && _done.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: Icons.cloud_done_outlined,
                      title: l.nothingPending,
                    ),
                  ),
                if (conflict.isNotEmpty) ...[
                  SectionHeader(l.sectionConflict),
                  for (final o in conflict)
                    _OpCard(
                      op: o,
                      actions: [
                        _btn(
                          l.resolveConflict,
                          Icons.compare_arrows,
                          () => _resolve(context, o),
                          key: 'resolve-${o.opId}',
                        ),
                      ],
                    ),
                ],
                if (failed.isNotEmpty) ...[
                  SectionHeader(l.sectionFailed),
                  for (final o in failed)
                    _OpCard(
                      op: o,
                      actions: [
                        _btn(
                          l.retryOp,
                          Icons.refresh,
                          () => s.sync.engine.retry(o.opId),
                          key: 'retry-${o.opId}',
                        ),
                        _btn(
                          l.discardOp,
                          Icons.delete_outline,
                          () => _discard(context, o),
                          key: 'discard-${o.opId}',
                        ),
                      ],
                    ),
                ],
                if (pending.isNotEmpty) ...[
                  SectionHeader(l.sectionPending),
                  for (final o in pending) _OpCard(op: o, actions: const []),
                ],
                if (_done.isNotEmpty) ...[
                  SectionHeader(l.sectionSynced),
                  for (final o in _done)
                    _OpCard(op: o, actions: const [], done: true),
                ],
              ],
            ),
    );
  }

  Widget _btn(
    String label,
    IconData icon,
    VoidCallback onTap, {
    required String key,
  }) => OutlinedButton.icon(
    key: Key(key),
    onPressed: onTap,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );

  Future<void> _discard(BuildContext context, OutboxOp o) async {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(l.discardConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.discard),
          ),
        ],
      ),
    );
    if (ok == true) await s.sync.engine.discard(o.opId);
  }

  Future<void> _resolve(BuildContext context, OutboxOp o) async {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final c = o.conflict ?? {};
    final server = (c['server_values'] as Map?)?.cast<String, dynamic>() ?? {};
    final mine = (c['client_values'] as Map?)?.cast<String, dynamic>() ?? {};
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.sectionConflict),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.conflictExplain),
              const SizedBox(height: 12),
              for (final k in server.keys) ...[
                Text(
                  k.replaceAll('_', ' '),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text('${l.serverHas}: ${server[k]}'),
                Text('${l.youChanged}: ${mine[k]}'),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('keep-server'),
            onPressed: () async {
              Navigator.pop(d);
              await s.sync.engine.resolveConflict(o.opId, keepServer: true);
            },
            child: Text(l.keepServer),
          ),
          FilledButton(
            key: const Key('keep-mine'),
            onPressed: () async {
              Navigator.pop(d);
              await s.sync.engine.resolveConflict(o.opId, keepServer: false);
              s.sync.scheduleAutoSync();
            },
            child: Text(l.keepMine),
          ),
        ],
      ),
    );
  }
}

class _OpCard extends StatelessWidget {
  const _OpCard({required this.op, required this.actions, this.done = false});
  final OutboxOp op;
  final List<Widget> actions;
  final bool done;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (tone, icon, label) = switch (op.state) {
      OpState.pending => (
        Tone.warn,
        Icons.schedule_send_outlined,
        l.sectionPending,
      ),
      OpState.rejected => (Tone.danger, Icons.error_outline, l.sectionFailed),
      OpState.conflict => (
        Tone.danger,
        Icons.compare_arrows,
        l.sectionConflict,
      ),
      OpState.acknowledged => (
        Tone.ok,
        Icons.cloud_done_outlined,
        l.sectionSynced,
      ),
    };
    final err = op.state == OpState.acknowledged ? '' : opErrorText(l, op);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        key: ValueKey('op-${op.opId}'),
        padding: const EdgeInsets.all(Tk.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    opTitle(l, op),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusBadge(tone: tone, icon: icon, label: label, dense: true),
              ],
            ),
            Text(op.entityId, style: Theme.of(context).textTheme.bodySmall),
            if (op.attempts > 0 && !done)
              Text(
                l.attemptsN(op.attempts),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (err.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  err,
                  style: const TextStyle(
                    color: Tk.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(spacing: 8, runSpacing: 8, children: actions),
              ),
          ],
        ),
      ),
    );
  }
}
