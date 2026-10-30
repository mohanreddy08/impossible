import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/presentation/screens/ask_screen.dart';
import 'package:health_companion/services/voice_input.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

class FakeVoice implements VoiceInput {
  String? lang, localeId;
  bool? offline;
  int starts = 0;
  VoiceProblem? problem;
  void Function(String, bool)? _onText;
  void Function()? _onDone;
  bool _on = false;
  int stops = 0;
  @override
  bool get isListening => _on;
  @override
  Future<void> start({
    required String lang,
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceProblem p) onProblem,
    required void Function() onDone,
    bool offline = false,
    String? localeId,
  }) async {
    this.lang = lang;
    this.offline = offline;
    this.localeId = localeId;
    starts++;
    if (problem != null) {
      onProblem(problem!);
      onDone();
      return;
    }
    _on = true;
    _onText = onText;
    _onDone = onDone;
  }

  void say(String t, {bool fin = false}) => _onText!(t, fin);
  void finish() {
    _on = false;
    _onDone!();
  }

  @override
  Future<void> stop() async {
    stops++;
    if (_on) finish();
  }
}

String fieldText(WidgetTester t) => t
    .widget<TextField>(find.byKey(const Key('question-field')))
    .controller!
    .text;

void main() {
  sqfliteFfiInit();

  uiTest(
    'speaking fills the box live; the app NEVER submits by itself; the worker is told to check the words',
    (t) async {
      final v = FakeVoice();
      final rig = (await t.runAsync(
        () => buildRig(configured: false, voice: v),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 1400),
      );
      await t.tap(find.byKey(const Key('mic-button')));
      await t.pump();
      expect(find.text('Listening… speak now'), findsWidgets);
      expect(
        t.widget<FilledButton>(find.byKey(const Key('ask-button'))).onPressed,
        isNull,
        reason: 'cannot press Check while listening',
      );
      v.say('when is the next');
      await t.pump();
      expect(fieldText(t), 'when is the next');
      v.say('when is the next ANC visit', fin: true);
      v.finish();
      await t.pump();
      expect(fieldText(t), 'when is the next ANC visit');
      expect(
        find.text('Check the words below, fix any mistakes, then press Check.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notice-cannotVerifyOffline')),
        findsNothing,
        reason: 'nothing was checked automatically',
      );
      expect(rig.server.requestPaths, isEmpty);
    },
  );

  uiTest(
    'voice language follows the app language by default and can be switched; Telugu and English are both requested correctly',
    (t) async {
      final v = FakeVoice();
      final rig = (await t.runAsync(
        () => buildRig(configured: false, voice: v, lang: 'te'),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 1400),
      );
      await t.tap(find.byKey(const Key('mic-button')));
      await t.pump();
      expect(v.lang, 'te');
      v.finish();
      await t.pump();
      await t.tap(find.byKey(const Key('voice-lang-en')));
      await t.pump();
      await t.tap(find.byKey(const Key('mic-button')));
      await t.pump();
      expect(v.lang, 'en');
      v.finish();
      await t.pump();
    },
  );

  uiTest('spoken text is appended to what was already typed', (t) async {
    final v = FakeVoice();
    final rig = (await t.runAsync(
      () => buildRig(configured: false, voice: v),
    ))!;
    await pumpApp(t, rig, home: const AskScreen(), size: const Size(412, 1400));
    await t.enterText(find.byKey(const Key('question-field')), 'ANC visit');
    await t.tap(find.byKey(const Key('mic-button')));
    await t.pump();
    v.say('కోసం ఎప్పుడు', fin: true);
    v.finish();
    await t.pump();
    expect(fieldText(t), 'ANC visit కోసం ఎప్పుడు');
  });

  // Found on a phone: after Check, the next voice take was added to the old question, so Check answered the old question again.
  uiTest('a voice take after a checked question starts a NEW question', (t) async {
    final v = FakeVoice();
    final rig = (await t.runAsync(
      () => buildRig(configured: false, voice: v, sampleProtocol: true),
    ))!;
    await pumpApp(t, rig, home: const AskScreen(), size: const Size(412, 1400));
    await t.tap(find.byKey(const Key('mic-button')));
    await t.pump();
    v.say('how often should I wash my hands', fin: true);
    v.finish();
    await t.pump();
    await t.tap(find.byKey(const Key('ask-button')));
    await settle(t, maxRounds: 30);
    // second take
    await t.tap(find.byKey(const Key('mic-button')));
    await t.pump();
    v.say('pregnant woman has fits', fin: true);
    v.finish();
    await t.pump();
    expect(fieldText(t), 'pregnant woman has fits', reason: 'not appended to the already checked question');
    // an edited, unchecked box still gets the voice text added
    await t.enterText(find.byKey(const Key('question-field')), 'ANC visit');
    await t.tap(find.byKey(const Key('mic-button')));
    await t.pump();
    v.say('when', fin: true);
    v.finish();
    await t.pump();
    expect(fieldText(t), 'ANC visit when');
  });

  uiTest(
    'a spoken (Telugu) danger sign still goes through the safety check and escalates',
    (t) async {
      final v = FakeVoice();
      final rig = (await t.runAsync(
        () => buildRig(configured: false, voice: v, lang: 'te'),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 1400),
      );
      await t.tap(find.byKey(const Key('mic-button')));
      await t.pump();
      v.say('గర్భిణీకి ఇప్పుడు విపరీతంగా రక్తస్రావం అవుతోంది', fin: true);
      v.finish();
      await t.pump();
      await t.tap(find.byKey(const Key('ask-button')));
      await settle(
        t,
        until: () =>
            find.byKey(const Key('escalation-card')).evaluate().isNotEmpty,
        maxRounds: 30,
      );
      expect(find.byKey(const Key('escalation-card')), findsOneWidget);
    },
  );

  uiTest('tapping the mic again stops listening', (t) async {
    final v = FakeVoice();
    final rig = (await t.runAsync(
      () => buildRig(configured: false, voice: v),
    ))!;
    await pumpApp(t, rig, home: const AskScreen(), size: const Size(412, 1400));
    await t.tap(find.byKey(const Key('mic-button')));
    await t.pump();
    await t.tap(find.byKey(const Key('mic-button')));
    await t.pump();
    expect(v.stops, greaterThan(0));
    expect(
      t.widget<FilledButton>(find.byKey(const Key('ask-button'))).onPressed,
      isNotNull,
    );
  });

  for (final c in {
    VoiceProblem.permissionDenied: 'Microphone permission is off.',
    VoiceProblem.unavailable: 'Voice input is not available on this phone.',
    VoiceProblem.languageMissing:
        'This phone has no speech support for the chosen language.',
    VoiceProblem.noSpeech: 'I did not hear anything.',
    VoiceProblem.network: 'Voice needs a connection on this phone right now.',
    VoiceProblem.other: 'Voice input stopped.',
  }.entries) {
    uiTest(
      'problem ${c.key.name}: plain-language message, typing still works',
      (t) async {
        final v = FakeVoice()..problem = c.key;
        final rig = (await t.runAsync(
          () => buildRig(configured: false, voice: v),
        ))!;
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 1400),
        );
        await t.tap(find.byKey(const Key('mic-button')));
        await t.pump();
        expect(find.textContaining(c.value), findsOneWidget);
        await t.enterText(
          find.byKey(const Key('question-field')),
          'typed question',
        );
        expect(fieldText(t), 'typed question');
      },
    );
  }

  uiTest(
    'the voice privacy note is always visible and the answer card says plainly when no server address is set',
    (t) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 1400),
      );
      expect(find.textContaining('does not save your voice'), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('question-field')),
        'How often is the register reviewed?',
      );
      await t.tap(find.byKey(const Key('ask-button')));
      await settle(
        t,
        until: () => find
            .byKey(const Key('notice-cannotVerifyOffline'))
            .evaluate()
            .isNotEmpty,
        maxRounds: 30,
      );
      expect(
        find.textContaining('no server address is set in Settings'),
        findsOneWidget,
      );
    },
  );
}
