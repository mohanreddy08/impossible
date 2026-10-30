import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'support/fake_server.dart';

List<Map<String, dynamic>> _jsonl(String path) => [
  for (final l in File(path).readAsLinesSync())
    if (l.trim().isNotEmpty) jsonDecode(l) as Map<String, dynamic>,
];

/// The core promise: with the online helpers off (the default), the Ask page gives the SAME result with a working server
/// as with no network at all, for every sample question, and never calls the server's /query.
void main() {
  sqfliteFfiInit();

  uiTest(
    'same outcome and same evidence online (server up) as offline (server down), and the server is never asked',
    (t) async {
      final qs = [
        ..._jsonl('../asha-data/questions/questions.jsonl'),
        ..._jsonl('../asha-data/questions/questions_heldout.jsonl'),
      ];
      final online = (await t.runAsync(
        () => buildRig(sampleProtocol: true, aiAssist: false),
      ))!;
      // a server that WOULD answer anything, so any dependence on it would change the result
      online.server.qaQuery = qaJson(
        'ANSWERED_WITH_EVIDENCE',
        answer: 'server answer',
      );
      final offline = (await t.runAsync(
        () => buildRig(sampleProtocol: true, aiAssist: false),
      ))!;
      offline.server.down = true;
      var checked = 0;
      for (final q in qs) {
        final text = q['question_text'] as String;
        final a = (await t.runAsync(() => online.services.qa.ask(text)))!;
        final b = (await t.runAsync(() => offline.services.qa.ask(text)))!;
        expect(a.outcome, b.outcome, reason: text);
        expect(
          [for (final e in a.evidence) '${e.documentId}#${e.sectionId}'],
          [for (final e in b.evidence) '${e.documentId}#${e.sectionId}'],
          reason: text,
        );
        // the explanation is the same too: the phone's own explainer, whether or not a connection exists
        final ea = await t.runAsync(() => online.services.qa.explain(text, a));
        final eb = await t.runAsync(
          () => offline.services.qa.explain(text, b, online: false),
        );
        expect(ea?.text, eb?.text, reason: text);
        expect(ea?.source, eb?.source, reason: text);
        checked++;
      }
      expect(checked, qs.length);
      expect(
        online.server.requestPaths.where((p) => p.contains('health-qa')),
        isEmpty,
        reason: 'with AI help off the app never contacts the server to answer',
      );
    },
  );

  uiTest('turning the optional helper ON is what makes the server get asked', (
    t,
  ) async {
    final rig = (await t.runAsync(
      () => buildRig(sampleProtocol: true, aiAssist: true),
    ))!;
    rig.server.qaQuery = qaJson('INSUFFICIENT_EVIDENCE');
    await t.runAsync(
      () => rig.services.qa.ask('zxqv unrelated question about tractors'),
    );
    expect(
      rig.server.requestPaths.where((p) => p.contains('health-qa/query')),
      isNotEmpty,
    );
  });
}
