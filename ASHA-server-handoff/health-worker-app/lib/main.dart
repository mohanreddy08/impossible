import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/local/database.dart';
import 'services/alert_notifier.dart';
import 'services/settings.dart';
import 'state/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // the app shows almost no pictures: keep the decoded-image cache small so it never holds much memory
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 8 << 20
    ..maximumSize = 40;
  await initializeDateFormatting('en');
  await initializeDateFormatting('te');
  final prefs = await SharedPreferences.getInstance();
  final adb = await AppDatabase.open();
  final rules = await rootBundle.loadString('assets/safety/danger_rules.json');
  final services = await AppServices.create(
    prefs: prefs,
    secrets: PlatformSecretStore(),
    adb: adb,
    safetyRulesJson: rules,
    notifier: PlatformAlertNotifier(),
  );
  runApp(HealthApp(services: services));
}
