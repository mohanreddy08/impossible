import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api/api_exceptions.dart';
import '../data/local/local_store.dart';
import '../services/settings.dart';
import '../services/sync_engine.dart';
import 'connectivity_controller.dart';

enum ServerLink { unknown, reachable, unreachable, authFailed, notConfigured }

class SyncController extends ChangeNotifier {
  SyncController(
    this.engine,
    this.store,
    this.settings,
    this.connectivity, {
    this.autoSync = true,
    this.autoSyncDelay = const Duration(seconds: 2),
  }) {
    _regainedSub = connectivity.onRegained.listen((_) => scheduleAutoSync());
  }
  final SyncEngine engine;
  final LocalStore store;
  final AppSettings settings;
  final ConnectivityController connectivity;
  final bool autoSync;
  final Duration autoSyncDelay;
  late final StreamSubscription<void> _regainedSub;
  Timer? _debounce;

  OutboxCounts counts = const OutboxCounts();
  String? lastSyncAt;
  bool syncing = false;
  SyncReport? lastReport;
  ServerLink link = ServerLink.unknown;
  bool _disposed = false;

  Future<void> refresh() async {
    counts = await store.outboxCounts();
    lastSyncAt = await store.meta('last_sync_at');
    if (!_disposed) notifyListeners();
  }

  Future<SyncReport> syncNow({bool pull = true}) async {
    if (syncing) return SyncReport()..alreadyRunning = true;
    syncing = true;
    if (!_disposed) notifyListeners();
    SyncReport rep;
    try {
      rep = await engine.syncNow(pull: pull);
    } on ApiException catch (_) {
      rep = SyncReport();
    }
    lastReport = rep;
    link = rep.notConfigured
        ? ServerLink.notConfigured
        : rep.authFailed
        ? ServerLink.authFailed
        : rep.offline
        ? ServerLink.unreachable
        : rep.error != null
        ? ServerLink.unreachable
        : ServerLink.reachable;
    syncing = false;
    await refresh();
    return rep;
  }

  /// Opportunistic upload after a local save / reconnect / app resume. It only ever SENDS; nothing is assumed to have succeeded.
  void scheduleAutoSync() {
    if (!autoSync ||
        _disposed ||
        !connectivity.online ||
        settings.baseUrl.isEmpty) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(autoSyncDelay, () {
      if (!_disposed) syncNow(pull: false);
    });
  }

  /// Drops a scheduled (not yet started) automatic upload. Called when the app root is disposed.
  void cancelScheduled() => _debounce?.cancel();

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _regainedSub.cancel();
    super.dispose();
  }
}
