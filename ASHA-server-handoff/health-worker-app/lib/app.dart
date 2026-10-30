import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'presentation/launch/launch_gate.dart';
import 'services/data_bus.dart';
import 'services/settings.dart';
import 'state/app_services.dart';
import 'state/connectivity_controller.dart';
import 'state/sync_controller.dart';

class HealthApp extends StatefulWidget {
  const HealthApp({super.key, required this.services, this.home});
  final AppServices services;
  final Widget? home;
  @override
  State<HealthApp> createState() => _HealthAppState();
}

class _HealthAppState extends State<HealthApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.services.sync.refresh();
    widget.services.bus.addListener(_onData);
    widget.services.settings.addListener(_onData);
    _onData();
    // Android 13+ needs the notification permission; the system only shows the prompt while it is still undecided.
    // A brand-new install is asked at the end of onboarding instead (after it has been explained).
    if (widget.services.settings.alertsEnabled &&
        widget.services.settings.onboardingDone) {
      widget.services.notifier.requestPermission().then(
        (_) => widget.services.alerts.refresh(),
      );
    }
  }

  /// Any change to the data (sync, a saved visit) or to the alert setting: re-check who is urgent. Works offline.
  void _onData() => widget.services.alerts.refresh();

  @override
  void dispose() {
    widget.services.bus.removeListener(_onData);
    widget.services.settings.removeListener(_onData);
    WidgetsBinding.instance.removeObserver(this);
    widget.services.sync.cancelScheduled();
    super.dispose();
  }

  /// Foreground return: refresh counts and try to send what is waiting. (iOS does not run background sync like Android: this is the reliable path.)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.services.sync.refresh();
      widget.services.sync.scheduleAutoSync();
      widget.services.bus.changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: s),
        ChangeNotifierProvider<AppSettings>.value(value: s.settings),
        ChangeNotifierProvider<DataBus>.value(value: s.bus),
        ChangeNotifierProvider<ConnectivityController>.value(
          value: s.connectivity,
        ),
        ChangeNotifierProvider<SyncController>.value(value: s.sync),
      ],
      child: Consumer<AppSettings>(
        builder: (context, st, _) => MaterialApp(
          title: 'ASHA',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          scrollBehavior: const _NoStretchScrollBehavior(),
          locale: Locale(st.language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: widget.home ?? const LaunchGate(),
        ),
      ),
    );
  }
}

/// No stretch/glow when scrolling past the end of a list: it made screens look like they were stretching.
class _NoStretchScrollBehavior extends MaterialScrollBehavior {
  const _NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}
