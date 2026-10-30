// Types real Telugu questions into the real Ask page, on the phone, against the live Mac server (settings already saved in the app).
//   flutter test integration_test/telugu_ask_test.dart -d <device>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/main.dart' as app;
import 'package:health_companion/state/app_services.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester t, [int ms = 1200]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Telugu questions on the real Ask page', (t) async {
    await (await SharedPreferences.getInstance()).setBool(
      'onboarding_done',
      true,
    );
    await app.main();
    await settle(t, 3500);
    // a wiped phone: load the synthetic demo data, point the app at the Mac server (over the USB reverse) and turn AI help on
    const server = String.fromEnvironment('ASK_SERVER');
    const key = String.fromEnvironment('ASK_KEY');
    final services = Provider.of<AppServices>(
      t.element(find.byType(Scaffold).first),
      listen: false,
    );
    if (find.byKey(const Key('load-demo')).evaluate().isNotEmpty) {
      await t.tap(find.byKey(const Key('load-demo')));
      await settle(t, 5000);
    }
    if (server.isNotEmpty && key.isNotEmpty) {
      await services.settings.setBaseUrl(server);
      await services.settings.setApiKey(key);
      await services.settings.setAiAssist(true);
      await services.settings.setEscalationPhone('9123456780');
    }
    await t.tap(find.byKey(const ValueKey('nav-2')));
    await settle(t, 1500);

    const qs = [
      'చేతులు ఎలా కడుక్కోవాలి',
      'ఇంట్లో ఎవరూ లేకపోతే ఏం చేయాలి',
      'గర్భిణీకి రక్తస్రావం అవుతోంది',
      'పాప పాలు దాగట్లేదు',
      'చిన్న పిల్ల వడికి జ్వరముగా ఉంది తీవ్రంగా',
      'ఈ యాంటీబయాటిక్ మోతాదు ఎంత',
      'మలేరియాకు చికిత్స ఏమిటి',
      'బిడ్డకు టీకా ఎప్పుడు వేయాలి',
    ];
    for (final q in qs) {
      await t.enterText(find.byKey(const Key('question-field')), q);
      await t.pump();
      await t.tap(find.byKey(const Key('ask-button')));
      await t.pump();
      // real network: wait up to 12 s for the Check button to come back
      for (var i = 0; i < 120; i++) {
        await t.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (i > 5 && find.text('Checking…').evaluate().isEmpty) break;
      }
      await settle(t, 800);
      final sev = [
        for (final k in ['severity-high', 'severity-medium', 'severity-low'])
          if (find.byKey(Key(k)).evaluate().isNotEmpty) k,
      ];
      final expl =
          find.byKey(const Key('explanation-text')).evaluate().isNotEmpty
          ? (t
                    .widget<SelectableText>(
                      find.byKey(const Key('explanation-text')),
                    )
                    .data ??
                '')
          : '-';
      final src =
          find.byKey(const Key('explanation-source')).evaluate().isNotEmpty
          ? t.widget<Text>(find.byKey(const Key('explanation-source'))).data
          : '-';
      // ignore: avoid_print
      print(
        'TELUGU-RESULT | $q | sev=$sev | escalation=${find.byKey(const Key('escalation-card')).evaluate().isNotEmpty} | src=$src | expl=${expl.length > 90 ? expl.substring(0, 90) : expl}',
      );
    }
  });
}
