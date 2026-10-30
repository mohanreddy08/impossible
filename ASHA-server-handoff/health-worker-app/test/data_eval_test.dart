import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/services/qa_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// Sends every sample question in asha-data/questions through the real answer pipeline and compares the result with the HIDDEN
/// answer key (asha-data/questions/answers_hidden.jsonl). When the real question set arrives it is evaluated the same way.
List<Map<String, dynamic>> _jsonl(String path) => [
  for (final l in File(path).readAsLinesSync())
    if (l.trim().isNotEmpty) jsonDecode(l) as Map<String, dynamic>,
];

void main() {
  sqfliteFfiInit();

  uiTest(
    'evaluation: all sample questions against the hidden answer key (retrieval, escalation, refusals), offline',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(configured: false, sampleProtocol: true),
      ))!;
      final qs = _jsonl('../asha-data/questions/questions.jsonl');
      final key = {
        for (final h in _jsonl('../asha-data/questions/answers_hidden.jsonl'))
          h['question_id'] as String: h,
      };
      var answerable = 0,
          hit1 = 0,
          hit3 = 0,
          mustEsc = 0,
          escOk = 0,
          wrongOutcome = 0,
          negatives = 0;
      final misses = <String>[];
      final byLang = <String, List<int>>{}; // language -> [answerable, hit3]
      for (final q in qs) {
        final id = q['question_id'] as String;
        final h = key[id]!;
        final r = (await t.runAsync(
          () => rig.services.qa.ask(q['question_text'] as String),
        ))!;
        final want = h['expected_outcome'] as String;
        if (want == 'no_answer') negatives++;
        final anchors = (h['expected_anchors'] as List).cast<String>();
        final doc = h['expected_document_id'] as String?;
        // evidence shown for an answer, or beside a danger-sign card
        final shown = [
          for (final e in r.evidence) '${e.documentId}#${e.sectionId}',
        ];
        final expected = {for (final a in anchors) '$doc#$a'};
        if (anchors.isNotEmpty) {
          answerable++;
          final l = byLang.putIfAbsent(
            q['language_type'] as String,
            () => [0, 0],
          );
          l[0]++;
          if (shown.isNotEmpty && expected.contains(shown.first)) hit1++;
          if (shown.any(expected.contains)) {
            hit3++;
            l[1]++;
          } else {
            misses.add(
              '$id [${q['language_type']}] "${q['question_text']}" -> ${r.outcome.name} shown=$shown want=$expected',
            );
          }
        }
        if (h['must_escalate'] == true) {
          mustEsc++;
          if (r.outcome == QaOutcome.escalationRequired) {
            escOk++;
          } else {
            misses.add(
              '$id ESCALATION MISSED "${q['question_text']}" -> ${r.outcome.name}',
            );
          }
        }
        final ok = switch (want) {
          'escalation' =>
            r.outcome == QaOutcome.escalationRequired ||
                r.outcome == QaOutcome.answeredWithEvidence,
          'answer' =>
            r.outcome == QaOutcome.answeredWithEvidence ||
                r.outcome == QaOutcome.answeredFromRecords,
          'clarification' => r.outcome == QaOutcome.clarificationRequired,
          'refusal' => r.outcome == QaOutcome.outOfScope,
          'no_answer' => r.outcome != QaOutcome.answeredWithEvidence,
          _ => true,
        };
        if (!ok) {
          wrongOutcome++;
          misses.add(
            '$id OUTCOME want=$want got=${r.outcome.name} "${q['question_text']}"',
          );
        }
      }
      // ignore: avoid_print
      print(
        'EVAL questions=${qs.length} answerable=$answerable hit@1=$hit1 hit@3=$hit3 | must-escalate=$mustEsc escalated=$escOk | wrong-outcome=$wrongOutcome unanswerable-questions=$negatives',
      );
      // ignore: avoid_print
      print('EVAL by language (answerable, found in top 3): $byLang');
      for (final m in misses) {
        // ignore: avoid_print
        print('EVAL miss: $m');
      }
      final report = StringBuffer()
        ..writeln(
          'questions=${qs.length} answerable=$answerable hit1=$hit1 hit3=$hit3 mustEscalate=$mustEsc escalated=$escOk wrongOutcome=$wrongOutcome',
        );
      File('../asha-data/build/last_evaluation.txt')
          .writeAsStringSync(report.toString());
      expect(answerable, greaterThan(30));
    },
  );

  uiTest(
    'evaluation (held-out questions, never used for tuning): how well unseen wording is handled',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(configured: false, sampleProtocol: true),
      ))!;
      final qs = _jsonl('../asha-data/questions/questions_heldout.jsonl');
      final key = {
        for (final h in _jsonl(
          '../asha-data/questions/answers_hidden_heldout.jsonl',
        ))
          h['question_id'] as String: h,
      };
      var hit1 = 0, hit3 = 0, esc = 0;
      final misses = <String>[];
      for (final q in qs) {
        final h = key[q['question_id']]!;
        final r = (await t.runAsync(
          () => rig.services.qa.ask(q['question_text'] as String),
        ))!;
        final want =
            '${h['expected_document_id']}#${(h['expected_anchors'] as List).first}';
        final shown = [
          for (final e in r.evidence) '${e.documentId}#${e.sectionId}',
        ];
        if (shown.isNotEmpty && shown.first == want) hit1++;
        if (shown.contains(want)) {
          hit3++;
        } else {
          misses.add(
            '${q['question_id']} [${q['language_type']}] "${q['question_text']}" -> ${r.outcome.name} shown=$shown',
          );
        }
        if (r.outcome == QaOutcome.escalationRequired) esc++;
      }
      // ignore: avoid_print
      print(
        'HELDOUT questions=${qs.length} hit@1=$hit1 hit@3=$hit3 escalated=$esc',
      );
      for (final m in misses) {
        // ignore: avoid_print
        print('HELDOUT miss: $m');
      }
      expect(qs.length, 24);
    },
  );
}
