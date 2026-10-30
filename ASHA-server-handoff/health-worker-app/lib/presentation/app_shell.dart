import 'package:flutter/material.dart';

import 'screens/ask_screen.dart';
import 'screens/home_screen.dart';
import 'screens/households_screen.dart';
import 'screens/more_screen.dart';
import 'screens/planner_screen.dart';
import 'widgets/pill_nav.dart';

/// Five-tab shell. Tabs are created lazily (a tab you never open costs no memory/CPU) and then kept alive.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  late int _index = widget.initialTab;
  late final AnimationController _swap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  late final Animation<double> _swapCurve = CurvedAnimation(
    parent: _swap,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _swap.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    if (!MediaQuery.disableAnimationsOf(context)) _swap.forward(from: 0);
  }

  final Set<int> _built = {};

  Widget _tab(int i) => switch (i) {
    0 => HomeScreen(onGoTo: _go),
    1 => const PlannerScreen(embedded: true),
    2 => const AskScreen(),
    3 => const HouseholdsScreen(),
    _ => const MoreScreen(),
  };

  @override
  Widget build(BuildContext context) {
    _built.add(_index);
    return Scaffold(
      extendBody: false,
      body: FadeTransition(
        // switching tabs: the new tab eases in (fade + a small rise) instead of snapping
        opacity: Tween(begin: 0.35, end: 1.0).animate(_swapCurve),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(_swapCurve),
          child: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < 5; i++)
                _built.contains(i) ? _tab(i) : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: ColoredBox(
        color: const Color(0xFFF3F7F7),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: PillNav(index: _index, onChanged: _go),
          ),
        ),
      ),
    );
  }
}
