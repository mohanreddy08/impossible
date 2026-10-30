import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/domain/safety/safety_engine.dart';

List<Map<String, dynamic>> _jsonl(String path) =>
    File(path)
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();

void main() {
  final engine = SafetyEngine.fromJsonString(
    File('assets/safety/danger_rules.json').readAsStringSync(),
  );
  final cases = _jsonl('../health-worker-datasets/danger_sign_tests.jsonl');
  final questions = _jsonl(
    '../health-worker-datasets/health_questions_200.jsonl',
  );

  test('bundled ruleset is byte-identical to the backend ruleset (single source of truth)', () {
    final backend = File(
      '../health-worker-backend/app/services/safety/rules/danger_rules.json',
    ).readAsStringSync();
    expect(
      File('assets/safety/danger_rules.json').readAsStringSync(),
      backend,
      reason:
          'run: python3 tool/make_demo_seed.py to re-copy the backend ruleset',
    );
  });

  test('ruleset is labelled as NOT clinically validated', () {
    final d = engine.evaluate('Pregnant woman is bleeding heavily right now');
    expect(d.clinicallyValidated, isFalse);
    expect(d.rulesetReviewStatus, contains('UNREVIEWED'));
    expect(d.rulesetVersion, isNotEmpty);
  });

  test(
    'every supplied danger-sign case matches the backend expectation (${cases.length} cases)',
    () {
      final misses = <String>[];
      for (final c in cases) {
        final d = engine.evaluate(c['input_text'] as String);
        if (d.status != c['expected_safety_status']) {
          misses.add(
            '${c['test_id']}: expected ${c['expected_safety_status']} got ${d.status} :: ${c['input_text']}',
          );
        }
      }
      expect(cases.length, greaterThanOrEqualTo(100));
      expect(misses, isEmpty);
    },
  );

  test('false negatives / false positives for escalation are both zero', () {
    var fn = 0, fp = 0;
    for (final c in cases) {
      final got = engine.evaluate(c['input_text'] as String).status;
      final exp = c['expected_safety_status'];
      if (exp == statusEscalation && got != statusEscalation) fn++;
      if (exp != statusEscalation && got == statusEscalation) fp++;
    }
    expect((fn, fp), (0, 0));
  });

  test(
    'all ${questions.length} supplied questions get the same gate result as the backend labels',
    () {
      final mism = [
        for (final q in questions)
          if (engine.evaluate(q['question_text'] as String).status !=
              q['expected_safety_status'])
            q['question_id'],
      ];
      expect(questions.length, greaterThan(0));
      expect(mism, isEmpty);
    },
  );

  test('dosage requests are refused as out of scope', () {
    for (final t in [
      'What dose of amoxicillin should I give a child?',
      'పిల్లలకు యాంటీబయాటిక్ డోసు ఎంత?',
      'pillalaku antibiotic dose enta ivvali',
    ]) {
      expect(engine.evaluate(t).status, statusOutOfScope, reason: t);
    }
  });
}
