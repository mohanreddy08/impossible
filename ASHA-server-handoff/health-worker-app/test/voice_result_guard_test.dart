import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/services/voice_input.dart';

// Found on a phone: English voice showed the words, then they vanished. The phone's recogniser sent a second, EMPTY final result and the
// box was overwritten with it.
void main() {
  test('an empty final result after real text does not wipe it', () {
    final g = VoiceResultGuard();
    expect(g.accept('the', false), ('the', false));
    expect(g.accept('the baby is not feeding', false), ('the baby is not feeding', false));
    expect(g.accept('the baby is not feeding well', true), ('the baby is not feeding well', true));
    expect(g.accept('', true), ('the baby is not feeding well', true));
    expect(g.accept('  ', false), isNull);
  });

  test('empty results with nothing recognised are ignored, and a new session starts clean', () {
    final g = VoiceResultGuard();
    expect(g.accept('', false), isNull);
    expect(g.accept('', true), isNull);
    g.accept('fits', true);
    g.reset();
    expect(g.accept('', true), isNull);
  });
}
