import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/h5/h5_pipeline.dart';

/// The Dart engine must give the same answers as the Python engine that produced the submission files (h5/). The golden file is made by
/// health-worker-backend/h5 (see docs/H5.md); without it this test is skipped, because the hackathon questions are not in git.
void main() {
  final golden = File(Platform.environment['H5_GOLDEN'] ?? '/private/tmp/h5work/golden.json');
  test('Dart engine == Python engine on every dev and test question', () {
    final bot = H5Assistant.fromJson(File('assets/h5/rules.json').readAsStringSync(), File('assets/h5/protocols.json').readAsStringSync());
    final rows = (jsonDecode(golden.readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final bad = <String>[];
    for (final r in rows) {
      final a = bot.answer(r['id'] as String, r['text'] as String);
      final ok = a.text == r['answer'] &&
          a.escalate == r['escalate'] &&
          a.refused == r['refused'] &&
          a.cited.join(',') == (r['cited'] as List).join(',');
      if (!ok) bad.add('${r['id']}: esc ${a.escalate}/${r['escalate']} ref ${a.refused}/${r['refused']} cited ${a.cited}/${r['cited']} rules ${a.rules}/${r['rules']}');
    }
    expect(rows.length, greaterThan(200));
    expect(bad, isEmpty, reason: '${bad.length} of ${rows.length} differ:\n${bad.take(25).join('\n')}');
  }, skip: golden.existsSync() ? false : 'golden file not found');
}
