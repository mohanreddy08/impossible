import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/domain/safety/safety_engine.dart';

// Spoken, misspelled and transliterated danger phrasings (same file as the backend's eval/danger_variants.jsonl):
// the phone's own rules must escalate every one of them, refuse the dose requests and not escalate negated ones.
void main() {
  final engine = SafetyEngine.fromJsonString(
    File('assets/safety/danger_rules.json').readAsStringSync(),
  );
  const want = {
    'ESC': 'ESCALATION_REQUIRED',
    'OOS': 'OUT_OF_SCOPE',
    'OK': 'NORMAL_PROTOCOL_QUERY',
  };
  final rows = File('test/data/danger_variants.jsonl')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .toList();

  test('the phone escalates 100% of the spoken / misspelled danger phrases', () {
    final wrong = [
      for (final r in rows)
        if (engine.evaluate(r['t'] as String).status != want[r['e']])
          '${r['e']} got ${engine.evaluate(r['t'] as String).status}: ${r['t']}',
    ];
    expect(rows.length, greaterThanOrEqualTo(80));
    expect(wrong, isEmpty);
  });
}
