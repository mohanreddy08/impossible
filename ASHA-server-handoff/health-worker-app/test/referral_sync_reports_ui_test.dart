import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/data/models/outbox_op.dart';
import 'package:health_companion/presentation/screens/referrals_screen.dart';
import 'package:health_companion/presentation/screens/reports_screen.dart';
import 'package:health_companion/presentation/screens/sync_screen.dart';
import 'package:health_companion/services/field_work_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'support/builders.dart';
import 'support/fake_server.dart';

Future<void> seedReferrals(AppRig rig, WidgetTester t) => t.runAsync(() async {
  final s = rig.services.store;
  await s.upsertHouseholds([hh('HH-1')], respectPending: false);
  await s.upsertVisits([
    vis(
      'VIS-A',
      'HH-1',
      DateTime(2026, 9, 1),
      status: 'COMPLETED',
      actual: DateTime(2026, 9, 1),
    ),
  ], respectPending: false);
  await s.upsertReferrals([
    ref(
      'REF-REC',
      'HH-1',
      'VIS-A',
      status: 'RECOMMENDED',
      created: DateTime(2026, 9, 2),
    ),
    ref(
      'REF-PLN',
      'HH-1',
      'VIS-A',
      status: 'PLANNED',
      planned: DateTime(2026, 10, 20),
      created: DateTime(2026, 9, 3),
      cat: 'ANC',
    ),
    ref(
      'REF-CONF',
      'HH-1',
      'VIS-A',
      status: 'ATTENDANCE_CONFIRMED',
      confirmed: true,
      record: 'ATT-777',
      planned: DateTime(2026, 9, 20),
      created: DateTime(2026, 9, 4),
    ),
    // inconsistent data: flagged confirmed but NO attendance record -> must NOT be shown as attended
    ref(
      'REF-FLAG',
      'HH-1',
      'VIS-A',
      status: 'ATTENDANCE_CONFIRMED',
      confirmed: true,
      planned: DateTime(2026, 9, 20),
      created: DateTime(2026, 9, 5),
    ),
    ref(
      'REF-CAN',
      'HH-1',
      'VIS-A',
      status: 'PLANNED',
      state: 'CANCELLED',
      planned: DateTime(2026, 9, 25),
      created: DateTime(2026, 9, 6),
    ),
    ref(
      'REF-DUP',
      'HH-1',
      'VIS-A',
      status: 'RECOMMENDED',
      state: 'DUPLICATE',
      created: DateTime(2026, 9, 7),
    ),
  ], respectPending: false);
});

void main() {
  sqfliteFfiInit();

  group('referral status accuracy', () {
    uiTest(
      'each state has its own wording; ONLY a real attendance record reads as attended',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(demo: false)))!;
        await seedReferrals(rig, t);
        await pumpApp(
          t,
          rig,
          home: const ReferralsScreen(),
          size: const Size(412, 2400),
        );
        await settle(
          t,
          until: () => find.byType(ReferralTile).evaluate().length == 6,
        );
        expect(find.byType(ReferralTile), findsNWidgets(6));
        expect(
          find.text('Hospital attendance confirmed (hospital record)'),
          findsOneWidget,
        );
        expect(
          find.text('Planned — attendance NOT confirmed'),
          findsNWidgets(2),
          reason: 'planned + the flagged-but-recordless one',
        );
        expect(find.text('Recommended — not yet planned'), findsOneWidget);
        expect(find.text('Referral cancelled'), findsOneWidget);
        expect(find.text('Duplicate record (not counted)'), findsOneWidget);
        expect(
          find.textContaining(
            'Recommending or planning a referral does not mean the person went.',
          ),
          findsOneWidget,
        );
      },
    );

    uiTest(
      'the "attendance confirmed" filter lists only records with an attendance record',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(demo: false)))!;
        await seedReferrals(rig, t);
        await pumpApp(
          t,
          rig,
          home: const ReferralsScreen(),
          size: const Size(412, 2400),
        );
        await settle(
          t,
          until: () => find.byType(ReferralTile).evaluate().length == 6,
        );
        await t.drag(
          find.byType(ListView).first,
          const Offset(-500, 0),
        ); // chips scroll horizontally
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.byKey(const ValueKey('ref-filter-confirmed')));
        await settle(
          t,
          until: () => find.byType(ReferralTile).evaluate().length == 1,
        );
        expect(find.byType(ReferralTile), findsOneWidget);
        expect(find.byKey(const ValueKey('ref-REF-CONF')), findsOneWidget);
        await t.drag(find.byType(ListView).first, const Offset(500, 0));
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.byKey(const ValueKey('ref-filter-pending')));
        await settle(
          t,
          until: () => find.byType(ReferralTile).evaluate().length == 3,
        );
        expect(
          find.byType(ReferralTile),
          findsNWidgets(3),
          reason: 'recommended + planned + the recordless one; cancelled/duplicate excluded',
        );
      },
    );

    uiTest(
      'a planned referral: attendance step is "not yet", and there is no way to confirm attendance from the app',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(demo: false)))!;
        await seedReferrals(rig, t);
        await pumpApp(
          t,
          rig,
          home: const ReferralDetailScreen(referralId: 'REF-PLN'),
          size: const Size(412, 1400),
        );
        await settle(
          t,
          until: () => find
              .text('Attendance confirmed by hospital')
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('Planned — attendance NOT confirmed'), findsOneWidget);
        expect(find.text('done'), findsNWidgets(2)); // recommended + planned
        expect(find.text('not yet'), findsOneWidget); // hospital attendance
        expect(find.byKey(const Key('plan-referral')), findsOneWidget);
        expect(find.byKey(const Key('cancel-referral')), findsOneWidget);
        expect(find.textContaining('Confirm attendance'), findsNothing);
        expect(find.textContaining('Mark as attended'), findsNothing);
      },
    );

    uiTest(
      'a confirmed referral shows its hospital record and cannot be edited or cancelled',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(demo: false)))!;
        await seedReferrals(rig, t);
        await pumpApp(
          t,
          rig,
          home: const ReferralDetailScreen(referralId: 'REF-CONF'),
          size: const Size(412, 1400),
        );
        await settle(
          t,
          until: () => find.textContaining('ATT-777').evaluate().isNotEmpty,
        );
        expect(
          find.text('Hospital attendance confirmed (hospital record)'),
          findsOneWidget,
        );
        expect(find.text('Hospital record: ATT-777'), findsOneWidget);
        expect(find.text('done'), findsNWidgets(3));
        expect(find.byKey(const Key('plan-referral')), findsNothing);
        expect(find.byKey(const Key('cancel-referral')), findsNothing);
      },
    );

    uiTest(
      'planning a recommended referral works offline, stays "NOT confirmed", and is marked as not yet synced',
      (t) async {
        final rig = (await t.runAsync(
          () => buildRig(demo: false, configured: false),
        ))!;
        await seedReferrals(rig, t);
        await pumpApp(
          t,
          rig,
          home: const ReferralDetailScreen(referralId: 'REF-REC'),
          size: const Size(412, 1400),
        );
        await settle(
          t,
          until: () =>
              find.byKey(const Key('plan-referral')).evaluate().isNotEmpty,
        );
        await t.tap(find.byKey(const Key('plan-referral')));
        await t.pumpAndSettle();
        await t.tap(find.text('OK'));
        await settle(
          t,
          until: () => find
              .text('Planned — attendance NOT confirmed')
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('Planned — attendance NOT confirmed'), findsOneWidget);
        expect(
          find.text('Not yet synced').evaluate().isNotEmpty ||
              find.text('Not synced yet').evaluate().isNotEmpty,
          isTrue,
        );
        final op = (await t.runAsync(() => rig.services.store.ops()))!.single;
        expect(op.payload['referral_status'], 'PLANNED');
        expect(op.payload.containsKey('attendance_record_id'), isFalse);
        expect(
          find.text('Hospital attendance confirmed (hospital record)'),
          findsNothing,
        );
      },
    );

    uiTest('cancelling asks for confirmation first', (t) async {
      final rig = (await t.runAsync(
        () => buildRig(demo: false, configured: false),
      ))!;
      await seedReferrals(rig, t);
      await pumpApp(
        t,
        rig,
        home: const ReferralDetailScreen(referralId: 'REF-REC'),
        size: const Size(412, 1400),
      );
      await settle(
        t,
        until: () =>
            find.byKey(const Key('cancel-referral')).evaluate().isNotEmpty,
      );
      await t.tap(find.byKey(const Key('cancel-referral')));
      await t.pumpAndSettle();
      expect(find.textContaining('Cancel this referral?'), findsOneWidget);
      await t.tap(find.text('No'));
      await t.pumpAndSettle();
      expect((await t.runAsync(() => rig.services.store.ops()))!, isEmpty);
      await t.tap(find.byKey(const Key('cancel-referral')));
      await t.pumpAndSettle();
      await t.tap(find.text('Yes'));
      await settle(
        t,
        until: () => find.text('Referral cancelled').evaluate().isNotEmpty,
      );
      expect(find.text('Referral cancelled'), findsOneWidget);
    });
  });

  group('sync centre', () {
    Future<AppRig> pendingRig(WidgetTester t, {bool configured = true}) async {
      final rig = (await t.runAsync(
        () => buildRig(demo: false, configured: configured),
      ))!;
      await t.runAsync(() async {
        final r = await Future.value(rig.services);
        await r.store.upsertHouseholds([
          hh('HH-1', status: 'DUE_TODAY', next: today),
        ], respectPending: false);
        await r.store.upsertVisits([
          vis('VIS-1', 'HH-1', today),
        ], respectPending: false);
        await r.fieldWork.recordOutcome(
          'VIS-1',
          VisitOutcome(
            status: 'COMPLETED',
            actualDate: today,
            followupRequired: true,
            nextFollowupDate: DateTime(2026, 11, 12),
          ),
        );
      });
      return rig;
    }

    uiTest(
      'pending changes are listed and NOT called synced until the server acknowledges them',
      (t) async {
        final rig = await pendingRig(t);
        await pumpApp(
          t,
          rig,
          home: const SyncScreen(),
          size: const Size(412, 1600),
        );
        await settle(
          t,
          until: () => find.text('Waiting to send').evaluate().length > 1,
        );
        expect(find.text('Visit result'), findsOneWidget);
        expect(find.text('New visit'), findsOneWidget);
        expect(find.textContaining('Sync finished'), findsNothing);
        expect(
          find.text(
            'A change is only \'synced\' after the server confirms it.',
          ),
          findsOneWidget,
        );
        await t.tap(find.byKey(const Key('sync-now')));
        await settle(
          t,
          until: () =>
              find.textContaining('Sync finished').evaluate().isNotEmpty,
          maxRounds: 40,
        );
        expect(
          find.text('Sync finished: 2 changes confirmed by the server.'),
          findsOneWidget,
        );
        final c = (await t.runAsync(() => rig.services.store.outboxCounts()))!;
        expect((c.pending, c.synced), (0, 2));
      },
    );

    uiTest(
      'offline: plain-language banner, nothing marked synced, data kept, attempts shown',
      (t) async {
        final rig = await pendingRig(t);
        rig.server.down = true;
        await pumpApp(
          t,
          rig,
          home: const SyncScreen(),
          size: const Size(412, 1600),
        );
        await settle(
          t,
          until: () => find.byKey(const Key('sync-now')).evaluate().isNotEmpty,
        );
        await t.tap(find.byKey(const Key('sync-now')));
        await settle(
          t,
          until: () =>
              find.textContaining('No connection').evaluate().isNotEmpty,
          maxRounds: 40,
        );
        expect(
          find.textContaining(
            'No connection. Your changes are saved on this phone',
          ),
          findsWidgets,
        );
        expect(find.textContaining('Sync finished'), findsNothing);
        await settle(
          t,
          until: () => find.text('Tried 1 times').evaluate().length == 2,
        );
        expect(find.text('Tried 1 times'), findsNWidgets(2));
        expect(
          (await t.runAsync(() => rig.services.store.outboxCounts()))!.pending,
          2,
        );
        expect(
          (await t.runAsync(() => rig.services.store.visit('VIS-1')))!.status,
          'COMPLETED',
        );
      },
    );

    uiTest('credentials rejected (401): says so, keeps data', (t) async {
      final rig = await pendingRig(t);
      rig.server.httpStatus = 401;
      await pumpApp(
        t,
        rig,
        home: const SyncScreen(),
        size: const Size(412, 1600),
      );
      await settle(
        t,
        until: () => find.byKey(const Key('sync-now')).evaluate().isNotEmpty,
      );
      await t.tap(find.byKey(const Key('sync-now')));
      await settle(
        t,
        until: () => find
            .textContaining('did not accept your access key')
            .evaluate()
            .isNotEmpty,
        maxRounds: 40,
      );
      expect(
        find.textContaining('Your data is safe on this phone'),
        findsOneWidget,
      );
      expect(
        (await t.runAsync(() => rig.services.store.outboxCounts()))!.pending,
        2,
      );
    });

    uiTest('no server configured: explained, nothing is sent', (t) async {
      final rig = await pendingRig(t, configured: false);
      await pumpApp(
        t,
        rig,
        home: const SyncScreen(),
        size: const Size(412, 1600),
      );
      await settle(
        t,
        until: () => find.byKey(const Key('sync-now')).evaluate().isNotEmpty,
      );
      await t.tap(find.byKey(const Key('sync-now')));
      await settle(
        t,
        until: () => find
            .textContaining('No server address is set')
            .evaluate()
            .isNotEmpty,
        maxRounds: 40,
      );
      expect(rig.server.requestPaths, isEmpty);
    });

    uiTest(
      'a rejected change is shown as failed with the server reason, can be retried',
      (t) async {
        final rig = await pendingRig(t);
        final ops = (await t.runAsync(() => rig.services.store.ops()))!;
        rig.server.forceResult[ops.first.opId] = {
          'status': 'REJECTED',
          'acknowledged': false,
          'error_code': 'NOT_FOUND',
          'error_message': 'household not found',
        };
        await pumpApp(
          t,
          rig,
          home: const SyncScreen(),
          size: const Size(412, 1800),
        );
        await settle(
          t,
          until: () => find.byKey(const Key('sync-now')).evaluate().isNotEmpty,
        );
        await t.tap(find.byKey(const Key('sync-now')));
        await settle(
          t,
          until: () =>
              find.textContaining('Nothing was lost').evaluate().isNotEmpty,
          maxRounds: 40,
        );
        expect(find.text('Rejected by server'), findsWidgets);
        expect(find.text('household not found'), findsOneWidget);
        expect(
          find.text(
            'Some changes were not accepted by the server. Nothing was lost: they are listed below.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('Sync finished'),
          findsNothing,
          reason: 'no green success banner while something is rejected',
        );
        rig.server.forceResult.clear();
        await t.tap(find.byKey(ValueKey('retry-${ops.first.opId}')));
        await settle(
          t,
          until: () => find.text('household not found').evaluate().isEmpty,
        );
        expect(
          (await t.runAsync(() => rig.services.store.op(ops.first.opId)))!
              .state,
          OpState.pending,
        );
      },
    );

    uiTest('a conflict is explained, both values shown, and the user decides', (
      t,
    ) async {
      final rig = (await t.runAsync(() => buildRig(demo: false)))!;
      await t.runAsync(() async {
        final s = rig.services.store;
        await s.upsertHouseholds([hh('HH-1')], respectPending: false);
        await s.upsertVisits([
          vis(
            'VIS-A',
            'HH-1',
            DateTime(2026, 9, 1),
            status: 'COMPLETED',
            actual: DateTime(2026, 9, 1),
          ),
        ], respectPending: false);
        await s.upsertReferrals([
          ref(
            'REF-X',
            'HH-1',
            'VIS-A',
            status: 'RECOMMENDED',
            created: DateTime(2026, 9, 2),
          ),
        ], respectPending: false);
        await rig.services.fieldWork.planReferral(
          'REF-X',
          DateTime(2026, 10, 20),
        );
      });
      final id = (await t.runAsync(() => rig.services.store.ops()))!
          .single
          .opId;
      rig.server.forceResult[id] = conflictResult(
        id,
        serverVersion: 3,
        server: {'referral_status': 'ATTENDANCE_CONFIRMED'},
        client: {'referral_status': 'PLANNED'},
      );
      await pumpApp(
        t,
        rig,
        home: const SyncScreen(),
        size: const Size(412, 1800),
      );
      await settle(
        t,
        until: () => find.byKey(const Key('sync-now')).evaluate().isNotEmpty,
      );
      await t.tap(find.byKey(const Key('sync-now')));
      await settle(
        t,
        until: () => find.byKey(ValueKey('resolve-$id')).evaluate().isNotEmpty,
        maxRounds: 40,
      );
      await settle(t, until: () => !rig.services.sync.syncing, maxRounds: 40);
      await t.tap(find.byKey(ValueKey('resolve-$id')));
      await settle(
        t,
        until: () =>
            find.textContaining('Someone else changed').evaluate().isNotEmpty,
      );
      expect(
        find.textContaining('Someone else changed this record'),
        findsOneWidget,
      );
      expect(find.text('Server has: ATTENDANCE_CONFIRMED'), findsOneWidget);
      expect(find.text('You changed it to: PLANNED'), findsOneWidget);
      await t.tap(find.byKey(const Key('keep-server')));
      await settle(
        t,
        until: () => find.byKey(ValueKey('resolve-$id')).evaluate().isEmpty,
        maxRounds: 30,
      );
      expect(
        (await t.runAsync(() => rig.services.store.referral('REF-X')))!.status,
        'ATTENDANCE_CONFIRMED',
      );
      expect(
        (await t.runAsync(() => rig.services.store.outboxCounts()))!.conflict,
        0,
      );
    });
  });

  group('reports', () {
    Future<AppRig> reportRig(WidgetTester t) async {
      final rig = (await t.runAsync(() => buildRig(demo: false)))!;
      await seedReferrals(rig, t);
      return rig;
    }

    uiTest(
      'a summary is computed on the phone with no network; counts keep the three states separate',
      (t) async {
        final rig = await reportRig(t);
        rig.server.down = true;
        rig.connStream.add([ConnectivityResult.none]);
        await pumpApp(
          t,
          rig,
          home: const ReportsScreen(),
          size: const Size(412, 2000),
        );
        await settle(
          t,
          until: () =>
              find.byKey(const Key('local-summary')).evaluate().isNotEmpty,
        );
        expect(
          find.text(
            'Computed on this phone from saved records (works offline)',
          ),
          findsOneWidget,
        );
        expect(find.text('Recommended'), findsOneWidget);
        expect(find.text('Planned'), findsWidgets);
        expect(
          find.text('Attendance confirmed (hospital record)'),
          findsOneWidget,
        );
        // REF-REC=1 recommended; REF-PLN + REF-FLAG=2 planned; REF-CONF=1 confirmed; total 4; cancelled + duplicate excluded
        expect(_sem('Recommended: 1'), findsOneWidget);
        expect(_sem('Planned: 2'), findsOneWidget);
        expect(
          _sem('Attendance confirmed (hospital record): 1'),
          findsOneWidget,
        );
        expect(_sem('Total recorded referrals: 4'), findsOneWidget);
        expect(find.text('cancelled'), findsOneWidget);
        expect(find.text('duplicate'), findsOneWidget);
        expect(
          find.textContaining('HH-'),
          findsNothing,
          reason: 'reports carry no household identifiers',
        );
        expect(
          find.text('PDF and server reports need an internet connection.'),
          findsOneWidget,
        );
        final btn = t.widget<FilledButton>(
          find.byKey(const Key('server-report')),
        );
        expect(btn.onPressed, isNull);
      },
    );

    uiTest('server report: aggregate counts shown, CSV and PDF can be shared', (
      t,
    ) async {
      final rig = await reportRig(t);
      rig.server.reportJson = {
        'report_id': 'RPT-1',
        'facility_id': 'FAC-1',
        'period_start': '2026-07-15',
        'period_end': '2026-10-13',
        'generated_at': '2026-10-13T09:00:00Z',
        'data_as_of': '2026-10-01T10:00:00Z',
        'last_sync_at': null,
        'data_freshness_label': 'NOT_PROVIDED',
        'counts': {
          'recommended': 1,
          'planned': 2,
          'attendance_confirmed': 1,
          'total_included': 4,
        },
        'counts_by_service_category': {'ANC': 1, 'GENERAL': 3},
        'excluded_counts': {'cancelled': 1},
        'follow_ups': {'due': 5, 'completed_in_period': 7},
        'privacy_notice': 'Aggregate counts only.',
        'synthetic_data': true,
        'content_hash': 'h',
        'duplicate_of_existing': false,
        'superseded_by': null,
      };
      final tmp = await t.runAsync(
        () => Directory.systemTemp.createTemp('rep_ui'),
      );
      await pumpApp(
        t,
        rig,
        home: const ReportsScreen(),
        size: const Size(412, 2600),
      );
      await settle(
        t,
        until: () =>
            find.byKey(const Key('server-report')).evaluate().isNotEmpty,
      );
      await t.tap(find.byKey(const Key('server-report')));
      await settle(
        t,
        until: () =>
            find.byKey(const Key('server-summary')).evaluate().isNotEmpty,
        maxRounds: 40,
      );
      expect(find.byKey(const Key('server-summary')), findsOneWidget);
      expect(find.text('Follow-ups due'), findsOneWidget);
      expect(find.text('Share CSV'), findsWidgets);
      await t.tap(find.byKey(const Key('share-csv')));
      await settle(t, until: () => rig.sharer.shared.isNotEmpty, maxRounds: 40);
      await t.tap(find.byKey(const Key('share-pdf')));
      await settle(
        t,
        until: () => rig.sharer.shared.length == 2,
        maxRounds: 40,
      );
      expect(rig.sharer.shared.map((e) => e.split(':').first), [
        'text/csv',
        'application/pdf',
      ]);
      await t.runAsync(() => tmp!.delete(recursive: true));
    });

    uiTest(
      'server failure is explained in plain language, local summary stays available',
      (t) async {
        final rig = await reportRig(t);
        await pumpApp(
          t,
          rig,
          home: const ReportsScreen(),
          size: const Size(412, 2000),
        );
        await settle(
          t,
          until: () =>
              find.byKey(const Key('server-report')).evaluate().isNotEmpty,
        );
        rig.server.httpStatus = 500;
        await t.tap(find.byKey(const Key('server-report')));
        await settle(
          t,
          until: () => find
              .text('The server had a problem. Try again later.')
              .evaluate()
              .isNotEmpty,
          maxRounds: 40,
        );
        expect(find.byKey(const Key('local-summary')), findsOneWidget);
        expect(find.byKey(const Key('server-summary')), findsNothing);
      },
    );
  });
}

Finder _sem(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);
