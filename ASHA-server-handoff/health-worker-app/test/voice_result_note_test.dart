import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/presentation/screens/ask_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'voice_test.dart' show FakeVoice;

// A speech recogniser can mishear a key word. When the checked text came from voice and the rules found no danger sign, the screen
// says so, instead of letting "no danger sign found" stand as if the words were certainly right.
Future<void> _speakAndCheck(WidgetTester t, FakeVoice v, String said) async {
  await t.tap(find.byKey(const Key('mic-button')));
  await settle(t, maxRounds: 6);
  v.say(said, fin: true);
  v.finish();
  await settle(t, maxRounds: 4);
  await t.tap(find.byKey(const Key('ask-button')));
  await settle(
    t,
    until: () => find.text('Checking…').evaluate().isEmpty,
    maxRounds: 40,
  );
  await settle(t, maxRounds: 10);
}

void main() {
  sqfliteFfiInit();
  const note = Key('voice-result-note');

  uiTest('voice text with no danger sign found: the caution is shown', (
    t,
  ) async {
    final v = FakeVoice();
    final rig = (await t.runAsync(
      () => buildRig(
        sampleProtocol: true,
        aiAssist: false,
        voice: v,
        offline: true,
      ),
    ))!;
    await pumpApp(t, rig, home: const AskScreen(), size: const Size(412, 3000));
    await _speakAndCheck(
      t,
      v,
      'What should I do if nobody is at home during a visit?',
    );
    expect(find.byKey(const Key('severity-low')), findsOneWidget);
    expect(find.byKey(note), findsOneWidget);
    expect(find.textContaining('may contain mistakes'), findsOneWidget);
  });

  uiTest('typed text: no caution', (t) async {
    final rig = (await t.runAsync(
      () => buildRig(sampleProtocol: true, aiAssist: false, offline: true),
    ))!;
    await pumpApp(t, rig, home: const AskScreen(), size: const Size(412, 3000));
    await t.enterText(
      find.byKey(const Key('question-field')),
      'What should I do if nobody is at home during a visit?',
    );
    await t.tap(find.byKey(const Key('ask-button')));
    await settle(
      t,
      until: () => find.byKey(const Key('severity-low')).evaluate().isNotEmpty,
      maxRounds: 40,
    );
    expect(find.byKey(const Key('severity-low')), findsOneWidget);
    expect(find.byKey(note), findsNothing);
  });

  uiTest(
    'voice text that IS a danger sign: the red alert stands alone, no caution',
    (t) async {
      final v = FakeVoice();
      final rig = (await t.runAsync(
        () => buildRig(
          sampleProtocol: true,
          aiAssist: false,
          voice: v,
          offline: true,
        ),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 3000),
      );
      await _speakAndCheck(t, v, 'The newborn baby is not feeding properly');
      expect(find.byKey(const Key('severity-high')), findsOneWidget);
      expect(find.byKey(note), findsNothing);
    },
  );

  uiTest('the caution does not stay after the next, typed Check', (t) async {
    final v = FakeVoice();
    final rig = (await t.runAsync(
      () => buildRig(
        sampleProtocol: true,
        aiAssist: false,
        voice: v,
        offline: true,
      ),
    ))!;
    await pumpApp(t, rig, home: const AskScreen(), size: const Size(412, 3000));
    await _speakAndCheck(
      t,
      v,
      'What should I do if nobody is at home during a visit?',
    );
    expect(find.byKey(note), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('question-field')),
      'What should I do if nobody is at home during a visit?',
    ); // the worker fixed the words by hand
    await t.tap(find.byKey(const Key('ask-button')));
    await settle(t, maxRounds: 30);
    expect(find.byKey(note), findsNothing);
  });
}
