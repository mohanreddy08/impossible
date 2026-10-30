import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/services/qa_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

// Telugu questions against the phone's own approved text. Found on a phone: "చేతులు ఎలా కడుక్కోవాలి" (how do I wash my hands) and
// "గర్భిణీ స్త్రీలో ప్రమాద సంకేతాలు ఏమిటి" (what are the danger signs in a pregnant woman) found nothing, although the sample document
// has Telugu passages for both: the search ignored too few Telugu question words and matched only exactly spelled words.
void main() {
  sqfliteFfiInit();
  uiTest(
    'Telugu questions find the right approved text, in more than one wording and spelling',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(
          sampleProtocol: true,
          aiAssist: false,
          lang: 'te',
          offline: true,
        ),
      ))!;
      Future<List<String>> found(String q) async {
        final r = (await t.runAsync(() => rig.services.qa.ask(q)))!;
        expect(r.outcome, QaOutcome.answeredWithEvidence, reason: q);
        return [for (final e in r.evidence) '${e.documentId}#${e.sectionId}'];
      }

      // hand washing: a verb ending that differs from the passage (కడుక్కోవాలి / కడుక్కోవడం vs కడుక్కోండి)
      for (final q in [
        'చేతులు ఎలా కడుక్కోవాలి',
        'చేతులు కడుక్కోవడం ఎలా',
        'సబ్బుతో చేతులు కడుక్కోండి',
      ]) {
        expect(
          await found(q),
          contains('SAMPLE-APP-WORKFLOW#hand-washing'),
          reason: q,
        );
      }

      // pregnancy danger signs: question words (ఏమిటి), word endings (స్త్రీలో) and both spellings of గర్భిణీ / గర్భిణి
      for (final q in [
        'గర్భిణీ స్త్రీలో ప్రమాద సంకేతాలు ఏమిటి',
        'గర్భిణి స్త్రీలో ప్రమాద సంకేతాలు ఏమిటి',
        'గర్భిణీ ప్రమాద సంకేతాలు',
      ]) {
        final ev = await found(q);
        expect(ev, isNotEmpty, reason: q);
        expect(
          ev.every((e) => e.startsWith('SAMPLE-PREG-DANGER')),
          isTrue,
          reason: '$q -> $ev',
        );
      }

      // newborn danger signs
      final nb = await found('నవజాత శిశువు ప్రమాద సంకేతాలు ఏమిటి');
      expect(
        nb.every((e) => e.startsWith('SAMPLE-NEWBORN-DANGER')),
        isTrue,
        reason: '$nb',
      );

      expect(
        await found('ఇంట్లో ఎవరూ లేకపోతే ఏమి చేయాలి'),
        contains('SAMPLE-APP-WORKFLOW#not-at-home'),
      );
    },
  );

  uiTest(
    'stem matching does not invent answers: unrelated or all-question-word Telugu questions find nothing',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(
          sampleProtocol: true,
          aiAssist: false,
          lang: 'te',
          offline: true,
        ),
      ))!;
      for (final q in [
        'ఫ్రాన్స్ రాజధాని ఏమిటి',
        'ఏమిటి',
        'ఎలా చేయాలి',
        'క్రికెట్ మ్యాచ్ ఎప్పుడు మొదలవుతుంది',
      ]) {
        final r = (await t.runAsync(() => rig.services.qa.ask(q)))!;
        expect(r.evidence, isEmpty, reason: q);
        expect(r.outcome, isNot(QaOutcome.answeredWithEvidence), reason: q);
      }
    },
  );
}
