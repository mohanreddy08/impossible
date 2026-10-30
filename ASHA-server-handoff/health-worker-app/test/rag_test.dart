import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/data/api/api_client.dart';
import 'package:health_companion/services/explainer.dart';
import 'package:health_companion/services/qa_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

// The server-side RAG step (Telugu and English): the model lives only on the nearby server; the phone just shows the reply.

const _te = 'చేతులు ఎలా కడుక్కోవాలి';
const _ans = 'సబ్బుతో చేతులను కనీసం 20 సెకన్లు రుద్దండి.';

Map<String, dynamic> _reply({
  String outcome = 'ANSWERED',
  String? answer = _ans,
  String source = 'extract',
}) => {
  'outcome': outcome,
  'answer': answer,
  'answer_source': source,
  'sources': [
    {
      'passage_id': 'P1',
      'document_id': 'D1',
      'document_title': 'Sample',
      'section_heading': 'చేతులు కడగడం',
      'relevance_score': 0.82,
      'source_verification_status': 'TEST_FIXTURE_ONLY',
      'text': _ans,
    },
  ],
};

void main() {
  sqfliteFfiInit();

  test('RagResponse parses the server reply', () {
    final r = RagResponse.fromJson(_reply(source: 'llm'));
    expect(r.answered, isTrue);
    expect(r.answerSource, 'llm');
    expect(r.sources.single.sectionHeading, 'చేతులు కడగడం');
    expect(
      RagResponse.fromJson(_reply(outcome: 'NO_APPROVED_TEXT', answer: null))
          .answered,
      isFalse,
    );
  });

  Future<(dynamic, QaResult)> rig(
    WidgetTester t, {
    bool offline = false,
    bool assist = true,
  }) async {
    final r = (await t.runAsync(
      () => buildRig(aiAssist: assist, offline: offline),
    ))!;
    // the phone's own search found nothing for the Telugu question (what the server RAG is for)
    const local = QaResult(
      outcome: QaOutcome.insufficientEvidence,
      message: '',
      rulesetVersion: 'test',
      fromDevice: true,
    );
    return (r, local);
  }

  uiTest(
    'ANSWERED: the server text and sources replace the phone\'s empty result',
    (t) async {
      final (r, local) = await rig(t);
      r.server.ragReply = _reply();
      final out = await t.runAsync(() => r.services.qa.ragAnswer(_te, local));
      expect(out, isNotNull);
      expect(out!.result.outcome, QaOutcome.answeredWithEvidence);
      expect(out.result.evidence.single.passageText, _ans);
      expect(out.explanation.text, _ans);
      expect(out.explanation.source, ExplanationSource.serverText);
      expect(r.server.ragCalls, 1);
    },
  );

  uiTest('an LLM-written answer is labelled as the server AI', (t) async {
    final (r, local) = await rig(t);
    r.server.ragReply = _reply(source: 'llm');
    final out = await t.runAsync(() => r.services.qa.ragAnswer(_te, local));
    expect(out!.explanation.source, ExplanationSource.server);
  });

  uiTest('NO_APPROVED_TEXT keeps the phone\'s own result', (t) async {
    final (r, local) = await rig(t);
    r.server.ragReply = _reply(outcome: 'NO_APPROVED_TEXT', answer: null);
    expect(await t.runAsync(() => r.services.qa.ragAnswer(_te, local)), isNull);
  });

  uiTest('an old server (404) keeps the phone\'s own result', (t) async {
    final (r, local) = await rig(t);
    r.server.ragStatus = 404;
    expect(await t.runAsync(() => r.services.qa.ragAnswer(_te, local)), isNull);
  });

  uiTest('a dose in the server text is dropped', (t) async {
    final (r, local) = await rig(t);
    r.server.ragReply = _reply(answer: 'Give 500 mg every six hours.');
    expect(await t.runAsync(() => r.services.qa.ragAnswer(_te, local)), isNull);
  });

  uiTest('offline: the server is never called', (t) async {
    final (r, local) = await rig(t, offline: true);
    r.server.ragReply = _reply();
    expect(
      await t.runAsync(
        () => r.services.qa.ragAnswer(_te, local, online: false),
      ),
      isNull,
    );
    expect(r.server.ragCalls, 0);
  });

  uiTest('AI help off: the server is never called', (t) async {
    final (r, local) = await rig(t, assist: false);
    r.server.ragReply = _reply();
    expect(await t.runAsync(() => r.services.qa.ragAnswer(_te, local)), isNull);
    expect(r.server.ragCalls, 0);
  });

  uiTest('a danger sign is never sent to RAG', (t) async {
    final r = (await t.runAsync(
      () => buildRig(sampleProtocol: true, aiAssist: true),
    ))!;
    r.server.ragReply = _reply();
    final local = (await t.runAsync(
      () => r.services.qa.ask('newborn baby is not breathing'),
    ))!;
    expect(local.outcome, QaOutcome.escalationRequired);
    expect(
      await t.runAsync(
        () => r.services.qa.ragAnswer('newborn baby is not breathing', local),
      ),
      isNull,
    );
    expect(r.server.ragCalls, 0);
  });

  uiTest(
    'a danger-sign passage from the server raises the alert, never "low"',
    (t) async {
      final (r, local) = await rig(t);
      r.server.ragReply = {
        ..._reply(answer: null),
        'outcome': 'ESCALATION_REQUIRED',
        'message': 'Possible danger sign.',
        'safety': {
          'rule_ids': ['RAG-DANGER-PASSAGE'],
        },
      };
      final out = await t.runAsync(() => r.services.qa.ragAnswer(_te, local));
      expect(out!.result.outcome, QaOutcome.escalationRequired);
      expect(out.result.evidence, isNotEmpty);
      expect(out.explanation, isNull);
    },
  );
}
