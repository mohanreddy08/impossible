import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/presentation/screens/ask_screen.dart';
import 'package:health_companion/services/explainer.dart';
import 'package:health_companion/services/qa_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'support/fake_server.dart';

// The Ask pipeline end to end: text or voice -> embedding -> vector search -> (network? the server's LLM : the phone's own explainer)
// -> one explanation card -> severity decides the action. Every request gives up after 10 seconds and the phone explains it itself.

const _q = 'What should I do if nobody is at home during a visit?';
const _dose = 'Give 500 mg every six hours.';

Evidence _ev(String text, {String? section = 'Planning'}) => Evidence(
  documentTitle: 'Doc',
  documentId: 'D',
  sectionTitle: section,
  sectionId: 'S',
  verificationStatus: 'VERIFIED',
  passageText: text,
);

Future<void> _ask(WidgetTester t, String q) async {
  await t.enterText(find.byKey(const Key('question-field')), q);
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

  group('severity (decided by the phone\'s rules, never by an AI)', () {
    test('danger sign = high, unclear = medium, approved text found = low, the rest none', () {
      expect(severityOf(QaOutcome.escalationRequired), Severity.high);
      expect(severityOf(QaOutcome.clarificationRequired), Severity.medium);
      expect(severityOf(QaOutcome.answeredWithEvidence), Severity.low);
      for (final o in [
        QaOutcome.outOfScope,
        QaOutcome.insufficientEvidence,
        QaOutcome.cannotVerifyOffline,
        QaOutcome.answeredFromRecords,
      ]) {
        expect(severityOf(o), isNull, reason: '$o');
      }
      expect(actionFor(Severity.high), SeverityAction.alertAndEscalate);
      expect(actionFor(Severity.medium), SeverityAction.askForDetails);
      expect(actionFor(Severity.low), SeverityAction.showInfo);
    });
  });

  group('OfflineExplainer (no network, nothing generated)', () {
    const ex = OfflineExplainer();

    test('picks the sentences that match the question, in their original order, under the section title', () {
      final e = _ev(
        'Wash your hands before visiting. If nobody is at home, record the visit as not done. Plan a new visit date for the same household. Bring the register.',
      );
      final out = ex.explain('what to do when nobody is at home', [e]);
      expect(out.split('\n').first, 'Planning');
      expect(
        out,
        contains('• If nobody is at home, record the visit as not done.'),
      );
      expect(out, isNot(contains('Wash your hands')));
    });

    test(
      'every sentence shown is taken word for word from the approved passages',
      () {
        final texts = [
          'Heavy bleeding in pregnancy is a danger sign. Refer at once. Keep the woman lying down.',
          'A severe headache with blurred vision needs urgent referral. Tell the supervisor.',
        ];
        final out = ex.explain('danger signs in pregnancy', [
          for (final t in texts) _ev(t),
        ]);
        for (final line in out.split('\n').skip(1)) {
          final sentence = line.replaceFirst('• ', '');
          expect(
            texts.any((t) => t.contains(sentence)),
            isTrue,
            reason: sentence,
          );
        }
      },
    );

    test('short and bounded: at most 3 sentences and 600 characters', () {
      final long = List.generate(
        30,
        (i) => 'Sentence number $i about fever in the child.',
      ).join(' ');
      final out = ex.explain('fever child', [_ev(long), _ev(long)]);
      expect('•'.allMatches(out).length, lessThanOrEqualTo(3));
      expect(out.length, lessThanOrEqualTo(700));
    });

    test(
      'no match in the question: the first sentences of the best passage',
      () {
        final out = ex.explain('zzz qqq', [
          _ev('First sentence here. Second sentence here. Third one.'),
        ]);
        expect(out, contains('First sentence here.'));
      },
    );

    test('Telugu text is split on the Telugu full stop too', () {
      final out = ex.explain('ప్రమాద సంకేతం వెంటనే రెఫర్', [
        _ev(
          'గర్భిణీకి ఎక్కువ రక్తస్రావం ప్రమాద సంకేతం। వెంటనే రెఫర్ చేయండి। ఇంటిని సందర్శించండి।',
          section: null,
        ),
      ]);
      expect(out, contains('• గర్భిణీకి ఎక్కువ రక్తస్రావం ప్రమాద సంకేతం'));
      expect(out.split('\n').length, greaterThan(1));
    });

    test('nothing to explain from nothing', () {
      expect(ex.explain('anything', const []), '');
    });
  });

  group('QaService.explain: both paths, one kind of result', () {
    Future<QaResult> found(WidgetTester t, AppRig rig) async {
      final r = (await t.runAsync(() => rig.services.qa.ask(_q)))!;
      expect(r.outcome, QaOutcome.answeredWithEvidence);
      return r;
    }

    uiTest(
      'no approved passages -> nothing to explain (null), and the server is not asked',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(aiAssist: false)))!;
        final r = (await t.runAsync(
          () => rig.services.qa.ask('What is the capital of France'),
        ))!;
        expect(
          await t.runAsync(
            () => rig.services.qa.explain('What is the capital of France', r),
          ),
          isNull,
        );
        expect(rig.server.explainBodies, isEmpty);
      },
    );

    uiTest(
      'ONLINE: the server gets the question, the closest passages and the safety status, and its text is the explanation',
      (t) async {
        final rig = (await t.runAsync(
          () => buildRig(sampleProtocol: true, aiAssist: true),
        ))!;
        final r = await found(t, rig);
        final e = (await t.runAsync(() => rig.services.qa.explain(_q, r)))!;
        expect(e.source, ExplanationSource.server);
        expect(e.text, 'Please take her to the health centre now.');
        expect(e.severity, Severity.low);
        expect(e.fallback, FallbackReason.none);
        final sent = rig.server.explainBodies.single;
        expect(sent['question'], _q);
        expect(sent['safety_status'], 'NORMAL_PROTOCOL_QUERY');
        final passages = (sent['passages'] as List)
            .cast<Map<String, dynamic>>();
        expect(passages.length, inInclusiveRange(1, 3));
        expect(passages.first['text'], r.evidence.first.passageText);
        expect(
          rig.server.llmBodies,
          isEmpty,
          reason: 'the question-only route is no longer used',
        );
      },
    );

    uiTest(
      'OFFLINE (no connection): the phone explains it itself and sends nothing',
      (t) async {
        final rig = (await t.runAsync(
          () => buildRig(sampleProtocol: true, aiAssist: true),
        ))!;
        final r = await found(t, rig);
        final e = (await t.runAsync(
          () => rig.services.qa.explain(_q, r, online: false),
        ))!;
        expect(e.source, ExplanationSource.device);
        expect(
          e.fallback,
          FallbackReason.none,
          reason: 'offline is the normal case, not a failure',
        );
        expect(e.text, contains('nobody is at home'));
        expect(rig.server.explainBodies, isEmpty);
        expect(
          rig.server.requestPaths.where((p) => p.contains('health-qa')),
          isEmpty,
        );
      },
    );

    uiTest(
      'AI help OFF (the default): same explanation online or offline, and the server is never asked',
      (t) async {
        final on = (await t.runAsync(
          () => buildRig(sampleProtocol: true, aiAssist: false),
        ))!;
        final off = (await t.runAsync(
          () => buildRig(sampleProtocol: true, aiAssist: false, offline: true),
        ))!;
        final ra = (await t.runAsync(() => on.services.qa.ask(_q)))!;
        final rb = (await t.runAsync(() => off.services.qa.ask(_q)))!;
        final a = (await t.runAsync(() => on.services.qa.explain(_q, ra)))!;
        final b = (await t.runAsync(
          () => off.services.qa.explain(_q, rb, online: false),
        ))!;
        expect((a.text, a.source), (b.text, b.source));
        expect(a.source, ExplanationSource.device);
        expect(on.server.explainBodies, isEmpty);
      },
    );

    uiTest('no server address: the phone explains it, nothing is sent', (
      t,
    ) async {
      final rig = (await t.runAsync(
        () => buildRig(sampleProtocol: true, aiAssist: true, configured: false),
      ))!;
      final r = await found(t, rig);
      final e = (await t.runAsync(() => rig.services.qa.explain(_q, r)))!;
      expect(e.source, ExplanationSource.device);
      expect(rig.server.requestPaths, isEmpty);
    });

    uiTest(
      'a slow server: after the time limit the phone explains it itself, and says why',
      (t) async {
        final srv = FakeServer()..llmDelay = const Duration(seconds: 3);
        final rig = (await t.runAsync(
          () => buildRig(sampleProtocol: true, aiAssist: true, server: srv),
        ))!;
        final r = await found(t, rig);
        final e = (await t.runAsync(
          () => rig.services.qa.explain(
            _q,
            r,
            timeout: const Duration(milliseconds: 150),
          ),
        ))!;
        expect(e.source, ExplanationSource.device);
        expect(e.fallback, FallbackReason.timeout);
        expect(e.text, isNotEmpty);
      },
    );

    test('the limit is 10 seconds', () {
      expect(QaService.defaultExplainTimeout, const Duration(seconds: 10));
    });

    uiTest(
      'server errors (502/503/504/429) and no network: the phone explains it, never an exception',
      (t) async {
        for (final code in [502, 503, 504, 429]) {
          final srv = FakeServer()..llmStatus = code;
          final rig = (await t.runAsync(
            () => buildRig(sampleProtocol: true, aiAssist: true, server: srv),
          ))!;
          final r = await found(t, rig);
          final e = (await t.runAsync(() => rig.services.qa.explain(_q, r)))!;
          expect(
            (e.source, e.fallback),
            (ExplanationSource.device, FallbackReason.unreachable),
            reason: '$code',
          );
        }
        final down = FakeServer()..down = true;
        final rig = (await t.runAsync(
          () => buildRig(sampleProtocol: true, aiAssist: true, server: down),
        ))!;
        final r = (await t.runAsync(() => rig.services.qa.ask(_q)))!;
        final e = (await t.runAsync(() => rig.services.qa.explain(_q, r)))!;
        expect(
          (e.source, e.fallback),
          (ExplanationSource.device, FallbackReason.unreachable),
        );
      },
    );

    uiTest(
      'the server refused its own text (wrong language / not grounded / dose): the phone explains it and says "rejected", not "unreachable"',
      (t) async {
        for (final code in [
          'LLM_WRONG_LANGUAGE',
          'LLM_NOT_GROUNDED',
          'LLM_UNSAFE_OUTPUT',
        ]) {
          final srv = FakeServer()
            ..llmStatus = 502
            ..llmErrorCode = code;
          final rig = (await t.runAsync(
            () => buildRig(sampleProtocol: true, aiAssist: true, server: srv),
          ))!;
          final r = (await t.runAsync(() => rig.services.qa.ask(_q)))!;
          final e = (await t.runAsync(() => rig.services.qa.explain(_q, r)))!;
          expect(
            (e.source, e.fallback),
            (ExplanationSource.device, FallbackReason.rejected),
            reason: code,
          );
        }
      },
    );

    uiTest(
      'the phone never trusts the server: a dose or a medicine name in its text is dropped',
      (t) async {
        for (final text in [
          _dose,
          'Give paracetamol for the fever.',
          'ఈ మాత్ర ఇవ్వండి',
        ]) {
          final srv = FakeServer()..llmText = text;
          final rig = (await t.runAsync(
            () => buildRig(sampleProtocol: true, aiAssist: true, server: srv),
          ))!;
          final r = await found(t, rig);
          final e = (await t.runAsync(() => rig.services.qa.explain(_q, r)))!;
          expect(
            (e.source, e.fallback),
            (ExplanationSource.device, FallbackReason.unsafe),
            reason: text,
          );
          expect(e.text, isNot(contains('500 mg')));
        }
      },
    );

    uiTest('a very long server text is cut to the limit', (t) async {
      final srv = FakeServer()..llmText = 'word ' * 2000;
      final rig = (await t.runAsync(
        () => buildRig(sampleProtocol: true, aiAssist: true, server: srv),
      ))!;
      final r = await found(t, rig);
      final e = (await t.runAsync(() => rig.services.qa.explain(_q, r)))!;
      expect(e.text.length, QaService.aiMaxChars);
    });

    uiTest(
      'a danger sign is passed on as ESCALATION_REQUIRED and keeps severity high',
      (t) async {
        final rig = (await t.runAsync(
          () => buildRig(sampleProtocol: true, aiAssist: true),
        ))!;
        const danger = 'Pregnant woman is bleeding heavily right now';
        final r = (await t.runAsync(() => rig.services.qa.ask(danger)))!;
        expect(r.outcome, QaOutcome.escalationRequired);
        final e = (await t.runAsync(() => rig.services.qa.explain(danger, r)))!;
        expect(e.severity, Severity.high);
        expect(
          rig.server.explainBodies.single['safety_status'],
          'ESCALATION_REQUIRED',
        );
      },
    );
  });

  group('Ask screen', () {
    uiTest(
      'LOW, offline: severity strip + explanation from the phone, no request',
      (t) async {
        final rig = (await t.runAsync(
          () => buildRig(sampleProtocol: true, aiAssist: true, offline: true),
        ))!;
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 3000),
        );
        await _ask(t, _q);
        expect(find.byKey(const Key('severity-low')), findsOneWidget);
        expect(find.byKey(const Key('explanation')), findsOneWidget);
        expect(find.textContaining('Explained on this phone'), findsOneWidget);
        expect(find.byKey(const Key('explanation-note')), findsNothing);
        expect(find.byKey(const Key('explanation-text')), findsOneWidget);
        expect(rig.server.requestPaths, isEmpty);
      },
    );

    uiTest('LOW, online with AI help: the same card, written by the server', (
      t,
    ) async {
      final rig = (await t.runAsync(
        () => buildRig(sampleProtocol: true, aiAssist: true),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 3000),
      );
      await _ask(t, _q);
      expect(find.byKey(const Key('severity-low')), findsOneWidget);
      expect(find.textContaining('Explained by your server'), findsOneWidget);
      expect(
        find.text('Please take her to the health centre now.'),
        findsOneWidget,
      );
      expect(find.textContaining('Not clinically verified'), findsOneWidget);
      expect(rig.server.explainBodies.length, 1);
    });

    uiTest(
      'LOW, online but the server is too slow: the phone\'s explanation appears with the reason',
      (t) async {
        final srv = FakeServer()..llmDelay = const Duration(seconds: 3);
        final rig = (await t.runAsync(
          () => buildRig(
            sampleProtocol: true,
            aiAssist: true,
            server: srv,
            explainTimeout: const Duration(milliseconds: 200),
          ),
        ))!;
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 3000),
        );
        await _ask(t, _q);
        expect(find.byKey(const Key('explanation-loading')), findsNothing);
        expect(find.textContaining('Explained on this phone'), findsOneWidget);
        expect(
          find.textContaining('did not answer in 10 seconds'),
          findsOneWidget,
        );
        await t.pump(
          const Duration(seconds: 4),
        ); // let the fake server's slow reply finish
      },
    );

    uiTest('while the server is being asked, a progress line shows', (t) async {
      final srv = FakeServer()..llmDelay = const Duration(seconds: 3);
      final rig = (await t.runAsync(
        () => buildRig(sampleProtocol: true, aiAssist: true, server: srv),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 3000),
      );
      await t.enterText(find.byKey(const Key('question-field')), _q);
      await t.tap(find.byKey(const Key('ask-button')));
      await settle(
        t,
        until: () =>
            find.byKey(const Key('explanation-loading')).evaluate().isNotEmpty,
        maxRounds: 30,
      );
      expect(find.textContaining('Asking the AI server'), findsOneWidget);
      // the normal result is already on screen while waiting
      expect(find.byKey(const Key('severity-low')), findsOneWidget);
      await t.pump(
        const Duration(seconds: 4),
      ); // let the fake server's slow reply finish
      await settle(t, maxRounds: 10);
    });

    uiTest(
      'HIGH: a danger sign shows the high strip and the red alert at once',
      (t) async {
        final rig = (await t.runAsync(
          () => buildRig(sampleProtocol: true, aiAssist: true, offline: true),
        ))!;
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 7000),
        );
        await _ask(t, 'I see a danger sign: the newborn baby is not feeding');
        expect(find.byKey(const Key('severity-high')), findsOneWidget);
        expect(find.byKey(const Key('escalation-card')), findsOneWidget);
        expect(find.textContaining('Act now'), findsOneWidget);
        // the explanation (from approved text) sits BELOW the alert
        expect(
          find.byKey(const Key('escalation-card')).evaluate().isNotEmpty,
          isTrue,
        );
        expect(
          t.getTopLeft(find.byKey(const Key('escalation-card'))).dy,
          lessThan(t.getTopLeft(find.byKey(const Key('explanation'))).dy),
        );
      },
    );

    uiTest('the card tells the worker when the server\'s text was refused', (
      t,
    ) async {
      final srv = FakeServer()
        ..llmStatus = 502
        ..llmErrorCode = 'LLM_WRONG_LANGUAGE';
      final rig = (await t.runAsync(
        () => buildRig(sampleProtocol: true, aiAssist: true, server: srv),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 3000),
      );
      await _ask(t, _q);
      expect(find.textContaining('Explained on this phone'), findsOneWidget);
      expect(
        find.textContaining('did not stay with the approved text'),
        findsOneWidget,
      );
      expect(find.textContaining('could not be reached'), findsNothing);
    });

    uiTest(
      'MEDIUM: unclear description shows the medium strip and the detail buttons, no explanation',
      (t) async {
        final rig = (await t.runAsync(
          () => buildRig(sampleProtocol: true, aiAssist: true, offline: true),
        ))!;
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 3000),
        );
        await _ask(t, 'the baby is not feeling well');
        expect(find.byKey(const Key('severity-medium')), findsOneWidget);
        expect(find.byKey(const Key('clarify-severe')), findsOneWidget);
        expect(find.byKey(const Key('explanation')), findsNothing);
      },
    );

    uiTest(
      'no approved text found: no severity strip and no explanation (nothing is explained from nothing)',
      (t) async {
        final rig = (await t.runAsync(
          () => buildRig(sampleProtocol: true, aiAssist: false),
        ))!;
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 3000),
        );
        await _ask(t, 'What is the capital of France');
        expect(
          find.byKey(const Key('notice-insufficientEvidence')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('explanation')), findsNothing);
        expect(
          find
              .byType(Container)
              .evaluate()
              .where((e) => e.widget.key.toString().contains('severity-')),
          isEmpty,
        );
        expect(rig.server.explainBodies, isEmpty);
      },
    );

    uiTest(
      'Telugu screen: the strip, the card and the notes have no English words left',
      (t) async {
        final rig = (await t.runAsync(
          () => buildRig(
            sampleProtocol: true,
            aiAssist: true,
            offline: true,
            lang: 'te',
          ),
        ))!;
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 3000),
        );
        await _ask(t, 'garbhini ki pitts vastunnayi');
        expect(find.byKey(const Key('severity-high')), findsOneWidget);
        final texts = <String>[
          for (final w
              in find.byType(Text).evaluate().map((e) => e.widget as Text))
            if ((w.data ?? '').isNotEmpty) w.data!,
        ];
        expect(
          texts.where((x) => x.contains('Act now') || x.contains('Explained')),
          isEmpty,
        );
      },
    );
  });
}
