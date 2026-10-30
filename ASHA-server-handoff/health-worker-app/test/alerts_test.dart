import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/domain/rules/priority_rules.dart';
import 'package:health_companion/services/alert_notifier.dart';
import 'package:health_companion/services/urgent_alerts.dart';

HouseholdUrgency u(String id, UrgencyLevel level) => HouseholdUrgency(
  householdId: id,
  villageId: 'V',
  score: level == UrgencyLevel.urgent ? 90 : 40,
  level: level,
  factors: const [],
  category: 'ANC',
);

void main() {
  group('planAlerts', () {
    test('only URGENT households that were not already notified are fresh', () {
      final plan = planAlerts(
        [
          u('A', UrgencyLevel.urgent),
          u('B', UrgencyLevel.soon),
          u('C', UrgencyLevel.urgent),
        ],
        {'C'},
      );
      expect(plan.fresh.map((x) => x.householdId), ['A']);
      expect(plan.keep, {'A', 'C'});
      expect(plan.urgentCount, 2);
    });

    test('a household that stops being urgent is forgotten, so it can alert again later', () {
      final plan = planAlerts([u('A', UrgencyLevel.soon)], {'A'});
      expect(plan.fresh, isEmpty);
      expect(plan.keep, isEmpty);
    });
  });

  group('UrgentAlerts', () {
    late FakeAlertNotifier n;
    late Set<String> stored;
    late List<HouseholdUrgency> ranked;
    var enabled = true;
    var lang = 'en';
    late UrgentAlerts alerts;

    setUp(() {
      n = FakeAlertNotifier();
      stored = {};
      ranked = [];
      enabled = true;
      lang = 'en';
      alerts = UrgentAlerts(
        notifier: n,
        loadRanked: () async => ranked,
        readNotified: () async => {...stored},
        writeNotified: (s) async => stored = {...s},
        language: () => lang,
        enabled: () => enabled,
      );
    });

    test('a newly urgent household raises ONE notification, and a daily reminder is scheduled', () async {
      ranked = [u('HH-1', UrgencyLevel.urgent)];
      await alerts.refresh();
      expect(n.shown, hasLength(1));
      expect(n.shown.single.$2, 'Urgent: household HH-1');
      expect(n.daily, hasLength(1));
      expect(stored, {'HH-1'});
    });

    test('refreshing again does not repeat the same alert', () async {
      ranked = [u('HH-1', UrgencyLevel.urgent)];
      await alerts.refresh();
      await alerts.refresh();
      await alerts.refresh();
      expect(n.shown, hasLength(1));
    });

    test(
      'another household becoming urgent alerts only for the new one',
      () async {
        ranked = [u('HH-1', UrgencyLevel.urgent)];
        await alerts.refresh();
        ranked = [
          u('HH-1', UrgencyLevel.urgent),
          u('HH-2', UrgencyLevel.urgent),
        ];
        await alerts.refresh();
        expect(n.shown.map((e) => e.$2), [
          'Urgent: household HH-1',
          'Urgent: household HH-2',
        ]);
      },
    );

    test('many at once are grouped into one summary notification', () async {
      ranked = [for (var i = 1; i <= 6; i++) u('HH-$i', UrgencyLevel.urgent)];
      await alerts.refresh();
      expect(n.shown, hasLength(1));
      expect(n.shown.single.$2, 'Urgent: 6 households need attention');
    });

    test(
      'nothing urgent -> no alert, and the daily reminder is cancelled',
      () async {
        ranked = [u('HH-1', UrgencyLevel.soon)];
        await alerts.refresh();
        expect(n.shown, isEmpty);
        expect(n.daily, isEmpty);
        expect(n.cancelled, contains(UrgentAlerts.dailyId));
      },
    );

    test('switched off -> nothing is shown or scheduled', () async {
      enabled = false;
      ranked = [u('HH-1', UrgencyLevel.urgent)];
      await alerts.refresh();
      expect(n.shown, isEmpty);
      expect(n.daily, isEmpty);
    });

    test('without notification permission nothing is shown AND nothing is remembered, so it alerts once allowed', () async {
      n.permission = false;
      ranked = [u('HH-1', UrgencyLevel.urgent)];
      await alerts.refresh();
      expect(n.shown, isEmpty);
      expect(stored, isEmpty);
      n.permission = true;
      await alerts.refresh();
      expect(n.shown, hasLength(1));
    });

    test(
      'switching off forgets what was notified, so switching on alerts again',
      () async {
        ranked = [u('HH-1', UrgencyLevel.urgent)];
        await alerts.refresh();
        enabled = false;
        await alerts.refresh();
        expect(stored, isEmpty);
        enabled = true;
        await alerts.refresh();
        expect(n.shown, hasLength(2));
      },
    );

    test(
      'the lock-screen body never contains a household ID or any symptom words',
      () async {
        ranked = [u('HH-SYN-00316', UrgencyLevel.urgent)];
        await alerts.refresh();
        expect(n.shown.single.$3.contains('HH-SYN'), isFalse);
      },
    );

    test('Telugu text is used when the app language is Telugu', () async {
      lang = 'te';
      ranked = [u('HH-1', UrgencyLevel.urgent)];
      await alerts.refresh();
      expect(n.shown.single.$2, contains('అత్యవసరం'));
    });

    test('overlapping refreshes (sync + save at the same moment) do not double-alert', () async {
      ranked = [u('HH-1', UrgencyLevel.urgent)];
      await Future.wait([alerts.refresh(), alerts.refresh(), alerts.refresh()]);
      expect(n.shown, hasLength(1));
    });
  });
}
