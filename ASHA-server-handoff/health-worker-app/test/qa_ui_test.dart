import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/presentation/screens/ask_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'support/builders.dart';
import 'support/fake_server.dart';

Future<void> ask(WidgetTester t, String q) async {
  await t.enterText(find.byKey(const Key('question-field')), q);
  await t.tap(find.byKey(const Key('ask-button')));
  await settle(
    t,
    until: () =>
        find.byKey(const Key('ask-button')).evaluate().isNotEmpty &&
        find.text('Checking…').evaluate().isEmpty,
    maxRounds: 30,
  );
  await settle(t, maxRounds: 6);
}

void main() {
  sqfliteFfiInit();

  group('safety escalation', () {
    uiTest(
      'a danger sign is shown as a prominent warning; with no approved protocol loaded there is no answer or advice, the card says so, and the server is never asked',
      (t) async {
        final rig = (await t.runAsync(() => buildRig()))!;
        // even if the server would happily "answer", the escalation must win
        rig.server.qaQuery = qaJson(
          'ANSWERED_WITH_EVIDENCE',
          answer: 'reassuring answer',
          citations: [citationJson()],
        );
        await pumpApp(t, rig, home: const AskScreen());
        await ask(t, 'Pregnant woman is bleeding heavily right now');
        expect(find.byKey(const Key('escalation-card')), findsOneWidget);
        expect(find.text('Possible danger sign'), findsOneWidget);
        expect(
          find.text('Follow your approved escalation steps now.'),
          findsOneWidget,
        );
        expect(
          find.byIcon(Icons.warning_amber_rounded),
          findsWidgets,
        ); // not colour alone: icon + words
        expect(find.byKey(const Key('passage-text')), findsNothing);
        expect(find.byKey(const Key('evidence-verified')), findsNothing);
        expect(find.text('Verified protocol text'), findsNothing);
        expect(find.text('reassuring answer'), findsNothing);
        expect(find.byKey(const Key('no-approved-guidance')), findsOneWidget);
        expect(
          rig.server.qaCalls,
          0,
          reason: 'escalation never waits for, or defers to, the network',
        );
        // the only request a danger sign may make is the optional AI one: nothing goes to the normal question pipeline
        expect(
          rig.server.requestPaths.where((p) => !p.endsWith('/health-qa/llm')),
          isEmpty,
        );
        // honesty about the placeholder wording and about validation
        expect(find.textContaining('PLACEHOLDER TEXT'), findsOneWidget);
        expect(
          find.text(
            'The wording below is placeholder text that has not been approved by a clinician.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Safety rules are not clinically validated yet'),
          findsOneWidget,
        );
        expect(find.text('Rules version 0.3.1-draft'), findsOneWidget);
      },
    );

    uiTest(
      'a danger sign shows APPROVED local protocol text beside the urgent steps; unverified text never appears; the server is still not asked',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        Future<void> insert(String status, int approved) =>
            rig.services.store.db.transaction((txn) async {
              await txn.insert('protocol_documents', {
                'document_id': 'D9',
                'title': 'Fixture Protocol (software test only)',
                'version': 'v1',
                'source_verification_status': status,
                'approved_for_retrieval': approved,
              });
              await txn.insert('protocol_passages', {
                'passage_id': 'D9-1',
                'document_id': 'D9',
                'section_id': '1',
                'section_title': 'Fixture section',
                'page_number': 1,
                'passage_text': 'FIXTURE TEXT for software tests only: pregnant woman bleeding heavily.',
                'approved_for_retrieval': approved,
                'source_verification_status': status,
              });
            });
        await t.runAsync(() => insert('UNVERIFIED', 0));
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 1800),
        );
        await ask(t, 'Pregnant woman is bleeding heavily right now');
        expect(find.byKey(const Key('escalation-card')), findsOneWidget);
        expect(find.byKey(const Key('passage-text')), findsNothing);
        expect(find.byKey(const Key('no-approved-guidance')), findsOneWidget);
        await t.runAsync(() => rig.services.store.wipe());
        await t.runAsync(() => insert('VERIFIED', 1));
        await ask(t, 'Pregnant woman is bleeding heavily right now');
        expect(find.byKey(const Key('escalation-card')), findsOneWidget);
        expect(find.text('Possible danger sign'), findsOneWidget);
        expect(find.text('Approved guidance'), findsOneWidget);
        expect(find.byKey(const Key('evidence-verified')), findsOneWidget);
        expect(find.byKey(const Key('no-approved-guidance')), findsNothing);
        expect(rig.server.qaCalls, 0);
        // the placeholder / not-validated honesty stays
        expect(find.textContaining('PLACEHOLDER TEXT'), findsOneWidget);
      },
    );

    uiTest(
      'escalation works with zero connectivity and tells the worker how to reach a supervisor only if a number was configured',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        await pumpApp(t, rig, home: const AskScreen());
        await ask(t, 'She is having fits and not waking up');
        expect(find.byKey(const Key('escalation-card')), findsOneWidget);
        expect(find.byKey(const Key('no-contact')), findsOneWidget);
        expect(find.byKey(const Key('call-supervisor')), findsNothing);
        expect(
          find.text('No supervisor number is set. Add one in Settings.'),
          findsOneWidget,
        );
      },
    );

    uiTest('a configured supervisor number gives a one-tap call', (t) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      await rig.services.settings.setEscalationPhone('+91 90000 00000');
      Uri? launched;
      await pumpApp(
        t,
        rig,
        size: const Size(412, 1400),
        home: AskScreen(
          launcher: (u) async {
            launched = u;
            return true;
          },
        ),
      );
      await ask(t, 'newborn is not feeding and feels cold');
      expect(find.byKey(const Key('escalation-card')), findsOneWidget);
      await t.tap(find.byKey(const Key('call-supervisor')));
      await t.pump();
      expect(launched?.scheme, 'tel');
      expect(
        launched?.path,
        '+919000000000',
        reason: 'spaces/dashes stripped so the dialer receives a clean number',
      );
    });

    uiTest(
      'Telugu, code-mixed and transliterated danger-sign questions all escalate',
      (t) async {
        final rig = (await t.runAsync(
          () => buildRig(configured: false, lang: 'te'),
        ))!;
        await pumpApp(t, rig, home: const AskScreen());
        for (final q in [
          'గర్భిణీకి ఇప్పుడు విపరీతంగా రక్తస్రావం అవుతోంది',
          'pregnant woman కి heavy bleeding అవుతోంది ఇప్పుడే',
          'garbhini ki ippudu ekkuva raktasravam avuthundi',
        ]) {
          await ask(t, q);
          expect(
            find.byKey(const Key('escalation-card')),
            findsOneWidget,
            reason: q,
          );
          expect(
            find.text('ప్రమాద సంకేతం కావచ్చు'),
            findsOneWidget,
          ); // Telugu title rendered
        }
      },
    );
  });

  group('other safety outcomes', () {
    uiTest('a vague or one-word complaint asks for clarification', (t) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      await pumpApp(t, rig, home: const AskScreen());
      await ask(t, 'she is not feeling well');
      expect(
        find.byKey(const Key('notice-clarificationRequired')),
        findsOneWidget,
      );
      expect(find.text('Please tell us more'), findsOneWidget);
      expect(find.byKey(const Key('escalation-card')), findsNothing);
    });

    uiTest('a dosage request is refused: no dose is shown', (t) async {
      final rig = (await t.runAsync(() => buildRig()))!;
      await pumpApp(t, rig, home: const AskScreen());
      await ask(t, 'What dose of amoxicillin should I give a child?');
      expect(find.byKey(const Key('notice-outOfScope')), findsOneWidget);
      expect(find.text('This app cannot help with this'), findsOneWidget);
      expect(find.textContaining('mg'), findsNothing);
      expect(find.byKey(const Key('passage-text')), findsNothing);
      expect(rig.server.qaCalls, 0);
    });

    uiTest(
      'an empty question is rejected in plain language and nothing is sent',
      (t) async {
        final rig = (await t.runAsync(() => buildRig()))!;
        await pumpApp(t, rig, home: const AskScreen());
        await t.tap(find.byKey(const Key('ask-button')));
        await settle(t, maxRounds: 6);
        expect(find.text('Type a question first.'), findsOneWidget);
        expect(rig.server.requestPaths, isEmpty);
      },
    );
  });

  group('evidence states (never an unsupported answer)', () {
    uiTest(
      'no verified evidence anywhere -> "no verified answer", clearly not an answer',
      (t) async {
        final rig = (await t.runAsync(() => buildRig()))!;
        rig.server.qaQuery = qaJson(
          'INSUFFICIENT_EVIDENCE',
          message: 'No verified protocol passage was found for this question.',
          retrieval: 'NO_RESULT',
        );
        await pumpApp(t, rig, home: const AskScreen());
        await ask(
          t,
          'How many antenatal check-ups should a pregnant woman have?',
        );
        expect(
          find.byKey(const Key('notice-insufficientEvidence')),
          findsOneWidget,
        );
        expect(find.text('No verified answer available'), findsOneWidget);
        expect(find.textContaining('This is not an answer'), findsOneWidget);
        expect(find.byKey(const Key('passage-text')), findsNothing);
        expect(find.text('Verified protocol text'), findsNothing);
      },
    );

    uiTest(
      'offline with no approved protocol text on the phone -> "cannot be verified offline", no answer invented',
      (t) async {
        final rig = (await t.runAsync(() => buildRig()))!;
        rig.server.down = true;
        await pumpApp(t, rig, home: const AskScreen());
        await ask(
          t,
          'How many antenatal check-ups should a pregnant woman have?',
        );
        expect(
          find.byKey(const Key('notice-cannotVerifyOffline')),
          findsOneWidget,
        );
        expect(find.text('Cannot be verified offline'), findsOneWidget);
        expect(find.byKey(const Key('passage-text')), findsNothing);
        expect(find.byKey(const Key('escalation-card')), findsNothing);
      },
    );

    uiTest(
      'verified server evidence shows title, section, page, version, status and the exact passage',
      (t) async {
        final rig = (await t.runAsync(() => buildRig()))!;
        rig.server.qaQuery = qaJson(
          'ANSWERED_WITH_EVIDENCE',
          answer: 'According to Sample Protocol: exact text',
          citations: [citationJson()],
          retrieval: 'MATCH_FOUND',
        );
        rig.server.qaRetrieve = {
          'query_id': 'q',
          'status': 'MATCH_FOUND',
          'original_query': 'x',
          'normalized_query': 'x',
          'matched_passage_ids': ['DOC-1-0001'],
          'indexed_passages': 1,
          'matches': [
            {
              ...citationJson(),
              'text': 'EXACT SOURCE PASSAGE TEXT.',
              'matched_terms': ['visit'],
            },
          ],
        };
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 1400),
        );
        await ask(t, 'When is the first visit due?');
        expect(find.byKey(const Key('evidence-verified')), findsOneWidget);
        expect(find.text('Verified protocol text'), findsOneWidget);
        for (final s in [
          'Sample Protocol',
          'Visit schedule',
          '12',
          'v3',
          'VERIFIED',
        ]) {
          expect(find.text(s), findsWidgets, reason: s);
        }
        expect(find.text('EXACT SOURCE PASSAGE TEXT.'), findsOneWidget);
        expect(find.text('Found by the server'), findsOneWidget);
      },
    );

    uiTest(
      'content that is not VERIFIED (e.g. test fixtures) is never presented as medical guidance',
      (t) async {
        final rig = (await t.runAsync(() => buildRig()))!;
        final c = citationJson(
          status: 'TEST_FIXTURE_ONLY',
          title: 'Fixture Guide',
        );
        rig.server.qaQuery = qaJson(
          'ANSWERED_WITH_EVIDENCE',
          answer: 'x',
          citations: [c],
        );
        rig.server.qaRetrieve = {
          'query_id': 'q',
          'status': 'MATCH_FOUND',
          'original_query': 'x',
          'normalized_query': 'x',
          'matched_passage_ids': [],
          'indexed_passages': 1,
          'matches': [
            {...c, 'text': 'fixture text', 'matched_terms': []},
          ],
        };
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 1400),
        );
        await ask(t, 'When is the first visit due?');
        expect(find.byKey(const Key('evidence-unverified')), findsOneWidget);
        expect(find.byKey(const Key('evidence-verified')), findsNothing);
        expect(
          find.text('Unverified text — not medical guidance'),
          findsOneWidget,
        );
        expect(find.text('Verified protocol text'), findsNothing);
        expect(find.text('TEST_FIXTURE_ONLY'), findsOneWidget);
      },
    );

    uiTest(
      "if the server's own (newer) safety rules escalate, that escalation wins over any answer",
      (t) async {
        final rig = (await t.runAsync(() => buildRig()))!;
        rig.server.qaQuery = qaJson(
          'ESCALATION_REQUIRED',
          message: 'server escalation text',
          safety: 'ESCALATION_REQUIRED',
        );
        await pumpApp(t, rig, home: const AskScreen());
        await ask(t, 'How often should the visit register be reviewed?');
        expect(find.byKey(const Key('escalation-card')), findsOneWidget);
        expect(find.text('server escalation text'), findsOneWidget);
        expect(find.byKey(const Key('passage-text')), findsNothing);
      },
    );

    uiTest(
      'approved protocol text stored on the phone answers offline, with citation; UNVERIFIED local text is ignored',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        Future<void> insert(String status, int approved) =>
            rig.services.store.db.transaction((txn) async {
              await txn.insert('protocol_documents', {
                'document_id': 'D1',
                'title': 'Local Protocol',
                'version': 'v1',
                'source_verification_status': status,
                'approved_for_retrieval': approved,
              });
              await txn.insert('protocol_passages', {
                'passage_id': 'D1-1',
                'document_id': 'D1',
                'section_id': '3',
                'section_title': 'Register upkeep',
                'page_number': 7,
                'passage_text': 'The visit register must be signed by the supervisor after each monthly review meeting.',
                'approved_for_retrieval': approved,
                'source_verification_status': status,
              });
            });
        await t.runAsync(() => insert('UNVERIFIED', 0));
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 1400),
        );
        await ask(t, 'Who signs the visit register after the monthly review?');
        expect(
          find.byKey(const Key('notice-cannotVerifyOffline')),
          findsOneWidget,
          reason: 'unverified text must not be used',
        );
        await t.runAsync(() => rig.services.store.wipe());
        await t.runAsync(() => insert('VERIFIED', 1));
        await ask(t, 'Who signs the visit register after the monthly review?');
        expect(find.byKey(const Key('evidence-verified')), findsOneWidget);
        expect(find.text('Local Protocol'), findsOneWidget);
        expect(find.text('Register upkeep'), findsOneWidget);
        expect(find.text('7'), findsOneWidget);
        expect(
          find.text(
            'The visit register must be signed by the supervisor after each monthly review meeting.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Found in protocol text stored on this phone'),
          findsOneWidget,
        );
      },
    );
  });

  group('answers from the phone\'s own records', () {
    Future<dynamic> seeded(WidgetTester t) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      await t.runAsync(() async {
        final st = rig.services.store;
        await st.wipe();
        await st.upsertHouseholds([
          hh(
            'HH-A',
            status: 'OVERDUE',
            next: DateTime(2026, 9, 20),
            scheduled: 'ANC',
          ),
          hh('HH-B', status: 'DUE_TODAY', next: today, scheduled: 'ROUTINE'),
        ], respectPending: false);
        await st.upsertVisits([
          vis('V-A', 'HH-A', DateTime(2026, 9, 20), reason: 'ANC'),
          vis('V-B', 'HH-B', today),
        ], respectPending: false);
        await st.upsertReferrals([
          ref(
            'R-A',
            'HH-A',
            'V-A',
            status: 'RECOMMENDED',
            created: DateTime(2026, 10, 5),
          ),
        ], respectPending: false);
      });
      return rig;
    }

    uiTest(
      '"which households are overdue" is answered from local records, offline, with no server call',
      (t) async {
        final rig = await seeded(t);
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 1800),
        );
        await ask(t, 'Which households are overdue?');
        expect(
          find.byKey(const Key('notice-answeredFromRecords')),
          findsOneWidget,
        );
        expect(
          find.text('1 households have an overdue visit.'),
          findsOneWidget,
        );
        expect(find.text('HH-A'), findsOneWidget);
        expect(find.text('HH-B'), findsNothing);
        expect(rig.server.qaCalls, 0);
        expect(find.textContaining('not medical advice'), findsOneWidget);
      },
    );

    uiTest(
      '"who should I attend first" lists the most urgent household first',
      (t) async {
        final rig = await seeded(t);
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 1800),
        );
        await ask(t, 'Who should I attend first?');
        expect(find.byKey(const Key('records-heading')), findsOneWidget);
        expect(
          find.text('2 households are waiting. Most urgent first:'),
          findsOneWidget,
        );
        final a = t.getTopLeft(find.text('HH-A')).dy,
            b = t.getTopLeft(find.text('HH-B')).dy;
        expect(a, lessThan(b));
      },
    );

    uiTest(
      'a household ID question shows that household, and an unknown ID says so',
      (t) async {
        final rig = await seeded(t);
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 1800),
        );
        await ask(t, 'next visit for HH-A?');
        expect(find.textContaining('HH-A: Status:'), findsOneWidget);
        await ask(t, 'next visit for HH-999?');
        expect(
          find.text('No household with ID HH-999 is on this phone.'),
          findsOneWidget,
        );
      },
    );

    uiTest('a clinical question is not mistaken for a records question', (
      t,
    ) async {
      final rig = await seeded(t);
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 1800),
      );
      await ask(t, 'What should I feed the baby today?');
      expect(find.byKey(const Key('notice-answeredFromRecords')), findsNothing);
    });
  });

  uiTest('clarification offers tap-to-add details and re-checks the question', (
    t,
  ) async {
    final rig = (await t.runAsync(() => buildRig(configured: false)))!;
    await pumpApp(t, rig, home: const AskScreen(), size: const Size(412, 1800));
    await ask(t, 'bleeding');
    expect(
      find.byKey(const Key('notice-clarificationRequired')),
      findsOneWidget,
    );
    await t.ensureVisible(find.byKey(const Key('clarify-severe')));
    await t.tap(find.byKey(const Key('clarify-severe')));
    await settle(t);
    await t.tap(
      find.byKey(const Key('clarify-now')).hitTestable().first,
      warnIfMissed: false,
    );
    await settle(t);
    expect(find.byKey(const Key('escalation-card')), findsOneWidget);
  });

  uiTest('the question text is never written to the local database', (t) async {
    final rig = (await t.runAsync(() => buildRig(configured: false)))!;
    await pumpApp(t, rig, home: const AskScreen());
    await ask(t, 'zebra-quokka-7731 bleeding heavily right now');
    expect(find.byKey(const Key('escalation-card')), findsOneWidget);
    final dump = await t.runAsync(() async {
      final b = StringBuffer();
      final tables = await rig.services.store.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      for (final tb in tables) {
        b.writeln(
          await rig.services.store.db.rawQuery('SELECT * FROM ${tb['name']}'),
        );
      }
      return b.toString();
    });
    expect(dump!.contains('quokka'), isFalse);
  });
}
