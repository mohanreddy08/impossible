import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/data/local/local_store.dart';
import 'package:health_companion/presentation/screens/add_household_screen.dart';
import 'package:health_companion/presentation/screens/households_screen.dart';
import 'package:health_companion/services/field_work_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'support/harness.dart';
import 'telugu_complete_test.dart' show englishLeaks, shownText;

void main() {
  sqfliteFfiInit();

  group('FieldWorkService.addHousehold', () {
    late Rig rig;
    setUp(() async {
      rig = await Rig.create(
        configured: false,
      ); // no server at all: pure offline
      await rig.seedBasic();
    });
    tearDown(() => rig.dispose());

    test(
      'saves the family locally AND queues a create for the server, together',
      () async {
        final id = await rig.fieldWork.addHousehold(
          villageId: 'VIL-1',
          memberCount: 5,
          categories: ['ANC', 'ROUTINE'],
        );
        expect(id, startsWith('HH-'));
        final h = (await rig.store.household(id))!;
        expect(h.villageId, 'VIL-1');
        expect(h.memberCount, 5);
        expect(h.eligibleCategories, ['ANC', 'ROUTINE']);
        expect(h.recordStatus, 'NO_VISIT_DUE');
        expect(h.version, 1);
        expect(
          h.assignedWorkerId,
          'WRK-1',
          reason: 'the worker this phone belongs to',
        );
        final ops = await rig.store.db.query(
          'sync_outbox',
          where: "entity_type = 'household' AND entity_id = ?",
          whereArgs: [id],
        );
        expect(ops, hasLength(1));
        expect(ops.single['op_type'], 'create');
        expect(ops.single['state'], 'PENDING');
        final payload = ops.single['payload'].toString();
        expect(payload.contains('"village_id":"VIL-1"'), isTrue);
        expect(payload.contains('"household_member_count":5'), isTrue);
        expect(payload.contains('"assigned_worker_id":"WRK-1"'), isTrue);
        expect(
          payload.contains('"eligible_followup_categories":["ANC","ROUTINE"]'),
          isTrue,
        );
      },
    );

    test('two families get two different ids', () async {
      final a = await rig.fieldWork.addHousehold(
        villageId: 'VIL-1',
        memberCount: 3,
        categories: ['ROUTINE'],
      );
      final b = await rig.fieldWork.addHousehold(
        villageId: 'VIL-1',
        memberCount: 3,
        categories: ['ROUTINE'],
      );
      expect(a, isNot(b));
    });

    test(
      'the new family appears in the household list and the count',
      () async {
        final before = await rig.store.countHouseholds(const HouseholdFilter());
        await rig.fieldWork.addHousehold(
          villageId: 'VIL-1',
          memberCount: 3,
          categories: ['ROUTINE'],
        );
        expect(
          await rig.store.countHouseholds(const HouseholdFilter()),
          before + 1,
        );
      },
    );

    test('validation: bad village, members out of range, no category -> NOTHING is saved', () async {
      final before = await rig.store.countHouseholds(const HouseholdFilter());
      for (final bad in [
        (' ', 3, ['ROUTINE'], 'village'),
        ('a', 3, ['ROUTINE'], 'village'),
        ('VIL 1!', 3, ['ROUTINE'], 'village'),
        ('VIL-1', 0, ['ROUTINE'], 'members'),
        ('VIL-1', 61, ['ROUTINE'], 'members'),
        ('VIL-1', 3, <String>[], 'categories'),
        ('VIL-1', 3, ['NOT-A-CATEGORY'], 'categories'),
      ]) {
        await expectLater(
          rig.fieldWork.addHousehold(
            villageId: bad.$1,
            memberCount: bad.$2,
            categories: bad.$3,
          ),
          throwsA(
            isA<DomainValidation>().having(
              (e) => e.errors.containsKey(bad.$4),
              bad.$4,
              isTrue,
            ),
          ),
          reason: '$bad',
        );
      }
      expect(await rig.store.countHouseholds(const HouseholdFilter()), before);
      expect(
        await rig.store.db.query(
          'sync_outbox',
          where: "entity_type = 'household'",
        ),
        isEmpty,
      );
    });

    test('a phone that does not know its worker yet refuses, with a clear reason (nothing saved)', () async {
      await rig.store.wipe();
      await expectLater(
        rig.fieldWork.addHousehold(
          villageId: 'VIL-1',
          memberCount: 3,
          categories: ['ROUTINE'],
        ),
        throwsA(
          isA<DomainValidation>().having(
            (e) => e.errors['worker'],
            'worker',
            'unknown',
          ),
        ),
      );
    });

    test('a family added offline is sent on the next sync and the server accepts it', () async {
      final live = await Rig.create();
      await live.seedBasic();
      final id = await live.fieldWork.addHousehold(
        villageId: 'VIL-1',
        memberCount: 4,
        categories: ['ROUTINE'],
      );
      final rep = await live.engine.syncNow();
      expect(rep.error, isNull);
      expect((await live.store.outboxCounts()).pending, 0);
      expect((await live.store.household(id)), isNotNull);
      await live.dispose();
    });

    test('a family whose creation the server rejects can be discarded and then disappears from the phone', () async {
      final live = await Rig.create();
      await live.seedBasic();
      final id = await live.fieldWork.addHousehold(
        villageId: 'VIL-1',
        memberCount: 4,
        categories: ['ROUTINE'],
      );
      final op =
          (await live.store.db.query(
                'sync_outbox',
                where: 'entity_id = ?',
                whereArgs: [id],
              )).single['op_id']!
              as String;
      await live.engine.discard(op);
      expect(await live.store.household(id), isNull);
      await live.dispose();
    });
  });

  group('the Add family screen', () {
    uiTest(
      'the Households page has an "Add a new family" button that opens the form',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        await pumpApp(t, rig, home: const HouseholdsScreen());
        await t.tap(find.byKey(const Key('add-family')));
        await settle(t, maxRounds: 15);
        expect(find.byType(AddHouseholdScreen), findsOneWidget);
        expect(find.text('New family'), findsOneWidget);
      },
    );

    uiTest(
      'the form starts with the village you work in most, 4 members and Routine selected',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        await pumpApp(
          t,
          rig,
          home: const AddHouseholdScreen(),
          size: const Size(412, 1400),
        );
        await settle(t, maxRounds: 15);
        final village = (await t.runAsync(
          () => rig.services.store.villagesByUse(),
        ))!.first;
        expect(
          t
              .widget<TextField>(find.byKey(const Key('add-village')))
              .controller!
              .text,
          village,
        );
        expect(
          t.widget<Text>(find.byKey(const Key('members-value'))).data,
          '4',
        );
        expect(
          t.widget<FilterChip>(find.byKey(const Key('cat-ROUTINE'))).selected,
          isTrue,
        );
      },
    );

    uiTest('+ and - change the member count within 1..60', (t) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      await pumpApp(
        t,
        rig,
        home: const AddHouseholdScreen(),
        size: const Size(412, 1400),
      );
      await settle(t, maxRounds: 15);
      await t.tap(find.byKey(const Key('members-plus')));
      await t.pump();
      expect(t.widget<Text>(find.byKey(const Key('members-value'))).data, '5');
      for (var i = 0; i < 10; i++) {
        await t.tap(find.byKey(const Key('members-minus')));
        await t.pump();
      }
      expect(t.widget<Text>(find.byKey(const Key('members-value'))).data, '1');
      expect(
        t.widget<IconButton>(find.byKey(const Key('members-minus'))).onPressed,
        isNull,
        reason: 'cannot go below 1',
      );
    });

    uiTest(
      'saving adds the family, queues it, and opens its page so a first visit can be scheduled',
      (t) async {
        final rig = (await t.runAsync(() => buildRig(configured: false)))!;
        await pumpApp(
          t,
          rig,
          home: const AddHouseholdScreen(),
          size: const Size(412, 1400),
        );
        await settle(t, maxRounds: 15);
        final before = (await t.runAsync(
          () => rig.services.store.countHouseholds(const HouseholdFilter()),
        ))!;
        await t.enterText(find.byKey(const Key('add-village')), 'VIL-NEW-9');
        await t.tap(find.byKey(const Key('cat-ANC')));
        await t.pump();
        await t.ensureVisible(find.byKey(const Key('add-family-save')));
        await t.tap(find.byKey(const Key('add-family-save')));
        await settle(t, maxRounds: 25);
        expect(
          await t.runAsync(
            () => rig.services.store.countHouseholds(const HouseholdFilter()),
          ),
          before + 1,
        );
        expect(find.byType(HouseholdDetailScreen), findsOneWidget);
        expect(find.byKey(const Key('schedule-visit')), findsOneWidget);
        final rows = (await t.runAsync(
          () => rig.services.store.db.query(
            'households',
            where: 'village_id = ?',
            whereArgs: ['VIL-NEW-9'],
          ),
        ))!;
        expect(rows, hasLength(1));
        expect(rows.single['eligible_followup_categories'], '|ANC|ROUTINE|');
        final queued = (await t.runAsync(
          () => rig.services.store.db.query(
            'sync_outbox',
            where: "entity_type = 'household'",
          ),
        ))!;
        expect(queued, hasLength(1));
      },
    );

    uiTest('an empty village shows the error and saves nothing', (t) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      await pumpApp(
        t,
        rig,
        home: const AddHouseholdScreen(),
        size: const Size(412, 1400),
      );
      await settle(t, maxRounds: 15);
      final before = (await t.runAsync(
        () => rig.services.store.countHouseholds(const HouseholdFilter()),
      ))!;
      await t.enterText(find.byKey(const Key('add-village')), '');
      await t.ensureVisible(find.byKey(const Key('add-family-save')));
      await t.tap(find.byKey(const Key('add-family-save')));
      await settle(t, maxRounds: 15);
      expect(find.textContaining('Enter the village ID'), findsOneWidget);
      expect(find.byType(AddHouseholdScreen), findsOneWidget);
      expect(
        await t.runAsync(
          () => rig.services.store.countHouseholds(const HouseholdFilter()),
        ),
        before,
      );
    });

    uiTest('un-ticking every follow-up type shows the error', (t) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      await pumpApp(
        t,
        rig,
        home: const AddHouseholdScreen(),
        size: const Size(412, 1400),
      );
      await settle(t, maxRounds: 15);
      await t.tap(find.byKey(const Key('cat-ROUTINE')));
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('add-family-save')));
      await t.tap(find.byKey(const Key('add-family-save')));
      await settle(t, maxRounds: 15);
      expect(find.text('Pick at least one follow-up type.'), findsOneWidget);
    });

    uiTest('Telugu: no English left on the form (including its errors)', (
      t,
    ) async {
      final rig = (await t.runAsync(
        () => buildRig(configured: false, lang: 'te'),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AddHouseholdScreen(),
        size: const Size(412, 2000),
      );
      await settle(t, maxRounds: 15);
      expect(englishLeaks(shownText(t)), isEmpty);
      await t.enterText(find.byKey(const Key('add-village')), '');
      await t.tap(find.byKey(const Key('cat-ROUTINE')));
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('add-family-save')));
      await t.tap(find.byKey(const Key('add-family-save')));
      await settle(t, maxRounds: 15);
      expect(englishLeaks(shownText(t)), isEmpty);
    });

    for (final cfg in {
      'small phone 320x568, 200% text, Telugu': (
        const Size(320, 568),
        2.0,
        'te',
      ),
      'small phone 320x568, 200% text, English': (
        const Size(320, 568),
        2.0,
        'en',
      ),
    }.entries) {
      uiTest('fits without overflow: ${cfg.key}', (t) async {
        final rig = (await t.runAsync(
          () => buildRig(configured: false, lang: cfg.value.$3),
        ))!;
        await pumpApp(
          t,
          rig,
          home: const AddHouseholdScreen(),
          size: cfg.value.$1,
          textScale: cfg.value.$2,
        );
        await settle(t, maxRounds: 15);
        await t.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await settle(t, maxRounds: 6);
      });
    }
  });
}
