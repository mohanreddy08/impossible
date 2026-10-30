import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';
import 'h5_map_screen.dart';
import 'h5_visit_list_screen.dart';
import 'referrals_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget item(IconData icon, String label, Widget page, {String? key}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            key: key == null ? null : Key(key),
            onTap: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => page)),
            semanticLabel: label,
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Icon(icon, color: Tk.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Tk.textMuted),
                ],
              ),
            ),
          ),
        );
    return HeaderScaffold(
      title: l.moreTitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 120),
        children: [
          item(
            Icons.checklist_rtl,
            l.h5MoreVisit,
            const H5VisitListScreen(),
            key: 'more-h5-visits',
          ),
          item(
            Icons.map_outlined,
            l.h5MoreMap,
            const H5MapScreen(),
            key: 'more-h5-map',
          ),
          item(
            Icons.local_hospital_outlined,
            l.referralsTitle,
            const ReferralsScreen(),
            key: 'more-referrals',
          ),
          item(
            Icons.bar_chart,
            l.reportsTitle,
            const ReportsScreen(),
            key: 'more-reports',
          ),
          item(Icons.sync, l.syncTitle, const SyncScreen(), key: 'more-sync'),
          item(
            Icons.settings_outlined,
            l.settingsTitle,
            const SettingsScreen(),
            key: 'more-settings',
          ),
        ],
      ),
    );
  }
}
