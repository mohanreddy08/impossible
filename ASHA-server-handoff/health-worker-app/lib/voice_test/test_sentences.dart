import 'dart:convert';

/// One Telugu sentence the tester reads aloud, with what the app is expected to do with it.
class TestSentence {
  const TestSentence({
    required this.id,
    required this.text,
    required this.category,
    required this.expect,
    this.rule = '',
    this.section = '',
  });

  final String id, text, category;

  /// ESCALATION (rule must fire), ANSWER (top passage section must contain [section]) or OUT_OF_SCOPE.
  final String expect;
  final String rule, section;

  factory TestSentence.fromJson(Map<String, Object?> j) => TestSentence(
    id: j['id'] as String,
    text: j['text'] as String,
    category: (j['category'] as String?) ?? '',
    expect: j['expect'] as String,
    rule: (j['rule'] as String?) ?? '',
    section: (j['section'] as String?) ?? '',
  );

  /// The expected outcome as written to the CSV, for example "ESCALATION:DSR-FITS" or "ANSWER:Hygiene".
  String get expectedLabel => switch (expect) {
    'ESCALATION' => 'ESCALATION:$rule',
    'ANSWER' => 'ANSWER:$section',
    _ => expect,
  };
}

/// Parses the sentence file (assets/voice_test/sentences.json or the copy on the phone). Throws FormatException on a bad file.
List<TestSentence> parseSentences(String json) {
  final root = jsonDecode(json);
  if (root is! Map || root['sentences'] is! List) {
    throw const FormatException('expected {"sentences": [...]}');
  }
  final out = <TestSentence>[];
  final ids = <String>{};
  for (final e in root['sentences'] as List) {
    final s = TestSentence.fromJson((e as Map).cast<String, Object?>());
    if (!const {'ESCALATION', 'ANSWER', 'OUT_OF_SCOPE'}.contains(s.expect)) {
      throw FormatException('${s.id}: expect must be ESCALATION, ANSWER or OUT_OF_SCOPE');
    }
    if (!ids.add(s.id)) throw FormatException('duplicate id ${s.id}');
    out.add(s);
  }
  if (out.isEmpty) throw const FormatException('no sentences');
  return out;
}
