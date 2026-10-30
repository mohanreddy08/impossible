import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/presentation/app_shell.dart';
import 'package:health_companion/presentation/screens/ask_screen.dart';
import 'package:health_companion/presentation/screens/households_screen.dart';
import 'package:health_companion/presentation/screens/planner_screen.dart';
import 'package:health_companion/presentation/screens/referrals_screen.dart';
import 'package:health_companion/presentation/screens/reports_screen.dart';
import 'package:health_companion/presentation/screens/settings_screen.dart';
import 'package:health_companion/presentation/screens/sync_screen.dart';
import 'package:health_companion/presentation/screens/visit_screen.dart';
import 'package:health_companion/presentation/widgets/common.dart';
import 'package:health_companion/services/field_work_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

Future<String> firstVisitId(AppRig rig, WidgetTester t) async =>
    (await t.runAsync(
      () => rig.services.store.plannedVisits(
        'overdue',
        rig.services.clock.today(),
        limit: 1,
      ),
    ))!.first.visit.visitId;

void main() {
  sqfliteFfiInit();

  // (name, builder) for every screen. Visit form needs an id, so it is built after the rig exists.
  final screens = <String, Widget Function(String visitId)>{
    'home (shell)': (_) => const AppShell(),
    'planner': (_) => const PlannerScreen(initialTab: 0),
    'households': (_) => const HouseholdsScreen(),
    'ask': (_) => const AskScreen(),
    'referrals': (_) => const ReferralsScreen(),
    'reports': (_) => const ReportsScreen(),
    'sync centre': (_) => const SyncScreen(),
    'settings': (_) => const SettingsScreen(),
    'visit form': (id) => VisitScreen(visitId: id),
  };

  final configs = <String, (Size, double, String)>{
    'small phone 320x568, 200% text, English': (
      const Size(320, 568),
      2.0,
      'en',
    ),
    'small phone 320x568, 200% text, Telugu': (const Size(320, 568), 2.0, 'te'),
    'common phone 360x640, 130% text, Telugu': (
      const Size(360, 640),
      1.3,
      'te',
    ),
  };

  for (final cfg in configs.entries) {
    group('no overflow or crash: ${cfg.key}', () {
      for (final sc in screens.entries) {
        uiTest(sc.key, (t) async {
          final rig = (await t.runAsync(() => buildRig(lang: cfg.value.$3)))!;
          final id = await firstVisitId(rig, t);
          await pumpApp(
            t,
            rig,
            home: sc.value(id),
            size: cfg.value.$1,
            textScale: cfg.value.$2,
          );
          await settle(t, maxRounds: 25);
          // exercise scrolling to the bottom of whatever list is shown: lazily built rows must lay out too
          final scrollables = find.byType(Scrollable);
          if (scrollables.evaluate().isNotEmpty) {
            await t.drag(scrollables.first, const Offset(0, -3000));
            await settle(t, maxRounds: 6);
          }
        });
      }
    });
  }

  group('accessibility guidelines', () {
    Future<void> check(
      WidgetTester t,
      Widget home, {
      bool contrast = true,
      bool seed = true,
      Size size = const Size(412, 892),
    }) async {
      final sem = t.ensureSemantics();
      final rig = (await t.runAsync(() => buildRig(demo: seed)))!;
      await pumpApp(t, rig, home: home, size: size);
      await settle(t, maxRounds: 25);
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      if (contrast) await expectLater(t, meetsGuideline(textContrastGuideline));
      sem.dispose();
    }

    uiTest(
      'home: tap targets are large enough and labelled; text contrast passes',
      (t) => check(t, const AppShell()),
    );
    uiTest('planner', (t) => check(t, const PlannerScreen(initialTab: 0)));
    uiTest('households', (t) => check(t, const HouseholdsScreen()));
    uiTest('referrals', (t) => check(t, const ReferralsScreen()));
    uiTest('sync centre', (t) => check(t, const SyncScreen()));
    uiTest(
      'settings',
      (t) => check(t, const SettingsScreen(), size: const Size(412, 2200)),
    );
    uiTest('ask (before asking)', (t) => check(t, const AskScreen()));

    uiTest(
      'escalation result: the warning is exposed to screen readers as a live region with a header',
      (t) async {
        final sem = t.ensureSemantics();
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        await pumpApp(
          t,
          rig,
          home: const AskScreen(),
          size: const Size(412, 1400),
        );
        await t.enterText(
          find.byKey(const Key('question-field')),
          'Pregnant woman is bleeding heavily right now',
        );
        await t.tap(find.byKey(const Key('ask-button')));
        await settle(
          t,
          until: () =>
              find.byKey(const Key('escalation-card')).evaluate().isNotEmpty,
          maxRounds: 30,
        );
        await settle(t, maxRounds: 6);
        expect(find.byKey(const Key('escalation-card')), findsOneWidget);
        final live = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        );
        expect(live, findsWidgets);
        final header = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.header == true &&
              w.child is Text &&
              (w.child as Text).data == 'Possible danger sign',
        );
        expect(header, findsOneWidget);
        await expectLater(t, meetsGuideline(textContrastGuideline));
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        sem.dispose();
      },
    );

    uiTest(
      'status is never colour-only: every status badge carries an icon AND words',
      (t) async {
        final rig = (await t.runAsync(() => buildRig()))!;
        await pumpApp(t, rig, home: const HouseholdsScreen());
        await settle(
          t,
          until: () => find.byType(StatusBadge).evaluate().isNotEmpty,
        );
        final badges = find
            .byType(StatusBadge)
            .evaluate()
            .map((e) => e.widget as StatusBadge)
            .toList();
        expect(badges, isNotEmpty);
        for (final b in badges) {
          expect(b.label.trim(), isNotEmpty);
          expect(b.icon, isA<IconData>());
        }
      },
    );
  });

  group('Telugu', () {
    uiTest('navigation, headings and dates render in Telugu', (t) async {
      final rig = (await t.runAsync(() => buildRig(lang: 'te')))!;
      await pumpApp(t, rig, home: const AppShell());
      await settle(t, until: () => find.text('హోమ్').evaluate().isNotEmpty);
      for (final s in [
        'హోమ్',
        'సందర్శనలు',
        'అడగండి',
        'ఇళ్లు',
        'మరిన్ని',
        'ఈ రోజు మీ జాబితాలో ఏముంది?',
      ]) {
        expect(find.text(s), findsWidgets, reason: s);
      }
      await t.tap(find.byKey(const ValueKey('nav-3')));
      await settle(
        t,
        until: () => find.byType(HouseholdTile).evaluate().isNotEmpty,
      );
      final teChars = RegExp(r'[ఀ-౿]');
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .toList();
      expect(
        texts.any((s) => s.contains('తదుపరి సందర్శన') && teChars.hasMatch(s)),
        isTrue,
        reason: 'household tile shows Telugu label + localised date',
      );
    });

    uiTest(
      'Telugu, English and mixed text can be typed into the question box and are kept intact',
      (t) async {
        final rig = (await t.runAsync(
          () => buildRig(configured: false, lang: 'te'),
        ))!;
        await pumpApp(t, rig, home: const AskScreen());
        for (final q in [
          'గర్భిణీ స్త్రీకి ANC చెకప్ ఎన్ని సార్లు చేయాలి?',
          'When is the next ANC visit due?',
          'ORS packet ని ఎంత water లో mix చేయాలి?',
          'garbhini ki ANC checkup enni sarlu cheyali?',
        ]) {
          await t.enterText(find.byKey(const Key('question-field')), q);
          expect(
            t
                .widget<TextField>(find.byKey(const Key('question-field')))
                .controller!
                .text,
            q,
          );
        }
      },
    );
  });

  group('automatic sending', () {
    uiTest(
      'a saved visit is sent automatically after a short delay when online; nothing is called synced until acknowledged',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(autoSync: true)))!;
        final id = await firstVisitId(rig, t);
        await pumpApp(
          t,
          rig,
          home: VisitScreen(visitId: id),
          size: const Size(412, 2600),
        );
        await settle(
          t,
          until: () =>
              find.byKey(const Key('save-visit')).evaluate().isNotEmpty,
        );
        await t.tap(find.byKey(const Key('save-visit')));
        await settle(
          t,
          until: () => find.byKey(const Key('save-visit')).evaluate().isEmpty,
        );
        expect(
          rig.server.pushCalls,
          0,
          reason: 'debounced: not sent instantly',
        );
        expect(
          (await t.runAsync(() => rig.services.store.outboxCounts()))!.pending,
          greaterThan(0),
        );
        await t.pump(const Duration(seconds: 3));
        await settle(t, until: () => rig.server.pushCalls > 0, maxRounds: 40);
        await settle(t, maxRounds: 15);
        expect(rig.server.pushCalls, 1);
        final c = (await t.runAsync(() => rig.services.store.outboxCounts()))!;
        expect((c.pending, c.synced > 0), (0, true));
      },
    );

    uiTest(
      'when the server is unreachable the auto-send fails quietly, keeps everything pending and does not claim success',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(autoSync: true)))!;
        rig.server.down = true;
        final id = await firstVisitId(rig, t);
        await pumpApp(
          t,
          rig,
          home: VisitScreen(visitId: id),
          size: const Size(412, 2600),
        );
        await settle(
          t,
          until: () =>
              find.byKey(const Key('save-visit')).evaluate().isNotEmpty,
        );
        await t.tap(find.byKey(const Key('save-visit')));
        await settle(
          t,
          until: () => find.byKey(const Key('save-visit')).evaluate().isEmpty,
        );
        await t.pump(const Duration(seconds: 3));
        await settle(
          t,
          until: () =>
              !rig.services.sync.syncing &&
              rig.services.sync.lastReport != null,
          maxRounds: 40,
        );
        final c = (await t.runAsync(() => rig.services.store.outboxCounts()))!;
        expect((c.synced, c.pending > 0), (0, true));
        expect(rig.services.sync.link.name, 'unreachable');
        expect(
          await t.runAsync(() => rig.services.store.meta('last_sync_at')),
          isNull,
        );
      },
    );

    uiTest('regaining connectivity triggers an upload of waiting changes', (
      t,
    ) async {
      final rig = (await t.runAsync(() => buildRig(autoSync: true)))!;
      final id = await firstVisitId(rig, t);
      rig.server.down = true;
      await t.runAsync(
        () => rig.services.fieldWork.recordOutcome(
          id,
          _complete(rig.services.clock.today()),
        ),
      );
      await pumpApp(t, rig, home: const AppShell());
      rig.connStream.add([ConnectivityResult.none]);
      await settle(t, maxRounds: 5);
      rig.server.down = false;
      rig.connStream.add([ConnectivityResult.wifi]);
      await settle(t, maxRounds: 5);
      await t.pump(const Duration(seconds: 3));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2400)),
      ); // the debounce timer lives in the real-async zone
      await settle(t, until: () => rig.server.pushCalls > 0, maxRounds: 40);
      await settle(t, maxRounds: 15);
      expect(
        (await t.runAsync(() => rig.services.store.outboxCounts()))!.pending,
        0,
      );
    });
  });
}

VisitOutcome _complete(DateTime today) => VisitOutcome(
  status: 'COMPLETED',
  actualDate: today,
  followupRequired: false,
);
