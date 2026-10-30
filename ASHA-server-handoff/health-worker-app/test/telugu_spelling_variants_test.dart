import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

// A speech recogniser (or a worker) can spell the same Telugu word in more than one way. Found on a phone: the spoken sentence
// "the baby has trouble breathing" was once written with స్వాసా instead of శ్వాస and the rules saw no danger sign.
void main() {
  sqfliteFfiInit();
  uiTest(
    'spelling variants of danger words raise the alarm; their "no problem" forms do not',
    (t) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      String status(String q) => rig.services.safety.evaluate(q).status;

      for (final q in [
        // breathing: శ్వాస / స్వాస / స్వాసా, ఇబ్బంది / కష్టం, ఊపిరి / ఉపిరి, ఊపిరాడటం
        'బిడ్డకు శ్వాస తీసుకోవడంలో ఇబ్బంది ఉంది',
        'బిద్దకు స్వాసా తీసుకోవడంలో ఇబ్బంది ఉంది',
        'బిడ్డకు స్వాస తీసుకోవడంలో ఇబ్బంది ఉంది',
        'బిద్దకు శవాస తీసుకోవడంలో ఇబ్బంది ఉంది',
        'బిడ్డకు శ్వాస తీసుకోవడం కష్టంగా ఉంది',
        'బిడ్డకు ఊపిరి తీసుకోవడం కష్టంగా ఉంది',
        'బిడ్డకు ఉపిరి ఆడటం లేదు',
        'బిడ్డకు ఊపిరి ఆడటం లేదు',
        'బిడ్డకు ఊపిరి ఆడడం లేదు',
        'ఊపిరి ఆడటం లేదు',
        'బిడ్డ శ్వాస తీసుకోవడం లేదు',
        'బిడ్డకు ఊపిరాడటం లేదు',
        'బిడ్డ వేగంగా శ్వాస తీసుకుంటోంది',
        'బిడ్డ స్వాస గబగబా తీసుకుంటోంది',
        // fits: మూర్ఛ / మూర్చ, ఫిట్స్ / ఫిట్లు
        'బిడ్డకు మూర్చ వచ్చింది',
        'బిడ్డకు ఫిట్లు వచ్చాయి',
        // unconscious: స్పృహ / సృహ
        'ఆమె సృహ తప్పి పడిపోయింది',
        'అతను స్పృహ లేకుండా పడి ఉన్నాడు',
        // heavy bleeding: రక్తస్రావం / రక్తశ్రావం
        'గర్భిణీకి రక్తశ్రావం ఎక్కువగా ఉంది',
        'గర్భిణీకి ఎక్కువ రక్త స్రావం అవుతోంది',
      ]) {
        expect(status(q), 'ESCALATION_REQUIRED', reason: q);
      }

      for (final q in [
        'బిడ్డకు శ్వాసలో ఇబ్బంది లేదు',
        'బిడ్డకు స్వాస తీసుకోవడంలో ఇబ్బంది లేదు',
        'బిడ్డకు మూర్చ లేదు',
        'బిడ్డకు ఊపిరి తీసుకోవడంలో ఇబ్బంది లేదు',
        'ఆమెకు సృహ తప్పలేదు',
        'రక్తశ్రావం లేదు',
      ]) {
        expect(status(q), isNot('ESCALATION_REQUIRED'), reason: q);
      }
    },
  );
}
