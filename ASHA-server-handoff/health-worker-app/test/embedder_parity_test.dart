import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/domain/retrieval/embedder.dart';

void main() {
  const e = HashingEmbedder();
  final golden = jsonDecode(
    File('../asha-data/build/golden_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('the Dart embedder reproduces the Python vectors that asha-data/build_data.py wrote (same method on the Mac and the phone)', () {
    expect(golden['embedder'], HashingEmbedder.embedderId);
    expect(golden['dim'], HashingEmbedder.dim);
    final cases = (golden['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases.length, greaterThanOrEqualTo(6));
    var maxDiff = 0.0;
    for (final c in cases) {
      final text = c['text'] as String;
      final want = (c['vector'] as List)
          .map((x) => (x as num).toDouble())
          .toList();
      final got = e.embed(text);
      for (var i = 0; i < HashingEmbedder.dim; i++) {
        final d = (got[i] - want[i]).abs();
        if (d > maxDiff) maxDiff = d;
      }
      final q = e.quantize(got);
      final wantQ = (c['vector_int8'] as List).cast<int>();
      var mismatch = 0;
      for (var i = 0; i < HashingEmbedder.dim; i++) {
        if (q[i] != wantQ[i]) mismatch++;
      }
      expect(mismatch, 0, reason: 'int8 vector differs for "$text"');
    }
    expect(maxDiff, lessThan(1e-9));
  });

  test('empty text gives a zero vector, short text is ignored, vectors are unit length', () {
    expect(e.embed('').every((x) => x == 0), isTrue);
    expect(e.embed('a b').every((x) => x == 0), isTrue);
    final v = e.embed('heavy bleeding');
    expect(v.fold<double>(0, (s, x) => s + x * x), closeTo(1.0, 1e-9));
  });

  test('similar spellings score higher than unrelated text (bleeding / bleding vs fever)', () {
    final a = e.quantize(e.embed('heavy bleeding'));
    expect(
      e.cosine(e.embed('heavy bleding'), a),
      greaterThan(e.cosine(e.embed('high fever'), a)),
    );
    expect(e.cosine(e.embed('heavy bleeding'), a), closeTo(1.0, 0.05));
  });

  test('alias expansion joins English, Telugu and Telugu-in-English-letters (word-boundary safe)', () {
    final ex = AliasExpander.fromJson(
      File('../asha-data/lexicon/aliases.json').readAsStringSync(),
    );
    expect(ex.expand('garbhini ki rakta sravam'), contains('రక్తస్రావం'));
    expect(
      ex.expand('గర్భిణీకి విపరీతమైన రక్తస్రావం అవుతోంది'),
      contains('bleeding'),
    );
    expect(
      ex.expand('How do I record a visit?').contains('umbilical'),
      isFalse,
      reason: '"record" must not match the word "cord"',
    );
    expect(ex.expand('nothing relevant here'), 'nothing relevant here');
  });
}
