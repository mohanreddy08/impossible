import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/voice_test/results_log.dart';
import 'package:health_companion/voice_test/test_sentences.dart';
import 'package:health_companion/voice_test/voice_test_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

// The hidden Voice Test: its 20 sentences, the CSV it writes and the table it prints. The sentence file is only fair if every sentence,
// typed perfectly, passes: then any failure on the phone is the speech engine's, not the sentence's.
void main() {
  sqfliteFfiInit();
  final sentences = parseSentences(
    File('assets/voice_test/sentences.json').readAsStringSync(),
  );

  test('the sentence file has 20 Telugu sentences with unique ids', () {
    expect(sentences, hasLength(20));
    expect(sentences.map((s) => s.id).toSet(), hasLength(20));
    expect(sentences.every((s) => RegExp(r'[ఀ-౿]').hasMatch(s.text)), isTrue);
    expect(sentences.where((s) => s.category.contains('danger')), hasLength(9));
    expect(sentences.where((s) => s.category.contains('drug')), isNotEmpty);
  });

  test('a bad sentence file is refused with a clear message', () {
    expect(() => parseSentences('{}'), throwsFormatException);
    expect(
      () => parseSentences('{"sentences":[{"id":"a","text":"x","expect":"MAYBE"}]}'),
      throwsFormatException,
    );
    expect(
      () => parseSentences(
        '{"sentences":[{"id":"a","text":"x","expect":"ANSWER"},{"id":"a","text":"y","expect":"ANSWER"}]}',
      ),
      throwsFormatException,
    );
  });

  uiTest(
    'every sentence, typed correctly, gets the right danger rule or the right passage (so a phone failure is the speech engine)',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(sampleProtocol: true, aiAssist: false, lang: 'te', offline: true),
      ))!;
      final bad = <String>[];
      for (final s in sentences) {
        final r = (await t.runAsync(() => rig.services.qa.ask(s.text)))!;
        final v = judge(s, r);
        if (!v.dangerOk || !v.qaOk) {
          bad.add('${s.id} ${s.expectedLabel} -> ${r.outcome.name} ${r.ruleIds} ${v.qaTopSection}');
        }
      }
      expect(bad, isEmpty);
    },
  );

  test('the CSV survives commas, quotes and line breaks, and the summary counts the latest rating per take', () async {
    final dir = await Directory.systemTemp.createTemp('voicetest');
    addTearDown(() => dir.delete(recursive: true));
    final log = ResultsLog(File('${dir.path}/voice_test.csv'));
    VoiceTestRow row(String id, String engine, String rating, int ms, {String net = 'online', String text = 'తెలుగు'}) =>
        VoiceTestRow(
          session: 's1',
          startedAtMs: 1,
          endedAtMs: 2,
          network: net,
          sentenceId: id,
          expected: 'ESCALATION:DSR-FITS',
          engine: engine,
          transcript: text,
          msAfterStop: ms,
          audioMs: 1000,
          endedBy: 'user',
          error: '',
          rating: rating,
          dangerFired: 'DSR-FITS',
          dangerOk: true,
          qaOutcome: 'escalationRequired',
          qaTopSection: 'Fits, "seizures"',
          qaOk: rating != 'wrong',
        );
    await log.append(row('d01', 'offline_app', 'wrong', 400, text: 'a, "b"\nc'));
    await log.append(row('d01', 'offline_app', 'correct', 500)); // re-rated: replaces the first
    await log.append(row('d02', 'offline_app', 'some_wrong', 700));
    await log.append(row('d01', 'online', 'correct', 900));
    await log.append(row('d01', 'online', 'correct', 100, net: 'offline'));

    final rows = await log.readAll();
    expect(rows, hasLength(5));
    expect(rows.first.transcript, 'a, "b"\nc');
    expect(rows.first.qaTopSection, 'Fits, "seizures"');
    expect((await log.file.readAsString()).split('\n').first, VoiceTestRow.header.join(','));

    final sums = {for (final s in summarise(rows)) '${s.engine}/${s.network}': s};
    expect(sums['offline_app/online']!.takes, 2);
    expect(sums['offline_app/online']!.correct, 1);
    expect(sums['offline_app/online']!.someWrong, 1);
    expect(sums['offline_app/online']!.wrong, 0);
    expect(sums['offline_app/online']!.avgMs, 600);
    expect(sums['online/online']!.correct, 1);
    expect(sums['online/offline']!.avgMs, 100);
  });
}
