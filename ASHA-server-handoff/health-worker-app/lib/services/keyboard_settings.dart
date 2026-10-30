import 'package:flutter/services.dart';

/// Opens the phone's own keyboard settings (Android). Returns false when the phone cannot open it, so the screen can say so.
/// Replaceable in tests.
class KeyboardSettings {
  static const _ch = MethodChannel('asha/speech');
  static Future<bool> Function() open = () async {
    try {
      return (await _ch.invokeMethod<bool>('openKeyboardSettings')) ?? false;
    } on Object {
      return false;
    }
  };
}
