import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/presentation/screens/ask_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

Future<void> check(WidgetTester t, String q) async {
  await t.enterText(find.byKey(const Key('question-field')), q);
  await t.tap(find.byKey(const Key('ask-button')));
  await settle(t, maxRounds: 30);
  await settle(t, maxRounds: 6);
}

void main() {
  sqfliteFfiInit();

  uiTest(
    'loading the demo adds the FICTIONAL sample document: 64 passages, every one marked TEST_FIXTURE_ONLY, never VERIFIED',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(configured: false, sampleProtocol: true),
      ))!;
      final db = rig.services.store.db;
      final docs = (await t.runAsync(() => db.query('protocol_documents')))!;
      expect(docs, hasLength(3));
      expect(
        docs.every((d) => (d['document_id'] as String).startsWith('SAMPLE-')),
        isTrue,
      );
      expect(
        docs.every(
          (d) => d['source_verification_status'] == 'TEST_FIXTURE_ONLY',
        ),
        isTrue,
      );
      expect(
        docs.every((d) => (d['title'] as String).contains('SAMPLE')),
        isTrue,
      );
      final ps = (await t.runAsync(() => db.query('protocol_passages')))!;
      expect(ps, hasLength(64));
      expect(
        ps.every((p) => p['source_verification_status'] == 'TEST_FIXTURE_ONLY'),
        isTrue,
      );
      expect(
        ps.every(
          (p) =>
              (p['passage_text'] as String).startsWith('[DEMO SAMPLE]') ||
              (p['passage_text'] as String).startsWith('[SAMPLE]') ||
              (p['passage_text'] as String).startsWith('[డెమో నమూనా]'),
        ),
        isTrue,
      );
      expect(
        await t.runAsync(() => rig.services.library.approvedPassageCount()),
        0,
        reason: 'the sample is never counted as approved',
      );
    },
  );

  uiTest('the sample is searchable only while demo mode is on', (t) async {
    final rig = (await t.runAsync(
      () => buildRig(configured: false, sampleProtocol: true),
    ))!;
    expect(
      (await t.runAsync(() => rig.services.library.loadIndex()))!
          .search('nobody is at home visit', minScore: 0.5, minMatchedTerms: 2),
      isNotEmpty,
    );
    await t.runAsync(() => rig.services.settings.setUseDemoDate(false));
    expect(
      (await t.runAsync(() => rig.services.library.loadIndex()))!
          .search('nobody is at home visit', minScore: 0.5, minMatchedTerms: 2),
      isEmpty,
    );
  });

  uiTest(
    'OFFLINE, an English question is answered from the sample, clearly labelled UNVERIFIED with its fictional source',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(configured: false, sampleProtocol: true),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 3000),
      );
      await check(t, 'What do I do if nobody is at home during a visit?');
      expect(
        find.byKey(const Key('evidence-unverified')),
        findsWidgets,
      ); // a question can match more than one sample passage
      expect(find.byKey(const Key('evidence-verified')), findsNothing);
      expect(find.textContaining('[DEMO SAMPLE]'), findsWidgets);
      expect(
        find.textContaining('SAMPLE - how ASHA works in the field'),
        findsWidgets,
      );
      expect(find.text('Verified protocol text'), findsNothing);
    },
  );

  uiTest(
    'OFFLINE, a Telugu question is answered from the Telugu sample passage',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(configured: false, lang: 'te', sampleProtocol: true),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 3000),
      );
      await check(t, 'ఇంట్లో ఎవరూ లేకపోతే సందర్శనను ఎలా నమోదు చేయాలి');
      expect(find.byKey(const Key('evidence-unverified')), findsWidgets);
      expect(find.textContaining('[డెమో నమూనా]'), findsWidgets);
    },
  );

  uiTest(
    'a danger sign shows the sample under "Sample text (not approved guidance)", never under "Approved guidance"',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(configured: false, sampleProtocol: true),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 3000),
      );
      await check(t, 'heavy bleeding danger signs');
      expect(find.byKey(const Key('escalation-card')), findsOneWidget);
      expect(find.text('Approved guidance'), findsNothing);
      expect(find.text('Sample text (not approved guidance)'), findsOneWidget);
    },
  );

  uiTest(
    'a medicine/dose request is still refused first, even though a sample passage mentions medicines',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(configured: false, sampleProtocol: true),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 3000),
      );
      await check(t, 'what dose of paracetamol should I give');
      expect(find.byKey(const Key('notice-outOfScope')), findsOneWidget);
      expect(find.byKey(const Key('evidence-unverified')), findsNothing);
    },
  );

  uiTest(
    'with demo mode off the same question is NOT answered from the sample',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(configured: false, sampleProtocol: true),
      ))!;
      await t.runAsync(() => rig.services.settings.setUseDemoDate(false));
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 3000),
      );
      await check(t, 'What do I do if nobody is at home during a visit?');
      expect(find.byKey(const Key('evidence-unverified')), findsNothing);
      expect(
        find.byKey(const Key('notice-cannotVerifyOffline')),
        findsOneWidget,
      );
    },
  );

  uiTest(
    'refreshing protocols from a server never deletes the bundled sample',
    (t) async {
      final rig = (await t.runAsync(() => buildRig(sampleProtocol: true)))!;
      await t.runAsync(
        () => rig.services.library.refreshFromServer(),
      ); // the fake server has no documents
      final n = (await t.runAsync(
        () => rig.services.store.db.rawQuery(
          "SELECT COUNT(*) c FROM protocol_passages WHERE document_id LIKE 'SAMPLE-%'",
        ),
      ))!.single['c'];
      expect(n, 64);
    },
  );
}
