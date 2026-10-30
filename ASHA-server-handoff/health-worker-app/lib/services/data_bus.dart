import 'package:flutter/foundation.dart';

/// Tick that screens listen to; fired after any local write or sync so lists re-query SQLite.
class DataBus extends ChangeNotifier {
  int version = 0;
  void changed() {
    version++;
    notifyListeners();
  }
}
