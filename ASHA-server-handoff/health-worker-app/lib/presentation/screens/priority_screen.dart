import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../domain/rules/priority_rules.dart';
import '../../l10n/app_localizations.dart';
import '../../services/data_bus.dart';
import '../../services/priority_service.dart';
import '../../state/app_services.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';
import '../widgets/priority_card.dart';
import 'households_screen.dart';

/// Every household that is waiting for something, most urgent first.
class PriorityScreen extends StatefulWidget {
  const PriorityScreen({super.key});
  @override
  State<PriorityScreen> createState() => _PriorityScreenState();
}

class _PriorityScreenState extends State<PriorityScreen> {
  List<HouseholdUrgency>? _items;
  int _seen = -1;

  Future<void> _load() async {
    final s = context.read<AppServices>();
    final list = await PriorityService(s.store).ranked(s.clock.today());
    if (mounted) setState(() => _items = list);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bus = context.watch<DataBus>();
    if (_seen != bus.version) {
      _seen = bus.version;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final items = _items;
    return HeaderScaffold(
      title: l.priorityTitle,
      subtitle: l.prioritySubtitle,
      showBack: true,
      child: items == null
          ? const LoadingView()
          : items.isEmpty
          ? EmptyState(
              icon: Icons.task_alt,
              title: l.priorityEmpty,
              body: l.priorityNote,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 40),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: Tk.s12),
              itemBuilder: (context, i) {
                if (i == items.length) {
                  return Text(
                    l.priorityNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                }
                return PriorityCard(
                  item: items[i],
                  rank: i + 1,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HouseholdDetailScreen(
                        householdId: items[i].householdId,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
