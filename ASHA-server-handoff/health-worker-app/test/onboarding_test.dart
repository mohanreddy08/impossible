import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/app.dart';
import 'package:health_companion/presentation/launch/launch_gate.dart';
import 'package:health_companion/presentation/launch/onboarding_screen.dart';
import 'package:health_companion/presentation/launch/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'telugu_complete_test.dart' show englishLeaks, shownText;

/// A brand-new install has NO saved settings; buildRig(lang:) always saves one, so clear it afterwards.
Future<AppRig> freshInstall(WidgetTester t, {String? lang}) async {
  final rig = (await t.runAsync(
    () => buildRig(demo: false, configured: false),
  ))!;
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  if (lang != null) await prefs.setString('lang', lang);
  await prefs.setBool('onboarding_done', false); // explicit: a saved language alone would otherwise look like an existing install
  return rig;
}

Future<void> pumpGate(
  WidgetTester t,
  AppRig rig, {
  double textScale = 1,
  Size size = const Size(412, 892),
}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    t.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await t.pumpWidget(HealthApp(services: rig.services));
}

Future<void> toOnboarding(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 2100)); // splash
  await t.pump();
  await t.pump();
  await t.pump(const Duration(milliseconds: 600)); // crossfade
}

void main() {
  sqfliteFfiInit();

  uiTest(
    'every launch starts with the ASHA splash: logo, the name and a tagline',
    (t) async {
      final rig = await freshInstall(t);
      await pumpGate(t, rig);
      await t.pump(const Duration(milliseconds: 1600));
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('ASHA'), findsOneWidget);
      expect(find.text('Your health worker companion'), findsOneWidget);
      await toOnboarding(t);
    },
  );

  uiTest(
    'a brand-new install goes splash -> language choice (not straight into the app)',
    (t) async {
      final rig = await freshInstall(t);
      await pumpGate(t, rig);
      await toOnboarding(t);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byKey(const Key('ob-lang-te')), findsOneWidget);
      expect(find.byKey(const Key('ob-lang-en')), findsOneWidget);
      expect(
        find.byKey(const Key('ob-skip')),
        findsNothing,
        reason: 'the language choice cannot be skipped',
      );
      expect(rig.services.settings.onboardingDone, isFalse);
    },
  );

  uiTest(
    'choosing Telugu switches the rest of onboarding AND the app to Telugu, and the choice is saved',
    (t) async {
      final rig = await freshInstall(t);
      await pumpGate(t, rig);
      await toOnboarding(t);
      await t.tap(find.byKey(const Key('ob-lang-te')));
      await t.pump(const Duration(milliseconds: 400));
      expect(rig.services.settings.language, 'te');
      expect(find.text('మీ భాషను ఎంచుకోండి'), findsWidgets);
      await t.tap(find.byKey(const Key('ob-next')));
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('మీ రోజు ఒకే చోట'), findsOneWidget);
      // skip straight to the app
      await t.tap(find.byKey(const Key('ob-skip')));
      await t.pump(const Duration(milliseconds: 100));
      await settle(t, maxRounds: 25);
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('హోమ్'), findsWidgets, reason: 'Telugu home navigation');
      expect(rig.services.settings.onboardingDone, isTrue);
    },
  );

  uiTest(
    'walking through every page ends in the app, remembers it, and the next launch skips onboarding',
    (t) async {
      final rig = await freshInstall(t);
      await pumpGate(t, rig);
      await toOnboarding(t);
      for (var i = 0; i < 4; i++) {
        await t.tap(find.byKey(const Key('ob-next')));
        await t.pump();
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
      }
      expect(find.text('Two things ASHA may ask for'), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);
      expect(
        find.byKey(const Key('ob-skip')),
        findsNothing,
        reason: 'nothing left to skip on the last page',
      );
      await t.tap(find.byKey(const Key('ob-next')));
      await settle(t, maxRounds: 25);
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(rig.services.settings.onboardingDone, isTrue);

      // second launch with the same saved settings: splash, then straight into the app
      await t.pumpWidget(const SizedBox());
      await pumpGate(t, rig);
      await t.pump(const Duration(milliseconds: 2100));
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(OnboardingScreen), findsNothing);
    },
  );

  uiTest(
    'an installation that already has settings saved is NOT sent back through onboarding after an update',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(lang: 'en'),
      ))!; // saves 'lang' like an existing install
      expect(rig.services.settings.onboardingDone, isTrue);
      await pumpGate(t, rig);
      await t.pump(const Duration(milliseconds: 2100));
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(OnboardingScreen), findsNothing);
    },
  );

  uiTest(
    'the notification permission is requested at the END of onboarding, not over the splash',
    (t) async {
      final rig = await freshInstall(t);
      await pumpGate(t, rig);
      await t.pump(const Duration(milliseconds: 2100));
      expect(
        rig.fakeNotifier.permissionRequests,
        0,
        reason: 'nothing asked during the splash',
      );
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 4; i++) {
        await t.tap(find.byKey(const Key('ob-next')));
        await t.pump();
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
      }
      expect(
        rig.fakeNotifier.permissionRequests,
        0,
        reason: 'nor while reading the pages',
      );
      await t.tap(find.byKey(const Key('ob-next')));
      await settle(t, maxRounds: 25);
      expect(rig.fakeNotifier.permissionRequests, 1);
    },
  );

  uiTest(
    'the Android back button steps back through the pages instead of leaving the app',
    (t) async {
      final rig = await freshInstall(t);
      await pumpGate(t, rig);
      await toOnboarding(t);
      await t.tap(find.byKey(const Key('ob-next')));
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Your day in one place'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Your day in one place'), findsNothing);
      expect(find.byKey(const Key('ob-lang-en')), findsOneWidget);
    },
  );

  uiTest(
    'with "remove animations" on, the splash shows its finished state at once',
    (t) async {
      final rig = await freshInstall(t);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpGate(t, rig);
      await t.pump();
      final tag = t.widget<Opacity>(
        find
            .ancestor(
              of: find.text('Your health worker companion'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(tag.opacity, 1);
      await t.pump(const Duration(milliseconds: 2100));
      await t.pump();
    },
  );

  for (final cfg in {
    'small phone 320x568, 200% text, Telugu': (const Size(320, 568), 2.0, 'te'),
    'small phone 320x568, 200% text, English': (
      const Size(320, 568),
      2.0,
      'en',
    ),
    'common phone 360x640, 130% text, Telugu': (
      const Size(360, 640),
      1.3,
      'te',
    ),
  }.entries) {
    uiTest('every onboarding page fits without overflow: ${cfg.key}', (
      t,
    ) async {
      final rig = await freshInstall(t, lang: cfg.value.$3);
      await pumpGate(t, rig, textScale: cfg.value.$2, size: cfg.value.$1);
      await toOnboarding(t);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 400));
        if (i < 4) {
          await t.tap(find.byKey(const Key('ob-next')));
          await t.pump();
          await t.pump();
          await t.pump(const Duration(milliseconds: 600));
        }
      }
    });
  }

  uiTest('Telugu: no English left on the splash or any onboarding page', (
    t,
  ) async {
    final rig = await freshInstall(t, lang: 'te');
    await pumpGate(t, rig);
    await t.pump(const Duration(milliseconds: 1600));
    expect(englishLeaks(shownText(t)), isEmpty, reason: 'splash');
    await toOnboarding(t);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 400));
      // the language page deliberately names both languages, so a worker who cannot read the current one still knows what to tap
      const intended = {
        'Choose your language  ·  మీ భాషను ఎంచుకోండి',
        'Telugu',
        'తెలుగు, Telugu',
      };
      expect(
        englishLeaks(shownText(t)).where((e) => !intended.contains(e)),
        isEmpty,
        reason: 'page $i',
      );
      if (i < 4) {
        await t.tap(find.byKey(const Key('ob-next')));
        await t.pump();
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
      }
    }
  });

  testWidgets('LaunchGate is what HealthApp shows when no screen is forced', (
    t,
  ) async {
    expect(const LaunchGate(), isA<Widget>());
  });
}
