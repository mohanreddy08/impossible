import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/presentation/screens/settings_screen.dart';
import 'package:health_companion/services/keyboard_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'telugu_complete_test.dart' show englishLeaks, shownText;

// "Alternative way to get Telugu voice": a button in Settings next to the Telugu voice download, opening a steps screen for the
// Google keyboard's own voice typing.
Future<void> _openHelp(WidgetTester t, {String lang = 'en'}) async {
  final rig = (await t.runAsync(() => buildRig(lang: lang)))!;
  await pumpApp(
    t,
    rig,
    home: const SettingsScreen(),
    size: const Size(412, 4200),
  );
  await settle(t, maxRounds: 6);
  await t.ensureVisible(find.byKey(const Key('alt-voice-button')));
  await t.tap(find.byKey(const Key('alt-voice-button')));
  await settle(t, maxRounds: 10);
}

void main() {
  sqfliteFfiInit();
  final original = KeyboardSettings.open;
  tearDown(() => KeyboardSettings.open = original);

  uiTest(
    'Settings has the button next to the Telugu voice download, and it opens the steps screen',
    (t) async {
      final rig = (await t.runAsync(() => buildRig()))!;
      await pumpApp(
        t,
        rig,
        home: const SettingsScreen(),
        size: const Size(412, 4200),
      );
      await settle(t, maxRounds: 6);
      expect(find.text('Alternative way to get Telugu voice'), findsOneWidget);
      // it sits right after the Telugu voice card
      final card = t.getTopLeft(find.byKey(const Key('telugu-model'))).dy;
      final button = t.getTopLeft(find.byKey(const Key('alt-voice-button'))).dy;
      expect(button, greaterThan(card));
      expect(button - card, lessThan(600));
      await t.ensureVisible(find.byKey(const Key('alt-voice-button')));
      await t.tap(find.byKey(const Key('alt-voice-button')));
      await settle(t, maxRounds: 10);
      expect(find.byKey(const Key('telugu-keyboard-help')), findsOneWidget);
      expect(
        find.text('Telugu voice with the Google keyboard'),
        findsOneWidget,
      );
    },
  );

  uiTest(
    'the steps screen lists every step in order: keyboard settings, languages, add Telugu, voice typing, speak, check',
    (t) async {
      await _openHelp(t);
      final list = find.byKey(const Key('telugu-keyboard-help'));
      for (var i = 1; i <= 7; i++) {
        await t.scrollUntilVisible(
          find.byKey(Key('alt-step-$i')),
          200,
          scrollable: find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first,
        );
        expect(find.byKey(Key('alt-step-$i')), findsOneWidget);
      }
      expect(find.text('Open your phone\'s Settings'), findsOneWidget);
      expect(find.text('Find the keyboard settings'), findsOneWidget);
      expect(find.text('Add Telugu'), findsOneWidget);
      expect(find.textContaining('Voice typing'), findsWidgets);
      // honest about what this route is
      await t.scrollUntilVisible(
        find.byKey(const Key('alt-voice-note')),
        200,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      expect(find.textContaining('Google\'s service'), findsOneWidget);
      expect(find.textContaining('audio goes to Google'), findsOneWidget);
      expect(find.textContaining('Download Telugu voice'), findsOneWidget);
    },
  );

  uiTest(
    '"Open keyboard settings" asks the phone to open them; if it cannot, the screen says so',
    (t) async {
      var calls = 0;
      KeyboardSettings.open = () async {
        calls++;
        return calls > 1;
      };
      await _openHelp(t);
      final btn = find.byKey(const Key('alt-open-keyboard-settings'));
      await t.ensureVisible(btn);
      await t.tap(btn);
      await settle(t, maxRounds: 6);
      expect(calls, 1);
      expect(find.byKey(const Key('alt-open-failed')), findsOneWidget);
      await t.tap(btn);
      await settle(t, maxRounds: 6);
      expect(calls, 2);
      expect(find.byKey(const Key('alt-open-failed')), findsNothing);
    },
  );

  uiTest(
    'Telugu: the button and the whole steps screen are in Telugu, no English words left',
    (t) async {
      await _openHelp(t, lang: 'te');
      expect(find.text('గూగుల్ కీబోర్డ్‌తో తెలుగు వాయిస్'), findsOneWidget);
      expect(englishLeaks(shownText(t)), isEmpty);
      final list = find.byKey(const Key('telugu-keyboard-help'));
      await t.scrollUntilVisible(
        find.byKey(const Key('alt-voice-note')),
        200,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      expect(englishLeaks(shownText(t)), isEmpty);
    },
  );
}
