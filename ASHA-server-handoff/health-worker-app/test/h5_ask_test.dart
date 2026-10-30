import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/services/qa_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

// Ask with the protocol-book engine on: danger signs escalate, out-of-scope questions are refused, the rest is answered from the book
// with the section it came from. All of it on the phone, no server.
void main() {
  sqfliteFfiInit();

  Future<QaResult> ask(WidgetTester t, String q, {bool offline = true}) async {
    final rig = (await t.runAsync(() => buildRig(configured: false, h5Ask: true, offline: offline)))!;
    return (await t.runAsync(() => rig.services.qa.ask(q)))!;
  }

  testWidgets('a pregnant woman bleeding: escalate, citing ESC-2.1 with its text', (t) async {
    final r = await ask(t, 'garbhvati mahila ko 8 mahine me bahut khoon aa raha hai');
    expect(r.outcome, QaOutcome.escalationRequired);
    expect(r.evidence.map((e) => e.sectionId), contains('ESC-2.1'));
    expect(r.evidence.first.passageText, isNotEmpty);
    expect(r.evidence.first.isVerified, isTrue);
  });

  testWidgets('a newborn that is not feeding: escalate even though no phone word rule would be needed', (t) async {
    final r = await ask(t, 'navjat bachcha dudh nahi pi raha aur sust hai 4 din ka');
    expect(r.outcome, QaOutcome.escalationRequired);
    expect(r.evidence.map((e) => e.sectionId), contains('ESC-4.1'));
  });

  testWidgets('finding the sex of the baby is refused, pointing at SCP-1.2', (t) async {
    final r = await ask(t, 'scan me ladka hai ya ladki batao');
    expect(r.outcome, QaOutcome.outOfScope);
    expect(r.ruleIds, ['SCP-1.2']);
  });

  testWidgets('a vaccine question is answered from the immunisation section, with the text quoted', (t) async {
    final r = await ask(t, 'BCG ka tika kab tak lagwa sakte hain');
    expect(r.outcome, QaOutcome.answeredWithEvidence);
    expect(r.evidence, isNotEmpty);
    expect(r.evidence.first.sectionId, startsWith('IMM-'));
    expect(r.evidence.first.passageText.toLowerCase(), contains('bcg'));
  });

  testWidgets('works the same online and offline (no server is asked)', (t) async {
    final a = await ask(t, 'BCG ka tika kab tak lagwa sakte hain', offline: true);
    final b = await ask(t, 'BCG ka tika kab tak lagwa sakte hain', offline: false);
    expect(a.evidence.map((e) => e.sectionId), b.evidence.map((e) => e.sectionId));
    expect(a.evidence.first.passageText, b.evidence.first.passageText);
  });
}
