import 'package:flutter/foundation.dart';

/// The hidden Voice Test screen exists only in debug builds, or in a release build made with `--dart-define=VOICE_TEST=true`
/// (a release build keeps the same version code, so adb can install it over the phone's app without wiping its data).
bool get voiceTestEnabled =>
    kDebugMode || const bool.fromEnvironment('VOICE_TEST');
