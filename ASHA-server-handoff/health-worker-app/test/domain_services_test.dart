import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/core/clock.dart';
import 'package:health_companion/data/local/local_store.dart';
import 'package:health_companion/domain/retrieval/local_retrieval.dart';
import 'package:health_companion/domain/rules/report_rules.dart';
import 'package:health_companion/domain/rules/visit_rules.dart';
import 'package:health_companion/domain/safety/safety_engine.dart';
import 'package:health_companion/services/demo_data.dart';
import 'package:health_companion/services/protocol_library.dart';
import 'package:health_companion/services/qa_service.dart';
import 'package:health_companion/services/settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/builders.dart';
import 'support/fake_server.dart';
import 'support/harness.dart';

LocalPassage lp(
  String id,
  String text, {
  String status = 'VERIFIED',
  String? section,
  int? page,
}) => LocalPassage(
  passageId: id,
  documentId: 'D',
  documentTitle: 'Doc',
  documentVersion: 'v1',
  sectionId: 's',
  sectionTitle: section,
  pageNumber: page,
  text: text,
  verificationStatus: status,
);

void main() {
  sqfliteFfiInit();

  group('local retrieval (approved evidence only)', () {
    final passages = [
      lp(
        'P1',
        'The visit register must be signed by the supervisor after each monthly review meeting.',
        section: 'Register upkeep',
        page: 4,
      ),
      lp(
        'P2',
        'Immunisation cards are stored in a dry folder kept at the sub-centre cabinet.',
        page: 7,
      ),
      lp(
        'P3',
        'ప్రతి నెల సమీక్ష తర్వాత రిజిస్టర్‌పై పర్యవేక్షకుడు సంతకం చేయాలి.',
        section: 'రిజిస్టర్ నిర్వహణ',
        page: 2,
      ),
      lp(
        'X1',
        'The unverified draft says the lantern cupboard is painted blue.',
        status: 'UNVERIFIED',
      ),
      lp(
        'X2',
        'Fixture text about a bicycle repair roster.',
        status: 'TEST_FIXTURE_ONLY',
      ),
    ];
    final r = LocalRetrieval(passages);

    test('only VERIFIED passages are indexed', () {
      expect(r.size, 3);
      expect(r.search('lantern cupboard blue'), isEmpty);
      expect(r.search('bicycle repair roster'), isEmpty);
    });

    test('English, Telugu and code-mixed questions find the right passage with its citation fields', () {
      final en = r.search(
        'Who signs the visit register after the monthly review?',
      );
      expect(en.first.passage.passageId, 'P1');
      expect(
        (en.first.passage.sectionTitle, en.first.passage.pageNumber),
        ('Register upkeep', 4),
      );
      expect(
        en.first.passage.text,
        passages[0].text,
        reason: 'exact source text',
      );
      expect(
        r
            .search('రిజిస్టర్‌పై ఎవరు సంతకం చేయాలి సమీక్ష తర్వాత?')
            .first
            .passage
            .passageId,
        'P3',
      );
      expect(
        r
            .search(
              'monthly review తర్వాత register ఎవరు sign చేయాలి supervisor',
            )
            .first
            .passage
            .passageId,
        'P1',
      );
    });

    test('nonsense, empty and stop-word-only queries return nothing', () {
      for (final q in [
        'What is the colour of the moon cheese?',
        '',
        '   ',
        '????',
        'ఏం ఎలా',
      ]) {
        expect(r.search(q), isEmpty, reason: q);
      }
    });

    test('threshold is configurable', () {
      expect(
        r.search('visit register unknownword another', minScore: 0.9),
        isEmpty,
      );
      expect(
        r.search(
          'visit register unknownword another',
          minScore: 0.1,
          minMatchedTerms: 1,
        ),
        isNotEmpty,
      );
    });

    test(
      'an empty library never answers',
      () => expect(
        LocalRetrieval(const []).search('anything at all here'),
        isEmpty,
      ),
    );
  });

  group('QaService ordering', () {
    late Rig rig;
    late SafetyEngine engine;
    setUp(() async {
      rig = await Rig.create();
      engine = SafetyEngine.fromJsonString(
        File('assets/safety/danger_rules.json').readAsStringSync(),
      );
    });
    tearDown(() => rig.dispose());

    QaService svc(Future<LocalRetrieval> Function() idx) =>
        QaService(engine: engine, api: rig.api, loadIndex: idx);

    test('safety runs first: a danger sign is never answered or sent to the server; approved local text may accompany it', () async {
      var indexed = 0;
      final s = svc(() async {
        indexed++;
        return LocalRetrieval([
          lp('P', 'pregnant woman bleeding heavily call the van now please'),
        ]);
      });
      final res = await s.ask('Pregnant woman is bleeding heavily right now');
      expect(res.outcome, QaOutcome.escalationRequired);
      expect(res.message, isNotEmpty);
      expect(
        res.evidence,
        hasLength(1),
      ); // approved local passage shown beside the urgent steps
      expect(indexed, 1);
      expect(rig.server.requestPaths, isEmpty);
    });

    test(
      'a danger sign with no approved local text carries no evidence',
      () async {
        final s = svc(() async => LocalRetrieval(const []));
        final res = await s.ask('Pregnant woman is bleeding heavily right now');
        expect(res.outcome, QaOutcome.escalationRequired);
        expect(res.evidence, isEmpty);
      },
    );

    test('a failing local index never blocks the escalation', () async {
      final s = svc(() async => throw StateError('db unavailable'));
      final res = await s.ask('Pregnant woman is bleeding heavily right now');
      expect(res.outcome, QaOutcome.escalationRequired);
      expect(res.evidence, isEmpty);
    });

    test('input validation', () async {
      final s = svc(() async => LocalRetrieval(const []));
      expect(() => s.ask(''), throwsA(isA<QuestionInvalid>()));
      expect(() => s.ask('   \n'), throwsA(isA<QuestionInvalid>()));
      expect(() => s.ask('x' * 2001), throwsA(isA<QuestionInvalid>()));
      expect(QaService.validate('hi\x00 there\x07'), 'hi there');
    });

    test(
      'local approved evidence answers without touching the network',
      () async {
        final s = svc(
          () async => LocalRetrieval([
            lp(
              'P1',
              'The visit register must be signed by the supervisor after each monthly review meeting.',
              section: 'S',
              page: 3,
            ),
          ]),
        );
        final res = await s.ask(
          'Who signs the visit register after the monthly review?',
        );
        expect(res.outcome, QaOutcome.answeredWithEvidence);
        expect(res.fromDevice, isTrue);
        expect(res.evidence.single.isVerified, isTrue);
        expect(rig.server.requestPaths, isEmpty);
      },
    );

    test('no evidence + server down -> cannot verify offline (never an invented answer)', () async {
      rig.server.down = true;
      final res = await svc(() async => LocalRetrieval(const []))
          .ask('How often is the register reviewed?');
      expect(res.outcome, QaOutcome.cannotVerifyOffline);
      expect(res.evidence, isEmpty);
    });

    test('server says answered but gives no passage -> downgraded to insufficient evidence', () async {
      rig.server.qaQuery = qaJson(
        'ANSWERED_WITH_EVIDENCE',
        answer: null,
        citations: [],
      );
      rig.server.qaRetrieve = {
        'query_id': 'q',
        'status': 'MATCH_FOUND',
        'original_query': 'x',
        'normalized_query': 'x',
        'matched_passage_ids': [],
        'indexed_passages': 0,
        'matches': [],
      };
      final res = await svc(() async => LocalRetrieval(const []))
          .ask('How often is the register reviewed?');
      expect(res.outcome, QaOutcome.insufficientEvidence);
    });

    test('unconfigured server is treated like offline', () async {
      final r2 = await Rig.create(configured: false);
      final res = await QaService(
        engine: engine,
        api: r2.api,
        loadIndex: () async => LocalRetrieval(const []),
      ).ask('How often is the register reviewed?');
      expect(res.outcome, QaOutcome.cannotVerifyOffline);
      await r2.dispose();
    });
  });

  group('protocol library', () {
    test('stores ONLY documents that are approved AND verified; others are never stored', () async {
      final rig = await Rig.create();
      final lib = ProtocolLibrary(rig.store, rig.api);
      Map<String, dynamic> doc(String id, String status, bool approved) => {
        'document_id': id,
        'title': 'T-$id',
        'issuing_authority': 'A',
        'version': 'v1',
        'publication_date': null,
        'language': 'en',
        'source_verification_status': status,
        'approved_for_retrieval': approved,
      };
      Map<String, dynamic> pas(String id, String d, String status) => {
        'passage_id': id,
        'document_id': d,
        'section_id': '1',
        'section_title': 'Sec',
        'page_number': 3,
        'passage_text': 'text $id',
        'language': 'en',
        'source_verification_status': status,
      };
      rig.server.protocolDocs = [
        doc('OK', 'VERIFIED', true),
        doc('UNV', 'UNVERIFIED', false),
        doc('FIX', 'TEST_FIXTURE_ONLY', false),
        doc('HALF', 'VERIFIED', false),
      ];
      rig.server.protocolPassages = {
        'OK': [pas('OK-1', 'OK', 'VERIFIED'), pas('OK-2', 'OK', 'UNVERIFIED')],
        'UNV': [pas('UNV-1', 'UNV', 'UNVERIFIED')],
        'FIX': [pas('FIX-1', 'FIX', 'TEST_FIXTURE_ONLY')],
        'HALF': [pas('HALF-1', 'HALF', 'VERIFIED')],
      };
      expect(await lib.approvedPassageCount(), 0);
      expect(await lib.refreshFromServer(), 1);
      final idx = await lib.loadIndex();
      expect(idx.size, 1);
      final ids = (await rig.store.db.query('protocol_passages'))
          .map((r) => r['passage_id'])
          .toList();
      expect(ids, ['OK-1']);
      expect(
        (await rig.store.db.query('protocol_documents'))
            .map((r) => r['document_id']),
        ['OK'],
      );
      // the server withdraws approval -> it disappears from the phone
      rig.server.protocolDocs = [doc('OK', 'UNVERIFIED', false)];
      await lib.refreshFromServer();
      expect(await lib.approvedPassageCount(), 0);
      expect((await lib.loadIndex()).isEmpty, isTrue);
      await rig.dispose();
    });

    test('local rows that are not approved+verified are ignored by the index even if present', () async {
      final rig = await Rig.create();
      await rig.store.db.insert('protocol_documents', {
        'document_id': 'D',
        'title': 'T',
        'source_verification_status': 'UNVERIFIED',
        'approved_for_retrieval': 0,
      });
      await rig.store.db.insert('protocol_passages', {
        'passage_id': 'D-1',
        'document_id': 'D',
        'passage_text': 'visit register supervisor monthly review',
        'approved_for_retrieval': 1,
        'source_verification_status': 'VERIFIED',
      });
      expect(
        (await ProtocolLibrary(rig.store, rig.api).loadIndex()).isEmpty,
        isTrue,
        reason: 'passage flags alone are not enough: the document must be approved too',
      );
      await rig.dispose();
    });
  });

  group('visit rules', () {
    test('priority: overdue (days late) / today / upcoming (days until); dates only', () {
      final t = DateTime(2026, 10, 13);
      expect(
        priorityFor(DateTime(2026, 10, 1), t, 'ANC', null).bucket,
        PriorityBucket.overdue,
      );
      expect(priorityFor(DateTime(2026, 10, 1), t, 'ANC', null).days, 12);
      expect(priorityFor(t, t, 'ANC', null).bucket, PriorityBucket.today);
      expect(priorityFor(DateTime(2026, 10, 20), t, 'ANC', null).days, 7);
    });

    test(
      'planner order: most overdue first, then today, then soonest upcoming',
      () async {
        final rig = await Rig.create();
        await rig.store.upsertHouseholds([
          for (var i = 0; i < 5; i++) hh('H$i'),
        ], respectPending: false);
        await rig.store.upsertVisits([
          vis('V0', 'H0', DateTime(2026, 10, 12)),
          vis('V1', 'H1', DateTime(2026, 9, 1)),
          vis('V2', 'H2', DateTime(2026, 10, 5)),
          vis('V3', 'H3', today),
          vis('V4', 'H4', DateTime(2026, 10, 20)),
        ], respectPending: false);
        final over = (await rig.store.plannedVisits(
          'overdue',
          today,
        )).map((e) => e.visit.visitId).toList();
        expect(over, ['V1', 'V2', 'V0']);
        expect(
          (await rig.store.plannedVisits(
            'today',
            today,
          )).map((e) => e.visit.visitId),
          ['V3'],
        );
        expect(
          (await rig.store.plannedVisits(
            'upcoming',
            today,
          )).map((e) => e.visit.visitId),
          ['V4'],
        );
        await rig.dispose();
      },
    );

    test('recompute reproduces the backend rules', () async {
      final rig = await Rig.create();
      await rig.store.upsertHouseholds([hh('H1')], respectPending: false);
      await rig.store.upsertVisits([
        vis(
          'A',
          'H1',
          DateTime(2026, 9, 1),
          status: 'COMPLETED',
          actual: DateTime(2026, 10, 10),
        ),
      ], respectPending: false);
      Future<String> status(DateTime d) async {
        await rig.store.db.transaction(
          (txn) => recomputeHousehold(txn, 'H1', d),
        );
        return (await rig.store.household('H1'))!.recordStatus;
      }

      expect(
        await status(DateTime(2026, 10, 13)),
        'COMPLETED',
        reason: 'within 14 days of the last completed visit',
      );
      expect(await status(DateTime(2026, 11, 30)), 'NO_VISIT_DUE');
      await rig.store.upsertVisits([
        vis('B', 'H1', DateTime(2026, 10, 14)),
      ], respectPending: false);
      expect(await status(DateTime(2026, 10, 13)), 'UPCOMING');
      expect(await status(DateTime(2026, 10, 14)), 'DUE_TODAY');
      expect(await status(DateTime(2026, 10, 20)), 'OVERDUE');
      await rig.dispose();
    });
  });

  group('report rules (port of backend aggregate)', () {
    test('counts by state; only real attendance counts as attended; cancelled/duplicate/outside-period excluded', () {
      final refs = [
        ref(
          'R1',
          'H',
          'V',
          status: 'RECOMMENDED',
          created: DateTime(2026, 9, 1),
        ),
        ref(
          'R2',
          'H',
          'V',
          status: 'PLANNED',
          created: DateTime(2026, 9, 2),
          planned: DateTime(2026, 9, 9),
          cat: 'ANC',
        ),
        ref(
          'R3',
          'H',
          'V',
          status: 'ATTENDANCE_CONFIRMED',
          confirmed: true,
          record: 'A1',
          created: DateTime(2026, 9, 3),
        ),
        ref(
          'R4',
          'H',
          'V',
          status: 'ATTENDANCE_CONFIRMED',
          confirmed: true,
          created: DateTime(2026, 9, 4),
        ), // no record
        ref(
          'R5',
          'H',
          'V',
          status: 'PLANNED',
          state: 'CANCELLED',
          created: DateTime(2026, 9, 5),
        ),
        ref(
          'R6',
          'H',
          'V',
          status: 'RECOMMENDED',
          state: 'DUPLICATE',
          created: DateTime(2026, 9, 6),
        ),
        ref(
          'R7',
          'H',
          'V',
          status: 'RECOMMENDED',
          created: DateTime(2025, 1, 1),
        ),
        ref(
          'R8',
          'H',
          'V',
          status: 'RECOMMENDED',
          facility: 'FAC-2',
          created: DateTime(2026, 9, 7),
        ),
        ref(
          'R1',
          'H',
          'V',
          status: 'RECOMMENDED',
          created: DateTime(2026, 9, 1),
        ),
      ];
      final s = aggregateReferrals(
        refs,
        'FAC-1',
        DateTime(2026, 7, 1),
        DateTime(2026, 10, 13),
      );
      expect(
        (s.recommended, s.planned, s.attendanceConfirmed, s.total),
        (1, 2, 1, 4),
      );
      expect(s.byCategory.values.fold<int>(0, (a, b) => a + b), 4);
      expect(s.excluded, {
        'repeated_id': 1,
        'cancelled': 1,
        'duplicate': 1,
        'outside_period': 1,
        'other_facility': 1,
      });
    });

    test('freshness labels', () {
      final now = DateTime.utc(2026, 10, 13, 12);
      expect(freshnessLabel(null, now), 'NOT_PROVIDED');
      expect(
        freshnessLabel(now.subtract(const Duration(hours: 23)), now),
        'FRESH',
      );
      expect(
        freshnessLabel(now.subtract(const Duration(hours: 50)), now),
        'RECENT',
      );
      expect(
        freshnessLabel(now.subtract(const Duration(hours: 100)), now),
        'STALE_OFFLINE',
      );
    });

    test('local CSV carries the required fields and no identifiers', () {
      final s = aggregateReferrals(
        [ref('R1', 'HH-SECRET', 'V', created: DateTime(2026, 9, 1))],
        'FAC-1',
        DateTime(2026, 8, 1),
        DateTime(2026, 10, 13),
      );
      final csv = summaryToCsv(
        s,
        'FRESH',
        '2026-10-13T09:00:00Z',
        '2026-10-13T08:00:00Z',
      );
      for (final k in [
        'facility_id,FAC-1',
        'period_start,2026-08-01',
        'generated_at',
        'data_freshness_label,FRESH',
        'count_recommended,1',
        'count_attendance_confirmed,0',
        'privacy_notice',
      ]) {
        expect(csv, contains(k));
      }
      expect(csv, isNot(contains('HH-SECRET')));
    });

    test("report rules agree with the backend's own expected totals on the supplied hospital_report_tests (offline == server)", () async {
      // Uses the REAL generated referral records + the backend's expected counts. Everything else is the same code path the app uses.
      final lines = File(
        '../health-worker-datasets/hospital_report_tests.jsonl',
      ).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
      final refRows = File('../health-worker-datasets/referral_records.csv')
          .readAsLinesSync();
      final head = refRows.first.split(',');
      final byId = <String, Map<String, String>>{};
      for (final l in refRows.skip(1)) {
        final c = l.split(',');
        byId[c[0]] = {for (var i = 0; i < head.length; i++) head[i]: c[i]};
      }
      var checked = 0;
      for (final l in lines) {
        final j = _json(l);
        final per = (j['reporting_period'] as String).split('/');
        final refs = [
          for (final id in (j['input_referral_ids'] as List))
            if (byId[id] case final r?)
              ref(
                id as String,
                r['household_id']!,
                r['visit_id']!,
                status: r['referral_status']!,
                state: r['record_state']!,
                facility: r['facility_id']!,
                cat: r['service_category']!,
                created: parseDate(r['referral_created_date']),
                confirmed: r['attendance_confirmed'] == 'true',
                record: r['attendance_record_id']!.isEmpty
                    ? null
                    : r['attendance_record_id'],
              ),
        ];
        final s = aggregateReferrals(
          refs,
          j['selected_facility_id'] as String,
          parseDate(per[0])!,
          parseDate(per[1])!,
        );
        expect(
          (s.recommended, s.planned, s.attendanceConfirmed),
          (
            j['expected_recommended_count'],
            j['expected_planned_count'],
            j['expected_attendance_confirmed_count'],
          ),
          reason: j['scenario_id'] as String,
        );
        expect(
          s.byCategory,
          (j['expected_counts_by_service_category'] as Map).cast<String, int>(),
          reason: j['scenario_id'] as String,
        );
        checked++;
      }
      expect(checked, greaterThanOrEqualTo(50));
    });
  });

  group('demo data and settings', () {
    test('demo seed loads in FK order, keeps ids/versions, and is clearly synthetic', () async {
      final rig = await Rig.create();
      final r = await DemoData(
        rig.store,
        loader: () => File('assets/demo/demo_seed.json').readAsString(),
      ).load();
      expect((r.households, r.visits, r.referrals), (80, 330, 41));
      expect(await rig.store.countHouseholds(const HouseholdFilter()), 80);
      expect(await rig.store.meta('demo_loaded'), '1');
      expect((await rig.store.household('HH-SYN-00001'))!.version, 1);
      final c = await rig.store.dashboard(DateTime(2026, 10, 13));
      expect(c.overdue + c.dueToday + c.upcoming, greaterThan(0));
      await rig.dispose();
    });

    test(
      'plain http to a remote host is flagged; local/emulator hosts are not',
      () {
        expect(
          AppSettings.isInsecureRemote('http://health.example.org'),
          isTrue,
        );
        expect(
          AppSettings.isInsecureRemote('https://health.example.org'),
          isFalse,
        );
        for (final u in [
          'http://10.0.2.2:8000',
          'http://localhost:8000',
          'http://192.168.1.20',
          'http://127.0.0.1:8000',
        ]) {
          expect(AppSettings.isInsecureRemote(u), isFalse, reason: u);
        }
      },
    );

    test(
      'the API key lives in the secret store, never in preferences',
      () async {
        final rig = await buildSettingsRig();
        await rig.$1.setApiKey('  my-key  ');
        expect(rig.$1.hasApiKey, isTrue);
        expect(
          (await rig.$1.apiConfig()) == null,
          isTrue,
          reason: 'no base url yet',
        );
        await rig.$1.setBaseUrl('https://x.example.org');
        expect((await rig.$1.apiConfig())!.apiKey, 'my-key');
        expect(await rig.$2.read('api_key'), 'my-key');
        expect(
          rig.$3.getKeys().join(','),
          isNot(contains('key')),
          reason: 'no key-like entry in SharedPreferences',
        );
        expect(
          rig.$3.getKeys().any(
            (k) => (rig.$3.get(k) ?? '').toString().contains('my-key'),
          ),
          isFalse,
        );
      },
    );
  });
}

Map<String, dynamic> _json(String l) => jsonDecode(l) as Map<String, dynamic>;
