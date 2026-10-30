import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

// Everyday ways a worker types or says "the baby cannot breathe properly". Found on a phone: "suffering to breath" only asked for details.
void main() {
  sqfliteFfiInit();
  uiTest('lay wording for breathing trouble escalates; denial does not', (
    t,
  ) async {
    final rig = (await t.runAsync(() => buildRig(configured: false)))!;
    String status(String q) => rig.services.safety.evaluate(q).status;
    for (final q in [
      'newborn baby is suffering to breath right now',
      'the baby is gasping',
      'baby cannot breathe',
      "child can't breathe properly",
      'newborn is breathing hard',
      'baby is breathing heavily',
      'she is short of breath',
      'newborn struggling to breathe',
    ]) {
      expect(status(q), 'ESCALATION_REQUIRED', reason: q);
    }
    for (final q in [
      'the baby has no breathing problem',
      'there is no difficulty in breathing',
    ]) {
      expect(status(q), isNot('ESCALATION_REQUIRED'), reason: q);
    }
  });
}
