import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart' show isTest;
import 'package:health_companion/app.dart';
import 'package:health_companion/core/clock.dart';
import 'package:health_companion/h5/h5_data.dart';
import 'package:health_companion/h5/h5_pipeline.dart';
import 'package:health_companion/services/alert_notifier.dart';
import 'package:health_companion/services/report_service.dart';
import 'package:health_companion/services/settings.dart';
import 'package:health_companion/services/speech_capabilities.dart';
import 'package:health_companion/services/telugu_voice.dart';
import 'package:health_companion/services/voice_input.dart';
import 'package:health_companion/state/app_services.dart';
import 'package:health_companion/state/connectivity_controller.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';
import 'harness.dart';

class FakeSharer implements FileSharer {
  final List<String> shared = [];
  @override
  Future<void> shareFile(
    String path, {
    required String mime,
    String? subject,
  }) async => shared.add('$mime:$path');
}

class AppRig {
  AppRig(this.services, this.server, this.conn, this.connStream, this.sharer);
  final AppServices services;
  final FakeServer server;
  final ConnectivityController conn;
  final StreamController<List<ConnectivityResult>> connStream;
  final FakeSharer sharer;
  FakeAlertNotifier get fakeNotifier => services.notifier as FakeAlertNotifier;
}

Future<H5Assistant>? _assistantCache;

/// The protocol-book engine, built once per test run from the files in assets/h5.
Future<H5Assistant> h5AssistantForTests() async => _assistantCache ??=
    Future.value(H5Assistant.fromJson(File('assets/h5/rules.json').readAsStringSync(), File('assets/h5/protocols.json').readAsStringSync()));

Future<H5Data>? _h5Cache;

/// The Chandrapuri data, read once per test run (it never changes).
Future<H5Data> h5ForTests() => _h5Cache ??= H5Data.load((p) async => File(p).readAsString());

/// Builds the REAL app services (SQLite via ffi, real sync engine/QA service) with a fake HTTP backend.
Future<AppRig> buildRig({
  bool demo = true,
  bool sampleProtocol = false, // the FICTIONAL sample protocol text: off unless a test is about it
  bool configured = true,
  bool aiAssist = true, // existing tests exercise the optional online helpers; the product default is OFF
  FakeServer? server,
  String lang = 'en',
  bool autoSync = false,
  VoiceInput? voice,
  SpeechCapabilityProbe speechProbe = FixedSpeechProbe
      .allOffline, // a phone with English and Telugu offline packs
  bool allowOnlineSpeech = false,
  // offline test mode: no connection reported AND every HTTP request fails, so any accidental network use is visible
  bool offline = false,
  TeluguAsrEngine? teluguEngine,
  Directory? modelDir,
  Duration? explainTimeout,
  bool h5Ask = false, // the protocol-book engine in Ask: off unless a test is about it
}) async {
  await initializeDateFormatting('en');
  await initializeDateFormatting('te');
  SharedPreferences.setMockInitialValues({
    'lang': lang,
    'ai_assist': aiAssist,
    'online_speech': allowOnlineSpeech,
    if (configured) 'base_url': 'http://fake.local',
  });
  final prefs = await SharedPreferences.getInstance();
  final secrets = MemorySecretStore();
  if (configured) await secrets.write('api_key', 'test-key');
  final adb = await openTestDb();
  final srv = server ?? FakeServer();
  if (offline) srv.down = true;
  final stream = StreamController<List<ConnectivityResult>>.broadcast();
  final conn = ConnectivityController(
    stream: stream.stream,
    initial: () async => [
      offline ? ConnectivityResult.none : ConnectivityResult.wifi,
    ],
  );
  final sharer = FakeSharer();
  final tmp = Directory.systemTemp.createTempSync('hc_reports_');
  final h5 = await h5ForTests();
  final s = await AppServices.create(
    h5Loader: () async => h5,
    h5Ask: h5Ask,
    h5AssistantLoader: h5AssistantForTests,
    prefs: prefs,
    secrets: secrets,
    adb: adb,
    safetyRulesJson: File('assets/safety/danger_rules.json').readAsStringSync(),
    httpClient: srv.client(),
    connectivity: conn,
    sharer: sharer,
    demoLoader: () => File('assets/demo/demo_seed.json').readAsString(),
    aliasLoader: () async =>
        File('assets/data/aliases.json').readAsStringSync(),
    demoProtocolLoader: sampleProtocol
        ? () => File('assets/data/passages.json').readAsString()
        : () async => throw StateError('no sample protocol in this test'),
    clock: AppClock(now: () => DateTime(2026, 10, 13, 9)),
    tempDir: () async => tmp,
    voice: voice ?? NoVoiceInput(),
    speechProbe: speechProbe,
    teluguEngine: teluguEngine,
    modelDir: () async => modelDir ?? tmp,
    explainTimeout: explainTimeout,
    autoSync: autoSync, // off by default: tests drive sync explicitly (auto-sync has its own test)
  );
  if (demo) {
    await s.demo.load();
    await s.settings.setUseDemoDate(true);
  }
  return AppRig(s, srv, conn, stream, sharer);
}

/// sqflite_ffi does real async I/O: let it run, then pump frames, until [until] holds (or time runs out).
Future<void> settle(
  WidgetTester t, {
  bool Function()? until,
  int maxRounds = 60,
}) async {
  for (var i = 0; i < maxRounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 50));
    if (until != null && until()) return;
  }
}

Future<void> pumpApp(
  WidgetTester t,
  AppRig rig, {
  Widget? home,
  Size size = const Size(412, 892),
  double textScale = 1.0,
}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    t.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await t.pumpWidget(HealthApp(services: rig.services, home: home));
  await settle(t, maxRounds: 15);
}

/// Scrolls the first scrollable until [finder] is built AND fully on screen (lists build children lazily, like on a real phone).
Future<void> reveal(WidgetTester t, Finder finder) async {
  await t.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await t.ensureVisible(
    finder,
  ); // built != on screen: bring it fully into the viewport
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> revealUp(WidgetTester t, Finder finder) async {
  await t.scrollUntilVisible(
    finder,
    -250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await _center(t, finder);
}

/// Lets the debounced auto-sync (2 s) fire and finish so no timer is left pending at the end of a test.
Future<void> flushAutoSync(WidgetTester t) async {
  await t.pump(const Duration(seconds: 3));
  await settle(t, maxRounds: 10);
}

/// Built != tappable: put the widget in the middle of the viewport (not under the header edge).
Future<void> _center(WidgetTester t, Finder finder) async {
  Scrollable.ensureVisible(
    t.element(finder),
    alignment: 0.5,
    duration: const Duration(milliseconds: 50),
  );
  await t.pump(const Duration(milliseconds: 120));
  await t.pump(const Duration(milliseconds: 120));
}

/// testWidgets that lets in-flight screen queries finish before the test ends (sqflite_ffi does real async I/O).
@isTest
void uiTest(String description, Future<void> Function(WidgetTester t) body) {
  testWidgets(description, (t) async {
    await body(t);
    await settle(t, maxRounds: 12);
  });
}
