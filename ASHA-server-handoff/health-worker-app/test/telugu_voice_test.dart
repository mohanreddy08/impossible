import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/data/api/api_client.dart';
import 'package:health_companion/presentation/screens/ask_screen.dart';
import 'package:health_companion/presentation/screens/settings_screen.dart';
import 'package:health_companion/services/speech_capabilities.dart';
import 'package:health_companion/services/telugu_voice.dart';
import 'package:health_companion/services/voice_input.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'support/fake_server.dart';
import 'voice_test.dart' show fieldText;

// Offline Telugu speech with the app's own model (Whisper-tiny Telugu): the one-time download, the voice
// input, the routing policy, and the Ask / Settings screens.

const _sample = 'గర్భిణీకి ఫిట్స్ వచ్చాయి';

/// A phone whose speech service has English offline but no Telugu pack.
const _englishOnly = FixedSpeechProbe(
  SpeechCapabilities(
    recognitionAvailable: true,
    onDeviceAvailable: true,
    installed: ['en-US'],
    supportedOnDevice: ['en-US'],
    sdk: 34,
  ),
);

class FakeEngine implements TeluguAsrEngine {
  List<String> startReplies = ['ok'];
  String text = _sample;
  int starts = 0, stops = 0, cancels = 0;
  @override
  Future<String> start() async {
    final i = starts++;
    return startReplies[i < startReplies.length ? i : startReplies.length - 1];
  }

  @override
  Future<String> stop(String dir) async {
    stops++;
    return text;
  }

  @override
  Future<void> cancel() async => cancels++;
}

Map<String, List<int>> _pack() => {
  'decoder.int8.onnx': List<int>.generate(3000, (i) => i % 251),
  'encoder.int8.onnx': List<int>.generate(900, (i) => (i * 7) % 256),
  'tokens.txt': utf8.encode('IQ== 0\nIg== 1\n'),
};

Future<void> _install(Directory base) async {
  final d = Directory('${base.path}/te-asr')..createSync(recursive: true);
  _pack().forEach((n, b) => File('${d.path}/$n').writeAsBytesSync(b));
  File('${d.path}/ready.json').writeAsStringSync('{}');
}

TeluguModelStore _store(FakeServer srv, Directory base) => TeluguModelStore(
  api: ApiClient(
    client: srv.client(),
    config: () async => const ApiConfig('http://fake.local', 'k'),
  ),
  baseDir: () async => base,
);

void main() {
  sqfliteFfiInit();

  group('one-time download', () {
    late Directory base;
    setUp(() => base = Directory.systemTemp.createTempSync('te_model_'));
    tearDown(() => base.deleteSync(recursive: true));

    test(
      'downloads every file, checks SHA-256, then reports installed',
      () async {
        final srv = FakeServer()..speechFiles.addAll(_pack());
        final st = _store(srv, base);
        expect(await st.isInstalled(), isFalse);
        final seen = <double>[];
        await st.download(onProgress: (p) => seen.add(p.fraction));
        expect(await st.isInstalled(), isTrue);
        expect(seen.last, 1.0);
        expect(
          seen,
          orderedEquals([...seen]..sort()),
          reason: 'progress never goes backwards',
        );
        final d = await st.dir();
        for (final e in _pack().entries) {
          expect(File('${d.path}/${e.key}').readAsBytesSync(), e.value);
        }
      },
    );

    test('an interrupted download continues where it stopped (HTTP Range) and is still verified', () async {
      final srv = FakeServer()..speechFiles.addAll(_pack());
      final st = _store(srv, base);
      final d = await st.dir();
      File('${d.path}/decoder.int8.onnx.part')
          .writeAsBytesSync(_pack()['decoder.int8.onnx']!.sublist(0, 1200));
      await st.download();
      expect(srv.speechRanges, contains('bytes=1200-'));
      expect(await st.isInstalled(), isTrue);
      expect(
        File('${d.path}/decoder.int8.onnx').readAsBytesSync(),
        _pack()['decoder.int8.onnx'],
      );
    });

    test(
      'a damaged file is discarded and the model is NOT marked installed',
      () async {
        final srv = FakeServer()
          ..speechFiles.addAll(_pack())
          ..speechShaOverride = 'f' * 64;
        final st = _store(srv, base);
        await expectLater(
          st.download(),
          throwsA(
            isA<ModelDownloadFailed>().having(
              (e) => e.reason,
              'reason',
              'checksum',
            ),
          ),
        );
        expect(await st.isInstalled(), isFalse);
        final d = await st.dir();
        expect(File('${d.path}/decoder.int8.onnx.part').existsSync(), isFalse);
      },
    );

    test(
      'server without a pack, or no network: clear failure, nothing installed',
      () async {
        final none = FakeServer();
        await expectLater(_store(none, base).download(), throwsA(anything));
        final down = FakeServer()
          ..speechFiles.addAll(_pack())
          ..down = true;
        await expectLater(_store(down, base).download(), throwsA(anything));
        expect(await _store(none, base).isInstalled(), isFalse);
      },
    );

    test(
      'a half-finished install is never used; delete frees the space',
      () async {
        final srv = FakeServer()..speechFiles.addAll(_pack());
        final st = _store(srv, base);
        await _install(base);
        expect(await st.isInstalled(), isTrue);
        File('${(await st.dir()).path}/ready.json').deleteSync();
        expect(
          await st.isInstalled(),
          isFalse,
          reason: 'files without the verified marker do not count',
        );
        await _install(base);
        await st.delete();
        expect(await st.isInstalled(), isFalse);
        expect(await st.installedBytes(), 0);
      },
    );
  });

  group('voice input over the app model', () {
    late Directory base;
    setUp(() => base = Directory.systemTemp.createTempSync('te_voice_'));
    tearDown(() => base.deleteSync(recursive: true));

    test('speak, stop -> Telugu text delivered once; nothing is submitted by itself', () async {
      await _install(base);
      final eng = FakeEngine();
      final v = TeluguVoiceInput(_store(FakeServer(), base), eng);
      final texts = <String>[];
      var done = 0;
      await v.start(
        lang: 'te',
        onText: (t, f) => texts.add(t),
        onProblem: (p) => fail('$p'),
        onDone: () => done++,
      );
      expect(v.isListening, isTrue);
      await v.stop();
      expect(v.isListening, isFalse);
      expect(texts, [_sample]);
      expect(done, 1);
    });

    test('first use: the microphone question is asked, and listening starts after "allow"', () async {
      await _install(base);
      final eng = FakeEngine()..startReplies = ['granted', 'ok'];
      final v = TeluguVoiceInput(_store(FakeServer(), base), eng);
      await v.start(
        lang: 'te',
        onText: (_, _) {},
        onProblem: (p) => fail('$p'),
        onDone: () {},
      );
      expect(eng.starts, 2);
      expect(v.isListening, isTrue);
    });

    test('microphone refused / not installed / silence are reported, never a made-up sentence', () async {
      final problems = <VoiceProblem>[];
      // not installed
      var v = TeluguVoiceInput(_store(FakeServer(), base), FakeEngine());
      await v.start(
        lang: 'te',
        onText: (_, _) => fail('text'),
        onProblem: problems.add,
        onDone: () {},
      );
      expect(problems.removeLast(), VoiceProblem.languageMissing);
      await _install(base);
      // permission refused
      v = TeluguVoiceInput(
        _store(FakeServer(), base),
        FakeEngine()..startReplies = ['permission'],
      );
      await v.start(
        lang: 'te',
        onText: (_, _) => fail('text'),
        onProblem: problems.add,
        onDone: () {},
      );
      expect(problems.removeLast(), VoiceProblem.permissionDenied);
      // only silence (all blanks)
      v = TeluguVoiceInput(
        _store(FakeServer(), base),
        FakeEngine()..text = '',
      );
      await v.start(
        lang: 'te',
        onText: (_, _) => fail('text'),
        onProblem: problems.add,
        onDone: () {},
      );
      await v.stop();
      expect(problems.removeLast(), VoiceProblem.noSpeech);
    });
  });

  group('routing policy', () {
    test('the OS pack wins; else the app model; else online only with consent; else blocked', () {
      const noTe = _TeCaps.englishOnly;
      expect(
        decideVoiceRoute(
          noTe,
          lang: 'te',
          allowOnline: true,
          online: true,
          appModelReady: true,
        ).route,
        VoiceRoute.appModel,
        reason: 'even with online speech allowed, nothing leaves the phone when the app model can do it',
      );
      expect(
        decideVoiceRoute(
          noTe,
          lang: 'te',
          allowOnline: false,
          online: false,
          appModelReady: true,
        ).route,
        VoiceRoute.appModel,
        reason: 'and it works with no internet',
      );
      expect(
        decideVoiceRoute(
          noTe,
          lang: 'te',
          allowOnline: false,
          online: true,
        ).route,
        VoiceRoute.blocked,
      );
      expect(
        decideVoiceRoute(
          FixedSpeechProbe.allOffline.caps,
          lang: 'te',
          allowOnline: false,
          online: false,
          appModelReady: true,
        ).route,
        VoiceRoute.onDevice,
        reason: 'a pack the phone already has is used first',
      );
      expect(
        decideVoiceRoute(
          SpeechCapabilities.none,
          lang: 'te',
          allowOnline: false,
          online: false,
          appModelReady: true,
        ).route,
        VoiceRoute.appModel,
        reason: 'the app model does not need the phone speech service at all',
      );
    });
  });

  group('screens', () {
    uiTest(
      'Ask, Telugu, no Telugu pack on the phone, app model installed: listens and recognises on the phone',
      (t) async {
        final base = Directory.systemTemp.createTempSync('te_ui_');
        addTearDown(() => base.deleteSync(recursive: true));
        await _install(base);
        final eng = FakeEngine();
        final rig = (await t.runAsync(
          () => buildRig(
            configured: false,
            speechProbe: _englishOnly,
            teluguEngine: eng,
            modelDir: base,
            lang: 'te',
          ),
        ))!;
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 1600),
        );
        await t.tap(find.byKey(const Key('mic-button')));
        await settle(t, maxRounds: 8);
        expect(eng.starts, 1, reason: 'recognition started with the app model');
        await t.tap(find.byKey(const Key('mic-button'))); // stop
        await settle(t, maxRounds: 12);
        expect(eng.stops, 1);
        expect(fieldText(t), _sample);
        expect(
          find.textContaining('app\'s own Telugu model'),
          findsNothing,
          reason: 'the line is shown in Telugu on a Telugu screen',
        );
        expect(find.byKey(const Key('voice-privacy')), findsOneWidget);
        expect(
          find.text('Possible danger sign'),
          findsNothing,
          reason: 'recognised text is only put in the box; the worker presses Check',
        );
      },
    );

    uiTest(
      'Ask, Telugu, no pack and no app model: says what to do, including the Settings download',
      (t) async {
        final rig = (await t.runAsync(
          () => buildRig(
            configured: false,
            speechProbe: _englishOnly,
            voice: FakeVoiceForTe(),
            lang: 'en',
          ),
        ))!;
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 1600),
        );
        await t.tap(find.byKey(const Key('voice-lang-te')));
        await t.pump();
        await t.tap(find.byKey(const Key('mic-button')));
        await settle(t, maxRounds: 6);
        expect(
          find.textContaining(
            'download the Telugu voice pack once in Settings',
          ),
          findsOneWidget,
        );
      },
    );

    uiTest(
      'Settings: download button -> progress -> ready; remove puts it back',
      (t) async {
        final base = Directory.systemTemp.createTempSync('te_set_');
        addTearDown(() => base.deleteSync(recursive: true));
        final srv = FakeServer()..speechFiles.addAll(_pack());
        final rig = (await t.runAsync(
          () => buildRig(server: srv, modelDir: base),
        ))!;
        await pumpApp(
          t,
          rig,
          home: const SettingsScreen(),
          size: const Size(412, 3200),
        );
        await settle(t, maxRounds: 6);
        await t.ensureVisible(find.byKey(const Key('telugu-model-download')));
        expect(
          srv.speechFileCalls,
          0,
          reason: 'nothing downloads until the worker taps the button',
        );
        await t.tap(find.byKey(const Key('telugu-model-download')));
        await settle(
          t,
          until: () =>
              find.byKey(const Key('telugu-model-ready')).evaluate().isNotEmpty,
          maxRounds: 60,
        );
        expect(find.byKey(const Key('telugu-model-ready')), findsOneWidget);
        expect(srv.speechFileCalls, 3);
        await t.tap(find.byKey(const Key('telugu-model-remove')));
        await settle(t, maxRounds: 10);
        expect(find.byKey(const Key('telugu-model-download')), findsOneWidget);
      },
    );

    uiTest('Settings: damaged download and missing pack show a plain message', (
      t,
    ) async {
      final base = Directory.systemTemp.createTempSync('te_set2_');
      addTearDown(() => base.deleteSync(recursive: true));
      final srv = FakeServer()
        ..speechFiles.addAll(_pack())
        ..speechShaOverride = 'a' * 64;
      final rig = (await t.runAsync(
        () => buildRig(server: srv, modelDir: base),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const SettingsScreen(),
        size: const Size(412, 3200),
      );
      await settle(t, maxRounds: 6);
      await t.ensureVisible(find.byKey(const Key('telugu-model-download')));
      await t.tap(find.byKey(const Key('telugu-model-download')));
      await settle(
        t,
        until: () =>
            find.byKey(const Key('telugu-model-error')).evaluate().isNotEmpty,
        maxRounds: 60,
      );
      expect(find.textContaining('damaged'), findsOneWidget);
      srv.speechFiles.clear();
      await t.tap(find.byKey(const Key('telugu-model-download')));
      await settle(
        t,
        until: () =>
            find.textContaining('no Telugu voice pack').evaluate().isNotEmpty,
        maxRounds: 60,
      );
      expect(find.textContaining('no Telugu voice pack'), findsOneWidget);
    });

    uiTest(
      'Settings without a server address asks for it first and downloads nothing',
      (t) async {
        final base = Directory.systemTemp.createTempSync('te_set3_');
        addTearDown(() => base.deleteSync(recursive: true));
        final srv = FakeServer()..speechFiles.addAll(_pack());
        final rig = (await t.runAsync(
          () => buildRig(server: srv, configured: false, modelDir: base),
        ))!;
        await pumpApp(
          t,
          rig,
          home: const SettingsScreen(),
          size: const Size(412, 3200),
        );
        await settle(t, maxRounds: 6);
        await t.ensureVisible(find.byKey(const Key('telugu-model-download')));
        await t.tap(find.byKey(const Key('telugu-model-download')));
        await settle(t, maxRounds: 10);
        expect(find.textContaining('Set the server address'), findsOneWidget);
        expect(srv.speechFileCalls, 0);
      },
    );
  });
}

class _TeCaps {
  static const englishOnly = SpeechCapabilities(
    recognitionAvailable: true,
    onDeviceAvailable: true,
    installed: ['en-US'],
    supportedOnDevice: ['en-US', 'te-IN'],
    sdk: 34,
  );
}

class FakeVoiceForTe implements VoiceInput {
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
  }) async => fail('must not listen: no offline Telugu is available');
  @override
  Future<void> stop() async {}
}
