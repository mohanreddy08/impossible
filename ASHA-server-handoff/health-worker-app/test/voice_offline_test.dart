import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/presentation/screens/ask_screen.dart';
import 'package:health_companion/services/speech_capabilities.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'voice_test.dart' show FakeVoice, fieldText;

const _onDeviceEnglishOnly = FixedSpeechProbe(
  SpeechCapabilities(
    recognitionAvailable: true,
    onDeviceAvailable: true,
    installed: ['en-US'],
    supportedOnDevice: ['en-US', 'en-IN', 'te-IN'],
    sdk: 34,
  ),
);
const _noOnDeviceEngine = FixedSpeechProbe(
  SpeechCapabilities(
    recognitionAvailable: true,
    onDeviceAvailable: false,
    sdk: 30,
  ),
);

Future<FakeVoice> _open(
  WidgetTester t, {
  required SpeechCapabilityProbe probe,
  bool allowOnline = false,
  bool offline = false,
  String lang = 'en',
}) async {
  final v = FakeVoice();
  final rig = (await t.runAsync(
    () => buildRig(
      configured: false,
      voice: v,
      speechProbe: probe,
      allowOnlineSpeech: allowOnline,
      lang: lang,
    ),
  ))!;
  await pumpApp(t, rig, home: const AskScreen(), size: const Size(412, 1600));
  if (offline) {
    rig.connStream.add([ConnectivityResult.none]);
    await settle(t, maxRounds: 4);
  }
  return v;
}

Future<void> _tapMic(WidgetTester t) async {
  await t.tap(find.byKey(const Key('mic-button')));
  await settle(t, maxRounds: 4);
}

void main() {
  sqfliteFfiInit();

  group('voice policy (pure)', () {
    const both = SpeechCapabilities(
      recognitionAvailable: true,
      onDeviceAvailable: true,
      installed: ['en-US', 'te-IN'],
      supportedOnDevice: ['en-US', 'te-IN'],
    );

    test('installed language -> on the device, with the installed locale (Indian variant preferred)', () {
      final d = decideVoiceRoute(
        both,
        lang: 'te',
        allowOnline: false,
        online: false,
      );
      expect(d.route, VoiceRoute.onDevice);
      expect(d.locale, 'te-IN');
      expect(
        decideVoiceRoute(
          const SpeechCapabilities(
            recognitionAvailable: true,
            onDeviceAvailable: true,
            installed: ['en-US', 'en-IN'],
          ),
          lang: 'en',
          allowOnline: false,
          online: true,
        ).locale,
        'en-IN',
      );
    });

    test('on-device is used even when online and online speech is allowed (nothing leaves the phone if it need not)', () {
      expect(
        decideVoiceRoute(
          both,
          lang: 'en',
          allowOnline: true,
          online: true,
        ).route,
        VoiceRoute.onDevice,
      );
    });

    test('missing pack + online speech OFF -> blocked, never a silent cloud fallback', () {
      final d = decideVoiceRoute(
        _onDeviceEnglishOnly.caps,
        lang: 'te',
        allowOnline: false,
        online: true,
      );
      expect(d.route, VoiceRoute.blocked);
      expect(d.block, VoiceBlock.packMissing);
      expect(
        d.onlineWouldWork,
        isTrue,
        reason: 'the worker is told the option exists',
      );
    });

    test('missing pack + online speech ON + online -> online; + offline -> blocked', () {
      expect(
        decideVoiceRoute(
          _onDeviceEnglishOnly.caps,
          lang: 'te',
          allowOnline: true,
          online: true,
        ).route,
        VoiceRoute.online,
      );
      final off = decideVoiceRoute(
        _onDeviceEnglishOnly.caps,
        lang: 'te',
        allowOnline: true,
        online: false,
      );
      expect(off.route, VoiceRoute.blocked);
      expect(off.onlineWouldWork, isFalse);
    });

    test('no on-device engine (older Android) -> blocked offline, online only with consent', () {
      expect(
        decideVoiceRoute(
          _noOnDeviceEngine.caps,
          lang: 'en',
          allowOnline: false,
          online: true,
        ).block,
        VoiceBlock.noOfflineEngine,
      );
      expect(
        decideVoiceRoute(
          _noOnDeviceEngine.caps,
          lang: 'en',
          allowOnline: true,
          online: true,
        ).route,
        VoiceRoute.online,
      );
    });

    test('no recogniser at all -> blocked', () {
      expect(
        decideVoiceRoute(
          SpeechCapabilities.none,
          lang: 'en',
          allowOnline: true,
          online: true,
        ).block,
        VoiceBlock.noRecognizer,
      );
    });

    test('Android 12 (engine present, languages unknown) -> tries on the device only', () {
      final d = decideVoiceRoute(
        const SpeechCapabilities(
          recognitionAvailable: true,
          onDeviceAvailable: true,
        ),
        lang: 'te',
        allowOnline: false,
        online: false,
      );
      expect(d.route, VoiceRoute.onDevice);
      expect(d.locale, 'te-IN');
    });

    test('capabilities from the Android channel are read safely', () {
      final c = SpeechCapabilities.fromMap({
        'recognitionAvailable': true,
        'onDeviceAvailable': true,
        'installed': ['en-US', 'te-IN'],
        'supportedOnDevice': ['en-US', 'te-IN', 'hi-IN'],
        'sdk': 36,
      });
      expect(c.installedLocale('te'), 'te-IN');
      expect(c.canDownload('en'), isTrue);
      expect(SpeechCapabilities.fromMap({}).recognitionAvailable, isFalse);
    });
  });

  group('Ask screen voice, offline', () {
    uiTest(
      'offline with the Telugu pack installed: listens ON THE DEVICE in te-IN; the privacy line says nothing is sent',
      (t) async {
        final v = await _open(
          t,
          probe: FixedSpeechProbe.allOffline,
          offline: true,
        );
        await t.tap(find.byKey(const Key('voice-lang-te')));
        await t.pump();
        await _tapMic(t);
        expect(v.starts, 1);
        expect(v.offline, isTrue, reason: 'on-device only');
        expect(v.localeId, 'te-IN');
        v.say('గర్భిణీకి రక్తస్రావం', fin: true);
        v.finish();
        await settle(t, maxRounds: 3);
        expect(fieldText(t), 'గర్భిణీకి రక్తస్రావం');
        expect(
          find.text('Possible danger sign'),
          findsNothing,
          reason: 'never submitted by itself',
        );
        expect(
          find.textContaining('turned into text on this phone only'),
          findsOneWidget,
        );
      },
    );

    uiTest(
      'no Telugu offline pack, online speech OFF: does not listen, explains how to get the pack, offers the setting',
      (t) async {
        final v = await _open(t, probe: _onDeviceEnglishOnly);
        await t.tap(find.byKey(const Key('voice-lang-te')));
        await t.pump();
        await _tapMic(t);
        expect(v.starts, 0, reason: 'no silent cloud fallback');
        expect(
          find.textContaining('no offline speech pack for Telugu'),
          findsOneWidget,
        );
        expect(find.textContaining('Online speech'), findsWidgets);
        // typing still works
        expect(
          t.widget<FilledButton>(find.byKey(const Key('ask-button'))).onPressed,
          isNotNull,
        );
      },
    );

    uiTest(
      'no Telugu pack, online speech ON, online: uses the online service and SAYS so',
      (t) async {
        final v = await _open(
          t,
          probe: _onDeviceEnglishOnly,
          allowOnline: true,
        );
        await t.tap(find.byKey(const Key('voice-lang-te')));
        await t.pump();
        await _tapMic(t);
        expect(v.starts, 1);
        expect(v.offline, isFalse);
        v.say('pasi bidda palu tagadam ledu', fin: true);
        v.finish();
        await settle(t, maxRounds: 3);
        expect(
          find.textContaining('audio was sent to that service'),
          findsOneWidget,
        );
      },
    );

    uiTest(
      'no Telugu pack, online speech ON, but OFFLINE: blocked, and the online option is not offered',
      (t) async {
        final v = await _open(
          t,
          probe: _onDeviceEnglishOnly,
          allowOnline: true,
          offline: true,
        );
        await t.tap(find.byKey(const Key('voice-lang-te')));
        await t.pump();
        await _tapMic(t);
        expect(v.starts, 0);
        expect(
          find.textContaining('no offline speech pack for Telugu'),
          findsOneWidget,
        );
        expect(find.textContaining('allow the phone'), findsNothing);
      },
    );

    uiTest(
      'older phone with no on-device engine, offline: clear message, no listening',
      (t) async {
        final v = await _open(t, probe: _noOnDeviceEngine, offline: true);
        await _tapMic(t);
        expect(v.starts, 0);
        expect(
          find.textContaining(
            'cannot recognise English speech without internet',
          ),
          findsOneWidget,
        );
      },
    );

    uiTest(
      'English is fine offline while Telugu is not: the language pills are honoured',
      (t) async {
        final v = await _open(t, probe: _onDeviceEnglishOnly, offline: true);
        await t.tap(find.byKey(const Key('voice-lang-en')));
        await t.pump();
        await _tapMic(t);
        expect(v.starts, 1);
        expect(v.offline, isTrue);
        expect(v.localeId, 'en-US');
      },
    );
  });

  group(
    'voice transcripts still go through the safety engine (regressions)',
    () {
      // Recognisers drop or mishear words. These pin what the deterministic rules do with typical transcripts.
      uiTest('negation, numbers and code-mixed transcripts', (t) async {
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        String status(String q) => rig.services.safety.evaluate(q).status;
        // positive danger signs, as a recogniser typically writes them
        for (final q in [
          'pregnant woman bleeding heavily',
          'pregnant lady ki heavy bleeding avutundi',
          'newborn baby not feeding',
          'baby breathing fast',
          'garbhini ki pitts vastunnayi',
          'గర్భిణీకి రక్తస్రావం ఎక్కువగా ఉంది',
          'the baby has fits',
        ]) {
          expect(status(q), 'ESCALATION_REQUIRED', reason: q);
        }
        // rules v0.3.0: ANY bleeding in pregnancy escalates (not only "heavy")
        expect(
          status('pregnant woman 8 months bleeding'),
          'ESCALATION_REQUIRED',
        );
        // explicit negation of the sign must not escalate
        for (final q in [
          'pregnant woman has no bleeding',
          'there is no bleeding in the pregnant woman',
        ]) {
          expect(status(q), isNot('ESCALATION_REQUIRED'), reason: q);
        }
      });
    },
  );
}
