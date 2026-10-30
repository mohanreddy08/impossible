import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../data/api/api_client.dart';
import 'voice_input.dart';

/// Offline Telugu speech recognition with the app's OWN model (Whisper-tiny fine-tuned for Telugu, int8, about 44 MB), for phones whose
/// speech service has no Telugu offline pack. The model is downloaded ONCE from the project's server, checked against its SHA-256, and
/// then recognition runs entirely on the phone: no internet, nothing uploaded, audio only held in memory (see WhisperAsr.kt).

enum ModelStage { notInstalled, downloading, installed }

class ModelProgress {
  const ModelProgress(this.doneBytes, this.totalBytes);
  final int doneBytes, totalBytes;
  double get fraction => totalBytes == 0 ? 0 : doneBytes / totalBytes;
}

class ModelDownloadFailed implements Exception {
  const ModelDownloadFailed(this.reason);
  final String reason; // 'checksum' | 'incomplete'
}

/// Where the model files live and how they get there. The folder holds the verified files plus "ready.json"; the model counts as
/// installed only when every file is present and ready.json says it was verified (an interrupted download is never used).
class TeluguModelStore {
  TeluguModelStore({
    required this.api,
    required Future<Directory> Function() baseDir,
  }) : _base = baseDir;
  final ApiClient api;
  final Future<Directory> Function() _base;
  static const files = ['encoder.int8.onnx', 'decoder.int8.onnx', 'tokens.txt'];

  Future<Directory> dir() async {
    final d = Directory(
      '${(await _base()).path}${Platform.pathSeparator}te-asr',
    );
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<bool> isInstalled() async {
    final d = await dir();
    final ready = File('${d.path}/ready.json');
    if (!ready.existsSync()) return false;
    return files.every((n) => File('${d.path}/$n').existsSync());
  }

  Future<int> installedBytes() async {
    final d = await dir();
    var n = 0;
    for (final f in files) {
      final x = File('${d.path}/$f');
      if (x.existsSync()) n += x.lengthSync();
    }
    return n;
  }

  /// One-time download. Resumes a partial download, verifies each file's SHA-256, then marks the model ready.
  /// Throws ApiException (no network, not allowed, not on the server) or [ModelDownloadFailed].
  Future<void> download({void Function(ModelProgress)? onProgress}) async {
    final d = await dir();
    final ready = File('${d.path}/ready.json');
    if (ready.existsSync()) ready.deleteSync();
    final m = await api.speechModelManifest();
    final want = {
      for (final f in (m['files'] as List).cast<Map<String, dynamic>>())
        f['name'] as String: f,
    };
    if (!files.every(want.containsKey)) {
      throw const ModelDownloadFailed('incomplete');
    }
    final total = [for (final n in files) want[n]!['size'] as int]
        .fold<int>(0, (a, b) => a + b);
    var done = 0;
    for (final n in files) {
      final f = want[n]!;
      final size = f['size'] as int;
      final sha = f['sha256'] as String;
      final fin = File('${d.path}/$n');
      final part = File('${d.path}/$n.part');
      if (fin.existsSync() &&
          fin.lengthSync() == size &&
          await _sha(fin) == sha) {
        done += size; // already here and verified
        onProgress?.call(ModelProgress(done, total));
        continue;
      }
      if (part.existsSync() && part.lengthSync() > size) part.deleteSync();
      if (!part.existsSync() || part.lengthSync() < size) {
        await api.downloadFile(
          f['url'] as String,
          part,
          onBytes: (b) => onProgress?.call(ModelProgress(done + b, total)),
        );
      }
      if (part.lengthSync() != size) {
        // kept, so a retry resumes
        throw const ModelDownloadFailed('incomplete');
      }
      if (await _sha(part) != sha) {
        part.deleteSync();
        throw const ModelDownloadFailed('checksum');
      }
      if (fin.existsSync()) fin.deleteSync();
      part.renameSync(fin.path);
      done += size;
      onProgress?.call(ModelProgress(done, total));
    }
    ready.writeAsStringSync(
      jsonEncode({
        'id': m['id'],
        'files': [
          for (final n in files) {'name': n, 'sha256': want[n]!['sha256']},
        ],
      }),
    );
  }

  Future<String> _sha(File f) async =>
      (await sha256.bind(f.openRead()).first).toString();

  /// Frees the space (about 44 MB). Telugu voice then needs the pack again (or online speech).
  Future<void> delete() async {
    final d = await dir();
    for (final e in d.listSync()) {
      if (e is File) e.deleteSync();
    }
  }
}

/// The native side (WhisperAsr.kt) behind a small interface so tests can use a fake.
abstract class TeluguAsrEngine {
  /// 'ok' | 'permission' | 'granted' (mic was just allowed: call again) | 'mic_unavailable'
  Future<String> start();
  /// Stops the microphone and returns the recognised text (empty when nothing was said).
  Future<String> stop(String dir);
  Future<void> cancel();
}

class NativeTeluguAsrEngine implements TeluguAsrEngine {
  static const _ch = MethodChannel('asha/te_asr');
  @override
  Future<String> start() async =>
      (await _ch.invokeMethod<String>('start', {'dir': ''})) ??
      'mic_unavailable';
  @override
  Future<String> stop(String dir) async =>
      (await _ch.invokeMethod<String>('stop', {'dir': dir})) ?? '';
  /// Recognises a recorded 16 kHz mono 16-bit WAV with the installed model (Voice Test only): the text and the milliseconds it took.
  static Future<({String text, int ms})> recogniseWav(String dir, String wav) async {
    final m = await _ch.invokeMapMethod<String, Object?>('recogniseWav', {'dir': dir, 'wav': wav}) ?? const {};
    return (text: (m['text'] as String?) ?? '', ms: (m['ms'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<void> cancel() async {
    try {
      await _ch.invokeMethod<void>('cancel', {'dir': ''});
    } on Object {
      /* nothing to cancel */
    }
  }
}

/// [VoiceInput] over the app's own Telugu model. Not streaming: the worker speaks, taps stop, and the text appears a moment later.
/// Like every voice path, the text only fills the question box: the worker checks it and presses Check.
class TeluguVoiceInput implements VoiceInput {
  TeluguVoiceInput(this.store, [TeluguAsrEngine? engine])
    : _engine = engine ?? NativeTeluguAsrEngine();
  final TeluguModelStore store;
  final TeluguAsrEngine _engine;
  static const maxSeconds = 30;
  bool _listening = false;
  Timer? _cap;
  void Function(String, bool)? _onText;
  void Function(VoiceProblem)? _onProblem;
  void Function()? _onDone;

  @override
  bool get isListening => _listening;

  @override
  Future<void> start({
    required String lang,
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceProblem p) onProblem,
    required void Function() onDone,
    bool offline = false,
    String? localeId,
  }) async {
    _onText = onText;
    _onProblem = onProblem;
    _onDone = onDone;
    if (!await store.isInstalled()) {
      onProblem(VoiceProblem.languageMissing);
      onDone();
      return;
    }
    var r = await _engine.start();
    if (r == 'granted') r = await _engine.start();
    if (r != 'ok') {
      onProblem(
        r == 'mic_unavailable'
            ? VoiceProblem.unavailable
            : VoiceProblem.permissionDenied,
      );
      onDone();
      return;
    }
    _listening = true;
    _cap = Timer(const Duration(seconds: maxSeconds), stop);
  }

  @override
  Future<void> stop() async {
    _cap?.cancel();
    if (!_listening) return;
    _listening = false;
    try {
      final d = await store.dir();
      final text = (await _engine.stop(d.path)).trim();
      if (text.isEmpty) {
        _onProblem?.call(VoiceProblem.noSpeech);
      } else {
        _onText?.call(text, true);
      }
    } on Object {
      _onProblem?.call(VoiceProblem.other);
    } finally {
      _onDone?.call();
    }
  }
}
