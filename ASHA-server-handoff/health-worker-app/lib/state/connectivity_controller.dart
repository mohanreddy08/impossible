import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the phone has ANY network interface. This is only a hint: real reachability is decided by an actual request
/// (the sync engine), because "connected to Wi-Fi with no internet" and 2G with no data both look "online" here.
class ConnectivityController extends ChangeNotifier {
  ConnectivityController({
    Stream<List<ConnectivityResult>>? stream,
    Future<List<ConnectivityResult>> Function()? initial,
  }) {
    final s = stream ?? Connectivity().onConnectivityChanged;
    (initial ?? Connectivity().checkConnectivity)()
        .then(_set)
        .catchError((_) {});
    _sub = s.listen(_set);
  }
  late final StreamSubscription<List<ConnectivityResult>> _sub;
  bool _online = true;
  bool get online => _online;
  final _regained = StreamController<void>.broadcast();
  Stream<void> get onRegained => _regained.stream;

  void _set(List<ConnectivityResult> r) {
    final now = r.any((e) => e != ConnectivityResult.none);
    if (now != _online) {
      _online = now;
      notifyListeners();
      if (now) _regained.add(null);
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _regained.close();
    super.dispose();
  }
}
