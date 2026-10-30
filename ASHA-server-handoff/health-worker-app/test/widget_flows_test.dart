import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/data/local/local_store.dart';
import 'package:health_companion/data/models/outbox_op.dart';
import 'package:health_companion/presentation/app_shell.dart';
import 'package:health_companion/presentation/screens/households_screen.dart';
import 'package:health_companion/presentation/screens/planner_screen.dart';
import 'package:health_companion/presentation/screens/settings_screen.dart';
import 'package:health_companion/presentation/screens/visit_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

void main() {
  sqfliteFfiInit();

  group('home dashboard and navigation', () {
    uiTest(
      'shows today / overdue / upcoming / open referrals computed from local data, and the offline-first status chip',
      (t) async {
        final rig = await t.runAsync(() => buildRig());
        await pumpApp(t, rig!, home: const AppShell());
        final counts = await t.runAsync(
          () => rig.services.store.dashboard(rig.services.clock.today()),
        );
        await settle(
          t,
          until: () => find.text('Due today').evaluate().isNotEmpty,
        );
        expect(find.text("What's on your list today?"), findsOneWidget);
        expect(find.text('Due today'), findsWidgets);
        expect(find.text('Overdue'), findsWidgets);
        expect(find.text('Open referrals'), findsOneWidget);
        expect(find.text('${counts!.overdue}'), findsWidgets);
        expect(
          counts.overdue + counts.dueToday + counts.upcoming,
          greaterThan(0),
        );
        expect(
          find.text('Demo data (synthetic)'),
          findsNothing,
          reason: 'the demo badge was removed from Home',
        );
        expect(find.text('Online'), findsOneWidget);
        expect(find.text('All changes synced'), findsOneWidget);
      },
    );

    uiTest('empty database offers demo data instead of a blank screen', (
      t,
    ) async {
      final rig = await t.runAsync(() => buildRig(demo: false));
      await pumpApp(t, rig!, home: const AppShell());
      await settle(
        t,
        until: () => find.byKey(const Key('load-demo')).evaluate().isNotEmpty,
      );
      expect(find.text('No household data on this phone yet'), findsOneWidget);
      await t.tap(find.byKey(const Key('load-demo')));
      await settle(
        t,
        until: () => find.text('Due today').evaluate().isNotEmpty,
      );
      expect(find.text('Open referrals'), findsOneWidget);
    });

    uiTest('bottom navigation reaches every main tab', (t) async {
      final rig = await t.runAsync(() => buildRig());
      await pumpApp(t, rig!, home: const AppShell());
      await t.tap(find.byKey(const ValueKey('nav-1')));
      await settle(t);
      expect(find.text('Visit planner'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('nav-2')));
      await settle(t);
      expect(find.text('Ask a health question'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('nav-3')));
      await settle(t);
      expect(find.text('Search by household ID'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('nav-4')));
      await settle(t);
      expect(find.byKey(const Key('more-settings')), findsOneWidget);
    });
  });

  group('visit planner', () {
    uiTest(
      'lists planned visits with the reason each is on the list; overdue tab is ordered most-overdue first',
      (t) async {
        final rig = await t.runAsync(() => buildRig());
        await pumpApp(t, rig!, home: const PlannerScreen(initialTab: 0));
        await settle(
          t,
          until: () =>
              find.textContaining('follow-up was due').evaluate().isNotEmpty,
        );
        expect(find.textContaining('follow-up was due'), findsWidgets);
        expect(
          find.text(
            'Ordered by due date: most overdue first. No risk score is used.',
          ),
          findsOneWidget,
        );
        final list = await t.runAsync(
          () => rig.services.store.plannedVisits(
            'overdue',
            rig.services.clock.today(),
            limit: 50,
          ),
        );
        final dates = list!.map((e) => e.visit.scheduledDate).toList();
        expect(dates, orderedEquals([...dates]..sort()));
        expect(dates.length, greaterThan(1));
      },
    );
  });

  group('record a visit (form validation and offline save)', () {
    Future<String> firstPlannedVisit(AppRig rig, WidgetTester t) async =>
        (await t.runAsync(
          () => rig.services.store.plannedVisits(
            'today',
            rig.services.clock.today(),
            limit: 1,
          ),
        ))!.first.visit.visitId;

    uiTest(
      'missing follow-up date shows a plain-language error and saves nothing',
      (t) async {
        final rig = (await t.runAsync(() => buildRig()))!;
        final id = await firstPlannedVisit(rig, t);
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
        await t.tap(find.byKey(const Key('followup-switch')));
        await t.pump();
        await t.tap(find.byKey(const Key('save-visit')));
        await settle(
          t,
          until: () => find
              .text('Choose the date of the next visit.')
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('Choose the date of the next visit.'), findsOneWidget);
        expect(
          (await t.runAsync(() => rig.services.store.outboxCounts()))!.pending,
          0,
        );
        expect(
          (await t.runAsync(() => rig.services.store.visit(id)))!.status,
          'PLANNED',
        );
      },
    );

    uiTest(
      'saving works with no server: stored locally, queued, and the user is told it will be sent later',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        final id = await firstPlannedVisit(rig, t);
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
        final v = (await t.runAsync(() => rig.services.store.visit(id)))!;
        expect(v.status, 'COMPLETED');
        final ops = (await t.runAsync(() => rig.services.store.ops()))!;
        expect(ops.length, 1);
        expect(ops.single.state, OpState.pending);
        expect(
          rig.server.requestPaths,
          isEmpty,
          reason: 'nothing needs the network to save',
        );
      },
    );

    uiTest(
      'a referral can only be recommended (never planned/attended) from the form',
      (t) async {
        final rig = (await t.runAsync(() => buildRig()))!;
        final id = await firstPlannedVisit(rig, t);
        await pumpApp(
          t,
          rig,
          home: VisitScreen(visitId: id),
          size: const Size(412, 2600),
        );
        await settle(
          t,
          until: () =>
              find.byKey(const Key('referral-switch')).evaluate().isNotEmpty,
        );
        await t.tap(find.byKey(const Key('referral-switch')));
        await t.pump();
        await t.tap(find.byKey(const Key('save-visit')));
        await settle(
          t,
          until: () => find.byKey(const Key('save-visit')).evaluate().isEmpty,
        );
        final ops = (await t.runAsync(() => rig.services.store.ops()))!;
        final r = ops.firstWhere((o) => o.entityType == 'referral');
        expect(r.payload['referral_status'], 'RECOMMENDED');
        expect(r.payload.containsKey('attendance_record_id'), isFalse);
        expect(r.payload.containsKey('planned_visit_date'), isFalse);
        await flushAutoSync(t);
      },
    );
  });

  group('household register', () {
    uiTest('pages through the register, searches and filters locally', (
      t,
    ) async {
      final rig = (await t.runAsync(() => buildRig()))!;
      await pumpApp(t, rig, home: const HouseholdsScreen());
      await settle(
        t,
        until: () => find.byType(HouseholdTile).evaluate().isNotEmpty,
      );
      expect(find.byType(HouseholdTile), findsWidgets);
      expect(find.text('80 households on this phone'), findsOneWidget);
      final first = (await t.runAsync(
        () => rig.services.store.pageHouseholds(
          const HouseholdFilter(),
          limit: 1,
        ),
      ))!.first.householdId;
      await t.enterText(find.byKey(const Key('household-search')), first);
      await settle(
        t,
        until: () =>
            find.byKey(ValueKey('hh-$first')).evaluate().isNotEmpty &&
            find.byType(HouseholdTile).evaluate().length == 1,
        maxRounds: 40,
      );
      expect(find.byType(HouseholdTile), findsOneWidget);
      await t.tap(find.byKey(ValueKey('hh-$first')));
      await settle(
        t,
        until: () => find.text('Schedule a visit').evaluate().isNotEmpty,
      );
      // the house-location and phone-number cards sit above the visit history, so scroll down to it
      await t.scrollUntilVisible(find.text('Visit history'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Visit history'), findsOneWidget);
      expect(find.text('Schedule a visit'), findsOneWidget);
    });
  });

  group('settings', () {
    uiTest('language switch changes the whole UI to Telugu and back', (
      t,
    ) async {
      final rig = (await t.runAsync(() => buildRig()))!;
      await pumpApp(
        t,
        rig,
        home: const SettingsScreen(),
        size: const Size(412, 3200),
      );
      await t.tap(find.byKey(const Key('lang-te')));
      await settle(t);
      expect(find.text('సెట్టింగ్స్'), findsWidgets);
      expect(find.text('సర్వర్ చిరునామా'), findsOneWidget);
      await t.tap(find.byKey(const Key('lang-en')));
      await settle(t);
      expect(find.text('Server address'), findsOneWidget);
    });

    uiTest(
      'server address is validated; plain http to a remote host is warned about; the key is masked and not shown back',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        await pumpApp(
          t,
          rig,
          home: const SettingsScreen(),
          size: const Size(412, 3200),
        );
        await t.enterText(find.byKey(const Key('server-url')), 'not a url');
        await t.tap(find.byKey(const Key('save-server')));
        await t.pump(const Duration(milliseconds: 400));
        expect(
          find.text('Enter a full address starting with http:// or https://'),
          findsOneWidget,
        );
        await t.enterText(
          find.byKey(const Key('server-url')),
          'http://health.example.org',
        );
        await t.pump();
        expect(find.textContaining('plain http'), findsOneWidget);
        await t.enterText(
          find.byKey(const Key('server-url')),
          'https://health.example.org',
        );
        await t.enterText(find.byKey(const Key('api-key')), 'super-secret-key');
        await t.tap(find.byKey(const Key('save-server')));
        await settle(t);
        expect(rig.services.settings.baseUrl, 'https://health.example.org');
        expect(rig.services.settings.hasApiKey, isTrue);
        expect(find.text('super-secret-key'), findsNothing);
        final field = t.widget<TextField>(find.byKey(const Key('api-key')));
        expect(field.obscureText, isTrue);
        expect(field.controller!.text, isEmpty);
      },
    );

    uiTest(
      'clear all data asks first, then removes everything including queued changes',
      (t) async {
        final rig = (await t.runAsync(() => buildRig()))!;
        await pumpApp(
          t,
          rig,
          home: const SettingsScreen(),
          size: const Size(412, 3200),
        );
        await t.tap(find.byKey(const Key('clear-data')));
        await t.pumpAndSettle();
        expect(
          find.textContaining('Unsent changes will be lost'),
          findsOneWidget,
        );
        await t.tap(find.text('Discard'));
        await settle(t);
        final counts = (await t.runAsync(
          () => rig.services.store.rowCounts(),
        ))!;
        expect(counts['households'], 0);
        expect(counts['sync_outbox'], 0);
      },
    );

    uiTest(
      'protocol library says plainly that no approved protocol text is installed',
      (t) async {
        final rig = (await t.runAsync(() => buildRig()))!;
        await pumpApp(
          t,
          rig,
          home: const SettingsScreen(),
          size: const Size(412, 4200),
        );
        await settle(
          t,
          until: () => find
              .textContaining('No approved protocol text')
              .evaluate()
              .isNotEmpty,
        );
        expect(
          find.textContaining('No approved protocol text is installed yet'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Not clinically validated. Draft safety rules, synthetic data.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('(not clinically validated)'),
          findsOneWidget,
        );
      },
    );
  });
}
