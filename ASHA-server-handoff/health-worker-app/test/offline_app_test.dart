// The whole app in OFFLINE TEST MODE: the phone reports no connection and every HTTP request fails (buildRig(offline: true, aiAssist: false)).
// A server address and key ARE configured, so any screen that quietly tried the network would show up in requestPaths.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/presentation/app_shell.dart';
import 'package:health_companion/presentation/launch/launch_gate.dart';
import 'package:health_companion/services/field_work_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

Future<void> _tab(WidgetTester t, int i) async {
  await t.tap(find.byKey(ValueKey('nav-$i')));
  await settle(t, maxRounds: 10);
}

Future<void> _back(WidgetTester t) async {
  t.state<NavigatorState>(find.byType(Navigator).last).pop();
  await settle(t, maxRounds: 8);
}

Future<void> _ask(WidgetTester t, String q) async {
  await t.enterText(find.byKey(const Key('question-field')), q);
  await t.tap(find.byKey(const Key('ask-button')));
  await settle(
    t,
    until: () => find.text('Checking…').evaluate().isEmpty,
    maxRounds: 30,
  );
  await settle(t, maxRounds: 6);
}

void main() {
  sqfliteFfiInit();

  uiTest(
    'the app starts offline and every local screen opens; no network request is attempted',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(offline: true, aiAssist: false),
      ))!;
      // the real start-up gate (onboarding check -> app), without waiting out the splash animation
      await pumpApp(
        t,
        rig,
        home: const LaunchGate(splashFor: Duration.zero),
        size: const Size(412, 1400),
      );
      await settle(t, maxRounds: 20);
      expect(find.textContaining('Offline'), findsWidgets);
      expect(find.text('NEXT VISIT'), findsOneWidget);

      await _tab(t, 1);
      expect(find.text('Visit planner'), findsOneWidget);
      expect(find.text('Overdue'), findsWidgets);

      await _tab(t, 2);
      expect(find.text('Ask a health question'), findsOneWidget);

      await _tab(t, 3);
      expect(find.textContaining('households on this phone'), findsOneWidget);

      await _tab(t, 4);
      for (final (item, shows) in [
        ('Referrals', 'Attendance is only shown as confirmed'),
        ('Reports', 'Summary from this phone'),
        ('Sync centre', 'Waiting to send'),
        ('Settings', 'Language'),
      ]) {
        await t.tap(find.text(item).last);
        await settle(t, maxRounds: 10);
        expect(find.textContaining(shows), findsWidgets, reason: item);
        await _back(t);
      }
      expect(
        rig.server.requestPaths,
        isEmpty,
        reason: 'offline screens must not try the network',
      );
      expect(t.takeException(), isNull);
    },
  );

  uiTest(
    'a visit and a referral recorded offline are saved, counted as waiting, and nothing is sent',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(offline: true, aiAssist: false),
      ))!;
      final s = rig.services;
      final today = s.clock.today();
      final v = (await t.runAsync(
        () => s.store.plannedVisits('today', today, limit: 1),
      ))!.first.visit;
      await t.runAsync(
        () => s.fieldWork.recordOutcome(
          v.visitId,
          VisitOutcome(
            status: 'COMPLETED',
            actualDate: today,
            referral: const ReferralDraft(
              facilityId: 'FAC-SYN-01',
              serviceCategory: 'GENERAL',
            ),
          ),
        ),
      );
      // the app refreshes the waiting count after every save; wait for that here
      await t.runAsync(() => s.sync.refresh());
      expect(
        (await t.runAsync(() => s.store.visit(v.visitId)))!.status,
        'COMPLETED',
      );
      final c = (await t.runAsync(() => s.store.outboxCounts()))!;
      expect((c.pending, c.synced), (2, 0));
      await pumpApp(
        t,
        rig,
        home: const AppShell(),
        size: const Size(412, 1400),
      );
      expect(find.textContaining('2 waiting to sync'), findsWidgets);
      // pressing Sync now while offline keeps everything queued
      await _tab(t, 4);
      await t.tap(find.text('Sync centre').last);
      await settle(t, maxRounds: 10);
      expect(
        find.bySemanticsLabel(RegExp('Waiting to send: 2')),
        findsOneWidget,
      );
      expect((await t.runAsync(() => s.store.outboxCounts()))!.pending, 2);
    },
  );

  uiTest(
    'Ask works offline: danger sign escalates, a protocol question cites the sample, a dose request is refused, nothing is sent',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(offline: true, sampleProtocol: true, aiAssist: false),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AppShell(),
        size: const Size(412, 3000),
      );
      await _tab(t, 2);

      await _ask(t, 'The newborn is not feeding properly');
      expect(find.byKey(const Key('escalation-card')), findsOneWidget);

      await _ask(t, 'What are the danger signs in pregnancy?');
      expect(find.byKey(const Key('evidence-unverified')), findsWidgets);
      expect(find.textContaining('Danger signs in pregnancy'), findsWidgets);

      await _ask(t, 'What dose of paracetamol should I give a baby?');
      expect(find.byKey(const Key('notice-outOfScope')), findsOneWidget);

      await _ask(t, 'What is the capital of France');
      expect(
        find.byKey(const Key('notice-insufficientEvidence')),
        findsOneWidget,
      );

      expect(rig.server.requestPaths, isEmpty);
    },
  );

  uiTest(
    'switching to Telugu works offline and the Ask page answers in Telugu',
    (t) async {
      final rig = (await t.runAsync(
        () => buildRig(offline: true, sampleProtocol: true, aiAssist: false),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AppShell(),
        size: const Size(412, 3000),
      );
      await t.runAsync(() => rig.services.settings.setLanguage('te'));
      await settle(t, maxRounds: 10);
      await _tab(t, 2);
      expect(find.text('ఆరోగ్య ప్రశ్న అడగండి'), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('question-field')),
        'garbhini ki pitts vastunnayi',
      );
      await t.tap(find.byKey(const Key('ask-button')));
      await settle(t, maxRounds: 30);
      expect(find.byKey(const Key('escalation-card')), findsOneWidget);
      expect(find.text('ప్రమాద సంకేతం కావచ్చు'), findsWidgets);
      expect(rig.server.requestPaths, isEmpty);
    },
  );
}
