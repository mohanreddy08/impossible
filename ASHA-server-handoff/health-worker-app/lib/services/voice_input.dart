import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceProblem {
  permissionDenied,
  unavailable,
  languageMissing,
  noSpeech,
  network,
  other,
}

/// Speech-to-text for the question box. Uses the PHONE's own recognizer (Android SpeechRecognizer / iOS Speech):
/// no model is bundled in the app, audio is not stored by the app, and the phone's speech service may send audio to its
/// provider unless an offline language pack is installed (the UI says so). Recognised text only fills the text box:
/// the worker checks/edits it and presses Check, because recognition mistakes must never reach the safety check unseen.
abstract class VoiceInput {
  bool get isListening;

  /// [lang] is 'en' or 'te'. Calls [onText] with partial and final text; [onProblem] on failure; [onDone] when listening ends.
  Future<void> start({
    required String lang,
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceProblem p) onProblem,
    required void Function() onDone,
    bool offline = false,
    String? localeId,
  });
  Future<void> stop();
}

/// The phone's recogniser often ends a session with a second, EMPTY final result (after the real one). Passing that on would wipe the
/// words already shown, so an empty result never replaces text; a final empty result re-sends the best text of the session instead.
class VoiceResultGuard {
  String _best = '';
  void reset() => _best = '';

  /// The (text, isFinal) to show, or null when this result must be ignored.
  (String, bool)? accept(String words, bool isFinal) {
    final w = words.trim();
    if (w.isNotEmpty) {
      _best = w;
      return (w, isFinal);
    }
    return isFinal && _best.isNotEmpty ? (_best, true) : null;
  }
}

class PlatformVoiceInput implements VoiceInput {
  PlatformVoiceInput([SpeechToText? stt]) : _stt = stt ?? SpeechToText();
  final SpeechToText _stt;
  bool _ready = false;
  void Function(VoiceProblem)? _onProblem;
  void Function()? _onDone;
  final _guard = VoiceResultGuard();
  Future<void> Function()? _retryStart; // set for the first attempt of a start only

  @override
  bool get isListening => _stt.isListening;

  Future<bool> _init() async {
    if (_ready) return true;
    _ready = await _stt.initialize(
      onError: (SpeechRecognitionError e) {
        final id = e.errorMsg;
        debugPrint('[voice] error ${e.errorMsg} permanent=${e.permanent}'); // the error id only, never the words
        if (id == 'error_server_disconnected' && _retryStart != null) {
          // the speech service dropped the connection: the next listen gets a fresh recogniser (see third_party/speech_to_text), so
          // run the same start once more instead of showing an error
          final again = _retryStart!;
          _retryStart = null;
          Future<void>.delayed(const Duration(milliseconds: 400), again);
          return;
        }
        _onProblem?.call(
          id == 'error_permission'
              ? VoiceProblem.permissionDenied
              : id.contains('no_match') || id.contains('speech_timeout')
              ? VoiceProblem.noSpeech
              : id.contains('language')
              ? VoiceProblem.languageMissing
              : id.contains('network')
              ? VoiceProblem.network
              : VoiceProblem.other,
        );
      },
      onStatus: (s) {
        debugPrint('[voice] status $s');
        if (s == 'done' || s == 'notListening') _onDone?.call();
      },
    );
    return _ready;
  }

  /// Picks an installed locale for the language (prefers India variants). Null = that language is not installed.
  Future<String?> _locale(String lang, {bool offline = false}) async {
    final all = await _stt.locales();
    String norm(String s) => s.replaceAll('-', '_').toLowerCase();
    final want = lang == 'te'
        ? ['te_in', 'te']
        : offline
        ? [
            'en_us',
            'en_in',
            'en_gb',
            'en',
          ] // offline packs are usually installed for en-US
        : ['en_in', 'en_us', 'en_gb', 'en'];
    for (final w in want) {
      for (final l in all) {
        if (norm(l.localeId) == w) return l.localeId;
      }
    }
    for (final l in all) {
      if (norm(l.localeId).startsWith(lang)) return l.localeId;
    }
    // Some phones do not list every language they can recognise: try anyway and
    // let the recogniser answer (a language error becomes languageMissing).
    return lang == 'te' ? 'te-IN' : 'en-IN';
  }

  @override
  Future<void> start({
    required String lang,
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceProblem p) onProblem,
    required void Function() onDone,
    bool offline = false,
    String? localeId,
  }) => _begin(lang, onText, onProblem, onDone, offline, localeId, retry: true);

  Future<void> _begin(
    String lang,
    void Function(String text, bool isFinal) onText,
    void Function(VoiceProblem p) onProblem,
    void Function() onDone,
    bool offline,
    String? localeId, {
    required bool retry,
  }) async {
    _onProblem = onProblem;
    _onDone = onDone;
    _guard.reset();
    // one automatic second attempt if the speech service connection was dropped (see the error handler)
    _retryStart = retry
        ? () => _begin(lang, onText, onProblem, onDone, offline, localeId, retry: false)
        : null;
    if (!await _init()) {
      onProblem(
        await _stt.hasPermission
            ? VoiceProblem.unavailable
            : VoiceProblem.permissionDenied,
      );
      onDone();
      return;
    }
    final id = localeId ?? await _locale(lang, offline: offline);
    if (id == null) {
      onProblem(VoiceProblem.languageMissing);
      onDone();
      return;
    }
    await _stt.listen(
      onResult: (r) {
        final out = _guard.accept(r.recognizedWords, r.finalResult);
        if (out != null) onText(out.$1, out.$2);
      },
      listenOptions: SpeechListenOptions(
        localeId: id,
        onDevice: offline,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();
}

/// For tests and builds without speech support.
class NoVoiceInput implements VoiceInput {
  @override
  bool get isListening => false;
  @override
  Future<void> start({
    required String lang,
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceProblem p) onProblem,
    required void Function() onDone,
    bool offline = false,
    String? localeId,
  }) async {
    onProblem(VoiceProblem.unavailable);
    onDone();
  }

  @override
  Future<void> stop() async {}
}
