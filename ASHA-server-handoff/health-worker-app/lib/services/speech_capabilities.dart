import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// What the phone's speech service can do, as reported by the OS (see MainActivity.kt). Nothing here is assumed.
class SpeechCapabilities {
  const SpeechCapabilities({
    required this.recognitionAvailable,
    required this.onDeviceAvailable,
    this.installed,
    this.supportedOnDevice,
    this.sdk,
  });

  /// Any recogniser at all (it may send audio to its provider).
  final bool recognitionAvailable;

  /// An on-device recogniser exists (Android 12+): only then can the app guarantee audio stays on the phone.
  final bool onDeviceAvailable;

  /// Languages whose offline model is downloaded (Android 13+), e.g. ['en-US', 'te-IN']. Null = the OS cannot say.
  final List<String>? installed;

  /// Languages the on-device recogniser could download. Null = unknown.
  final List<String>? supportedOnDevice;
  final int? sdk;

  static const none = SpeechCapabilities(
    recognitionAvailable: false,
    onDeviceAvailable: false,
  );

  factory SpeechCapabilities.fromMap(Map<dynamic, dynamic> m) {
    List<String>? list(Object? v) =>
        v is List ? [for (final e in v) e.toString()] : null;
    return SpeechCapabilities(
      recognitionAvailable: m['recognitionAvailable'] == true,
      onDeviceAvailable: m['onDeviceAvailable'] == true,
      installed: list(m['installed']),
      supportedOnDevice: list(m['supportedOnDevice']),
      sdk: m['sdk'] is int ? m['sdk'] as int : null,
    );
  }

  /// The installed locale for [lang] ('en' / 'te'), preferring the Indian variant. Null when not installed (or unknown).
  String? installedLocale(String lang) => _pick(installed, lang);
  bool canDownload(String lang) => _pick(supportedOnDevice, lang) != null;

  static String? _pick(List<String>? from, String lang) {
    if (from == null) return null;
    final hits = [
      for (final l in from)
        if (l.toLowerCase().replaceAll('_', '-').split('-').first == lang) l,
    ];
    if (hits.isEmpty) return null;
    return hits.firstWhere(
      (l) => l.toLowerCase().replaceAll('_', '-').endsWith('-in'),
      orElse: () => hits.first,
    );
  }
}

abstract class SpeechCapabilityProbe {
  Future<SpeechCapabilities> check();
}

/// Android: asks the OS through the 'asha/speech' channel. Other platforms: reports that on-device recognition cannot be
/// guaranteed (iOS support was not built or tested here).
class PlatformSpeechProbe implements SpeechCapabilityProbe {
  static const _ch = MethodChannel('asha/speech');
  @override
  Future<SpeechCapabilities> check() async {
    if (!Platform.isAndroid) {
      return const SpeechCapabilities(
        recognitionAvailable: true,
        onDeviceAvailable: false,
      );
    }
    try {
      final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('capabilities');
      return m == null
          ? SpeechCapabilities.none
          : SpeechCapabilities.fromMap(m);
    } on Object {
      return SpeechCapabilities.none;
    }
  }
}

/// Tests and demos: a fixed answer.
class FixedSpeechProbe implements SpeechCapabilityProbe {
  const FixedSpeechProbe(this.caps);
  final SpeechCapabilities caps;

  /// On-device recogniser with English and Telugu offline packs installed.
  static const allOffline = FixedSpeechProbe(
    SpeechCapabilities(
      recognitionAvailable: true,
      onDeviceAvailable: true,
      installed: ['en-IN', 'te-IN'],
      supportedOnDevice: ['en-IN', 'te-IN'],
      sdk: 34,
    ),
  );
  @override
  Future<SpeechCapabilities> check() async => caps;
}

enum VoiceRoute { onDevice, appModel, online, blocked }

enum VoiceBlock {
  /// The phone has no speech recogniser at all.
  noRecognizer,

  /// No offline pack for this language; the OS says one can be downloaded in the phone's speech settings.
  packMissing,

  /// The phone cannot recognise this language on the device (no on-device engine, or the language is not offered).
  noOfflineEngine,
}

class VoiceDecision {
  const VoiceDecision.onDevice(this.locale)
    : route = VoiceRoute.onDevice,
      block = null,
      onlineWouldWork = false;

  /// The app's own offline model (downloaded once). Works with no internet and nothing leaves the phone.
  const VoiceDecision.appModel()
    : route = VoiceRoute.appModel,
      locale = null,
      block = null,
      onlineWouldWork = false;
  const VoiceDecision.online()
    : route = VoiceRoute.online,
      locale = null,
      block = null,
      onlineWouldWork = true;
  const VoiceDecision.blocked(this.block, {this.onlineWouldWork = false})
    : route = VoiceRoute.blocked,
      locale = null;
  final VoiceRoute route;
  final String? locale;
  final VoiceBlock? block;

  /// Blocked only because online speech is switched off (the worker can choose to allow it in Settings).
  final bool onlineWouldWork;
}

/// The voice policy, kept pure so it can be tested:
///  1. If the phone can recognise [lang] ON THE DEVICE, use that (nothing leaves the phone, works with no internet).
///  2. Otherwise, if the app's own offline model for [lang] is installed ([appModelReady]), use that: same guarantees.
///  3. Otherwise use the phone's online speech service ONLY if the worker switched "online speech" on and there is a connection.
///  4. Otherwise do not listen; say why. Typing always works. There is never a silent fallback to a cloud service.
VoiceDecision decideVoiceRoute(
  SpeechCapabilities c, {
  required String lang,
  required bool allowOnline,
  required bool online,
  bool appModelReady = false,
}) {
  final installedLoc = c.onDeviceAvailable ? c.installedLocale(lang) : null;
  if (installedLoc != null) return VoiceDecision.onDevice(installedLoc);
  if (appModelReady) return const VoiceDecision.appModel();
  if (!c.recognitionAvailable && !c.onDeviceAvailable) {
    return const VoiceDecision.blocked(VoiceBlock.noRecognizer);
  }
  if (c.onDeviceAvailable) {
    if (c.installed == null) {
      // Android 12: an on-device engine exists but cannot list its languages. Trying it is still local-only; if the language is
      // missing the recogniser reports a language error, which is shown as such.
      return VoiceDecision.onDevice(lang == 'te' ? 'te-IN' : 'en-IN');
    }
  }
  final onlineOk = c.recognitionAvailable && online;
  if (allowOnline && onlineOk) return const VoiceDecision.online();
  final block = c.onDeviceAvailable && c.canDownload(lang)
      ? VoiceBlock.packMissing
      : VoiceBlock.noOfflineEngine;
  return VoiceDecision.blocked(
    block,
    onlineWouldWork: onlineOk && !allowOnline,
  );
}
