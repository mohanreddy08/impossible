import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/clock.dart';
import '../data/api/api_client.dart';
import '../data/local/database.dart';
import '../data/local/local_store.dart';
import '../domain/safety/safety_engine.dart';
import '../h5/h5_data.dart';
import '../h5/h5_pipeline.dart';
import '../services/data_bus.dart';
import '../services/demo_data.dart';
import '../services/field_work_service.dart';
import '../services/protocol_library.dart';
import '../services/record_answers.dart';
import '../services/qa_service.dart';
import '../services/report_service.dart';
import '../services/settings.dart';
import '../services/alert_notifier.dart';
import '../services/priority_service.dart';
import '../services/urgent_alerts.dart';
import '../services/speech_capabilities.dart';

import 'package:path_provider/path_provider.dart';

import '../maps/offline_map_source.dart';
import '../services/telugu_voice.dart';
import '../services/voice_input.dart';
import '../services/sync_engine.dart';
import 'connectivity_controller.dart';
import 'sync_controller.dart';

/// Composition root. Every dependency is constructed here and injected; widgets never build their own clients or databases.
class AppServices {
  AppServices({
    required this.settings,
    required this.clock,
    required this.adb,
    required this.store,
    required this.bus,
    required this.api,
    required this.connectivity,
    required this.sync,
    required this.fieldWork,
    required this.qa,
    required this.library,
    required this.reports,
    required this.demo,
    required this.safety,
    required this.voice,
    required this.speechProbe,
    required this.teluguModel,
    required this.maps,
    required this.teluguVoice,
    required this.alerts,
    required this.notifier,
    required this.h5Engine,
    this.h5Loader,
  });

  final AppSettings settings;
  final AppClock clock;
  final AppDatabase adb;
  final LocalStore store;
  final DataBus bus;
  final ApiClient api;
  final ConnectivityController connectivity;
  final SyncController sync;
  final FieldWorkService fieldWork;
  final QaService qa;
  final ProtocolLibrary library;
  final ReportService reports;
  final DemoData demo;
  final SafetyEngine safety;
  final VoiceInput voice;
  final SpeechCapabilityProbe speechProbe;

  /// The app's own offline Telugu speech model: downloaded once, then used with no internet.
  final TeluguModelStore teluguModel;

  /// The offline village map pack on this phone (works with no internet).
  final JsonPackMapSource maps;
  final VoiceInput teluguVoice;
  final UrgentAlerts alerts;
  final AlertNotifier notifier;

  /// For tests: replaces reading the Chandrapuri data from the app's own files.
  final Future<H5Data> Function()? h5Loader;

  /// The Chandrapuri block data (500 houses, 2,234 people, six village maps, the visit list). Read once, on first use, from files inside
  /// the app, so it works with no internet.
  late final Future<H5Data> h5 = h5Loader != null ? h5Loader!() : H5Data.load();

  /// The offline question-answering engine for the same protocols (danger signs, refusal, cited answers). Read once, on first use.
  final H5AssistantLoader h5Engine;

  static Future<AppServices> create({
    required SharedPreferences prefs,
    required SecretStore secrets,
    required AppDatabase adb,
    required String safetyRulesJson,
    http.Client? httpClient,
    ConnectivityController? connectivity,
    FileSharer? sharer,
    Future<String> Function()? demoLoader,
    Future<String> Function()? demoProtocolLoader,
    Future<String> Function()? aliasLoader,
    AppClock? clock,
    Future<Directory> Function()? tempDir,
    bool autoSync = true,
    VoiceInput? voice,
    SpeechCapabilityProbe? speechProbe,
    Future<Directory> Function()? modelDir,
    Future<String> Function()? mapPackLoader,
    Duration? explainTimeout,
    TeluguAsrEngine? teluguEngine,
    AlertNotifier? notifier,
    Future<H5Data> Function()? h5Loader,
    Future<H5Assistant> Function()? h5AssistantLoader,
    bool h5Ask = true,
  }) async {
    final clk = clock ?? AppClock();
    final settings = AppSettings(prefs, secrets, clk);
    await settings.load();
    final store = LocalStore(adb);
    final bus = DataBus();
    final api = ApiClient(
      client: httpClient ?? http.Client(),
      config: settings.apiConfig,
      log: kDebugMode ? (m) => debugPrint('[api] $m') : null,
    );
    final conn = connectivity ?? ConnectivityController();
    final teluguModel = TeluguModelStore(
      api: api,
      baseDir: modelDir ?? getApplicationSupportDirectory,
    );
    Future<String> installationId() async {
      var id = await store.meta('installation_id');
      if (id == null) {
        id = const Uuid().v4();
        await store.setMeta('installation_id', id);
      }
      return id;
    }

    final engine = SyncEngine(
      store: store,
      api: api,
      installationId: installationId,
      clock: clk,
      onChanged: bus.changed,
    );
    final sync = SyncController(
      engine,
      store,
      settings,
      conn,
      autoSync: autoSync,
    );
    final safety = SafetyEngine.fromJsonString(safetyRulesJson);
    final h5Engine = H5AssistantLoader(h5AssistantLoader ?? H5Assistant.load);
    final alertNotifier = notifier ?? FakeAlertNotifier(permission: false);
    final library = ProtocolLibrary(
      store,
      api,
      allowSamples: () => settings.useDemoDate,
      aliasLoader: aliasLoader,
    );
    final maps = JsonPackMapSource(
      baseDir: modelDir ?? getApplicationSupportDirectory,
      demoPack:
          mapPackLoader ??
          () => rootBundle.loadString('assets/demo/demo_village.json'),
    );
    final demoData = DemoData(
      store,
      loader: demoLoader,
      protocolLoader: demoProtocolLoader,
      installMap: maps.installDemoPack,
    );
    await demoData.refreshSampleIfStale();
    await demoData.ensureMap();
    return AppServices(
      settings: settings,
      clock: clk,
      adb: adb,
      store: store,
      bus: bus,
      api: api,
      connectivity: conn,
      sync: sync,
      fieldWork: FieldWorkService(
        store,
        clk,
        bus,
        onWrite: () {
          sync.refresh();
          sync.scheduleAutoSync();
        },
      ),
      qa: QaService(
        engine: safety,
        api: api,
        loadIndex: library.loadIndex,
        h5: h5Ask ? h5Engine.get : null,
        records: RecordAnswerer(store, clk),
        now: clk.nowUtc,
        language: () => settings.language,
        aiAssist: () => settings.aiAssist,
        explainTimeout: explainTimeout ?? QaService.defaultExplainTimeout,
      ),
      library: library,
      reports: ReportService(
        store,
        api,
        clk,
        sharer ?? PlatformFileSharer(),
        tempDir: tempDir,
      ),
      demo: demoData,
      safety: safety,
      voice: voice ?? PlatformVoiceInput(),
      speechProbe: speechProbe ?? PlatformSpeechProbe(),
      teluguModel: teluguModel,
      maps: maps,
      teluguVoice: TeluguVoiceInput(teluguModel, teluguEngine),
      notifier: alertNotifier,
      h5Loader: h5Loader,
      h5Engine: h5Engine,
      alerts: UrgentAlerts(
        notifier: alertNotifier,
        loadRanked: () => PriorityService(store).ranked(clk.today()),
        readNotified: () async => ((await store.meta('urgent_notified')) ?? '')
            .split(',')
            .where((e) => e.isNotEmpty)
            .toSet(),
        writeNotified: (ids) => store.setMeta('urgent_notified', ids.join(',')),
        language: () => settings.language,
        enabled: () => settings.alertsEnabled,
      ),
    );
  }

  void dispose() {
    sync.dispose();
    connectivity.dispose();
    api.close();
  }
}
