import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_services.dart';
import '../app_shell.dart';
import 'onboarding_screen.dart';
import 'splash_screen.dart';

enum _Stage { splash, onboarding, app }

/// What the worker sees when ASHA opens: the splash (logo and name), then either the first-run onboarding (new installs) or
/// straight into the app (everyone else). Crossfades between the three.
class LaunchGate extends StatefulWidget {
  const LaunchGate({
    super.key,
    this.splashFor = const Duration(milliseconds: 1900),
  });
  final Duration splashFor;
  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  _Stage _stage = _Stage.splash;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.splashFor, () {
      if (!mounted) return;
      final done = context.read<AppServices>().settings.onboardingDone;
      setState(() => _stage = done ? _Stage.app : _Stage.onboarding);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    final s = context.read<AppServices>();
    await s.settings.setOnboardingDone();
    // the notification permission is asked for here, after the worker has read why (not over the splash on first launch)
    if (s.settings.alertsEnabled) {
      await s.notifier.requestPermission();
      unawaited(s.alerts.refresh());
    }
    if (mounted) setState(() => _stage = _Stage.app);
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (_stage) {
      _Stage.splash => const SplashScreen(key: ValueKey('splash')),
      _Stage.onboarding => OnboardingScreen(
        key: const ValueKey('onboarding'),
        onDone: _finishOnboarding,
      ),
      _Stage.app => const AppShell(key: ValueKey('app')),
    };
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      child: child,
    );
  }
}
