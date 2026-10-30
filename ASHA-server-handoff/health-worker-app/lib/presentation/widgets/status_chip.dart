import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/connectivity_controller.dart';
import '../../state/sync_controller.dart';
import '../screens/sync_screen.dart';

/// Always-visible connection + pending-sync indicator. Words and icons, not colour alone. Tap -> sync centre.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final online = context.watch<ConnectivityController>().online;
    final sync = context.watch<SyncController>();
    final unsynced = sync.counts.unsynced;
    final (IconData icon, String text) = !online
        ? (Icons.cloud_off, l.statusOffline)
        : sync.link == ServerLink.unreachable
        ? (Icons.cloud_off, l.statusServerUnreachable)
        : (Icons.cloud_done_outlined, l.statusOnline);
    final pending = unsynced > 0 ? l.syncPendingCount(unsynced) : null;
    return Semantics(
      button: true,
      label: '$text. ${pending ?? l.allSynced}. ${l.semStatusChip}',
      excludeSemantics: true,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const SyncScreen())),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(Tk.rChip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: online ? Tk.primaryDark : Tk.warn),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      style: const TextStyle(
                        color: Tk.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          unsynced > 0
                              ? Icons.sync_problem_outlined
                              : Icons.check_circle_outline,
                          size: 13,
                          color: unsynced > 0 ? Tk.warn : Tk.ok,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            pending ?? l.allSynced,
                            style: TextStyle(
                              color: unsynced > 0 ? Tk.warn : Tk.ok,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
