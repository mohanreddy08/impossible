import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/domain/retrieval/local_retrieval.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// Proof that the app's search really uses the stored vectors of the (fictional) sample document, and what they add over keywords alone.
/// A measurement on the sample question set only; nothing is tuned from it.
void main() {
  sqfliteFfiInit();
  uiTest(
    'the app loads one stored vector per sample passage, and search uses them',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(configured: false, sampleProtocol: true),
      ))!;
      final idx = (await t.runAsync(() => rig.services.library.loadIndex()))!;
      final rows = (await t.runAsync(
        () => rig.services.store.db.rawQuery(
          'SELECT COUNT(*) AS n, MIN(LENGTH(vec)) AS len FROM passage_vectors',
        ),
      ))!;
      final stored = rows.first['n'] as int;
      // ignore: avoid_print
      print(
        'passages searchable: ${idx.size}, vectors in table: $stored, bytes per vector: ${rows.first['len']}',
      );
      expect(idx.size, greaterThan(0));
      expect(idx.vectors, isNotNull);
      expect(
        idx.vectors!.length,
        idx.size,
        reason: 'every passage has a vector',
      );
      expect(stored, greaterThanOrEqualTo(idx.size));
      expect(rows.first['len'], 512);

      // same passages, vectors switched off: keyword-only
      final kwOnly = LocalRetrieval(
        idx.passages,
        eligible: idx.eligible,
        aliases: idx.aliases,
      );
      final qs = [
        for (final l in File(
          '../asha-data/questions/questions.jsonl',
        ).readAsLinesSync())
          if (l.trim().isNotEmpty) jsonDecode(l) as Map<String, dynamic>,
      ];
      final key = {
        for (final l in File(
          '../asha-data/questions/answers_hidden.jsonl',
        ).readAsLinesSync())
          if (l.trim().isNotEmpty)
            (jsonDecode(l) as Map<String, dynamic>)['question_id'] as String:
                jsonDecode(l) as Map<String, dynamic>,
      };
      var n = 0, withVec = 0, without = 0;
      for (final q in qs) {
        final h = key[q['question_id']]!;
        final anchors = (h['expected_anchors'] as List).cast<String>();
        if (anchors.isEmpty) continue;
        n++;
        final want = {
          for (final a in anchors) '${h['expected_document_id']}#$a',
        };
        bool hit(LocalRetrieval r) => r
            .search(q['question_text'] as String)
            .any(
              (m) => want.contains(
                '${m.passage.documentId}#${m.passage.sectionId}',
              ),
            );
        if (hit(idx)) withVec++;
        if (hit(kwOnly)) without++;
      }
      // ignore: avoid_print
      print(
        'answerable dev questions: $n, found in top 3 WITH vectors: $withVec, keyword-only: $without',
      );
      expect(withVec, greaterThanOrEqualTo(without));
    },
  );
}
