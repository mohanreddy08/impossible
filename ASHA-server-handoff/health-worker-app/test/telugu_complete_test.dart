import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/data/local/local_store.dart';
import 'package:health_companion/presentation/app_shell.dart';
import 'package:health_companion/presentation/screens/ask_screen.dart';
import 'package:health_companion/presentation/screens/households_screen.dart';
import 'package:health_companion/presentation/screens/planner_screen.dart';
import 'package:health_companion/presentation/screens/priority_screen.dart';
import 'package:health_companion/presentation/screens/referrals_screen.dart';
import 'package:health_companion/presentation/screens/reports_screen.dart';
import 'package:health_companion/presentation/screens/settings_screen.dart';
import 'package:health_companion/presentation/screens/sync_screen.dart';
import 'package:health_companion/presentation/screens/visit_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'support/fake_server.dart';
import 'voice_test.dart' show FakeVoice;

import 'package:health_companion/services/voice_input.dart';

/// Words that are allowed to stay in Latin letters: the product name, the language name, record IDs / codes, and the six village names of
/// the Chandrapuri data (place names are shown as the data writes them).
final _allowed = RegExp(
  r'ASHA|\bAI\b|English|Amrapur|Belwadi Tola|Dhanpura|Kesarganj|Navagaon Khurd|Sitapahari|https?://\S+|\b[A-Z]{2,5}-[A-Z0-9]+(?:-[A-Z0-9]+)*\b|\b\d+\.\d+\.\d+(?:-[a-z]+)?\b|\bHH\b|\bANC\b|\bAM\b|\bPM\b|\bPDF\b|\bCSV\b|\bID\b',
);

/// Every piece of text a worker can read or hear (visible text, tooltips, screen-reader labels) on the current screen.
Set<String> shownText(WidgetTester t) {
  final out = <String>{};
  for (final w in t.widgetList<Text>(find.byType(Text))) {
    final s = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (s.trim().isNotEmpty) out.add(s);
  }
  for (final w in t.widgetList<SelectableText>(find.byType(SelectableText))) {
    final s = w.data ?? '';
    if (s.trim().isNotEmpty) out.add(s);
  }
  for (final w in t.widgetList<TextField>(find.byType(TextField))) {
    final h = w.decoration?.hintText;
    final l = w.decoration?.labelText;
    if (h != null) out.add(h);
    if (l != null) out.add(l);
  }
  for (final w in t.widgetList<Tooltip>(find.byType(Tooltip))) {
    if (w.message != null) out.add(w.message!);
  }
  for (final w in t.widgetList<Semantics>(find.byType(Semantics))) {
    final l = w.properties.label;
    if (l != null && l.trim().isNotEmpty) out.add(l);
  }
  return out;
}

List<String> englishLeaks(Set<String> texts) {
  final leaks = <String>[];
  for (final s in texts) {
    final rest = s.replaceAll(_allowed, ' ');
    if (RegExp(r'[A-Za-z]{2,}').hasMatch(rest)) leaks.add(s);
  }
  return leaks..sort();
}

void main() {
  sqfliteFfiInit();

  final screens = <String, Widget Function(String)>{
    'home (shell)': (_) => const AppShell(),
    'planner': (_) => const PlannerScreen(initialTab: 0),
    'priority list': (_) => const PriorityScreen(),
    'households': (_) => const HouseholdsScreen(),
    'ask': (_) => const AskScreen(),
    'referrals': (_) => const ReferralsScreen(),
    'reports': (_) => const ReportsScreen(),
    'sync centre': (_) => const SyncScreen(),
    'settings': (_) => const SettingsScreen(),
  };

  for (final sc in screens.entries) {
    uiTest('Telugu: no English left on ${sc.key}', (t) async {
      final rig = (await t.runAsync(() => buildRig(lang: 'te')))!;
      await pumpApp(t, rig, home: sc.value(''), size: const Size(412, 3000));
      await settle(t, maxRounds: 25);
      expect(englishLeaks(shownText(t)), isEmpty, reason: sc.key);
    });
  }

  uiTest('Telugu: no English left on the visit form', (t) async {
    final rig = (await t.runAsync(() => buildRig(lang: 'te')))!;
    final id = (await t.runAsync(
      () => rig.services.store.plannedVisits(
        'overdue',
        rig.services.clock.today(),
        limit: 1,
      ),
    ))!.first.visit.visitId;
    await pumpApp(
      t,
      rig,
      home: VisitScreen(visitId: id),
      size: const Size(412, 3000),
    );
    await settle(t, maxRounds: 25);
    expect(englishLeaks(shownText(t)), isEmpty);
  });

  uiTest('Telugu: no English left on a household page', (t) async {
    final rig = (await t.runAsync(() => buildRig(lang: 'te')))!;
    final hh = (await t.runAsync(
      () => rig.services.store.pageHouseholds(
        const HouseholdFilter(),
        limit: 1,
        offset: 0,
      ),
    ))!.first.householdId;
    await pumpApp(
      t,
      rig,
      home: HouseholdDetailScreen(householdId: hh),
      size: const Size(412, 3000),
    );
    await settle(t, maxRounds: 25);
    expect(englishLeaks(shownText(t)), isEmpty);
  });

  // The Ask screen in every outcome the worker can reach.
  final questions = <String, String>{
    'danger sign': 'Pregnant woman is bleeding heavily right now',
    'needs more detail': 'bleeding',
    'medicine / out of scope': 'what dose of paracetamol should I give',
    'cannot verify': 'What should I feed a two year old child',
    'records answer': 'Who should I attend first',
    'records: household': 'next visit for HH-SYN-00005',
    'records: overdue': 'Which households are overdue',
  };
  for (final q in questions.entries) {
    uiTest('Telugu: no English left on the Ask answer (${q.key})', (t) async {
      final rig = (await t.runAsync(
        () => buildRig(lang: 'te', configured: false),
      ))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 4000),
      );
      await t.enterText(find.byKey(const Key('question-field')), q.value);
      await t.tap(find.byKey(const Key('ask-button')));
      await settle(t, maxRounds: 30);
      await settle(t, maxRounds: 6);
      expect(englishLeaks(shownText(t)), isEmpty, reason: q.key);
    });
  }

  // ---- dialogs, menus and error states
  uiTest('Telugu: the "clear data" confirmation dialog', (t) async {
    final rig = (await t.runAsync(() => buildRig(lang: 'te')))!;
    await pumpApp(
      t,
      rig,
      home: const SettingsScreen(),
      size: const Size(412, 4200),
    );
    await settle(t, maxRounds: 20);
    await t.tap(find.byKey(const Key('clear-data')));
    await settle(t, maxRounds: 10);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(englishLeaks(shownText(t)), isEmpty);
  });

  uiTest('Telugu: the household filter menus', (t) async {
    final rig = (await t.runAsync(() => buildRig(lang: 'te')))!;
    await pumpApp(
      t,
      rig,
      home: const HouseholdsScreen(),
      size: const Size(412, 900),
    );
    await settle(t, maxRounds: 20);
    final menus = find.byType(PopupMenuButton<String>);
    for (var i = 0; i < menus.evaluate().length; i++) {
      await t.tap(menus.at(i));
      await settle(t, maxRounds: 6);
      expect(englishLeaks(shownText(t)), isEmpty, reason: 'menu $i');
      await t.tapAt(const Offset(5, 5)); // dismiss
      await settle(t, maxRounds: 6);
    }
  });

  uiTest(
    'Telugu: the visit form with "could not visit", follow-up and referral switched on',
    (t) async {
      final rig = (await t.runAsync(() => buildRig(lang: 'te')))!;
      final id = (await t.runAsync(
        () => rig.services.store.plannedVisits(
          'overdue',
          rig.services.clock.today(),
          limit: 1,
        ),
      ))!.first.visit.visitId;
      await pumpApp(
        t,
        rig,
        home: VisitScreen(visitId: id),
        size: const Size(412, 3000),
      );
      await settle(t, maxRounds: 20);
      for (final k in ['followup-switch', 'referral-switch']) {
        await t.ensureVisible(find.byKey(Key(k)));
        await t.tap(find.byKey(Key(k)));
        await settle(t, maxRounds: 6);
      }
      expect(
        englishLeaks(shownText(t)),
        isEmpty,
        reason: 'completed + switches on',
      );
      // saving with the referral facility empty shows a validation message
      await t.ensureVisible(find.byKey(const Key('save-visit')));
      await t.tap(find.byKey(const Key('save-visit')));
      await settle(t, maxRounds: 10);
      expect(englishLeaks(shownText(t)), isEmpty, reason: 'validation message');
      for (final k in ['outcome-missed', 'outcome-cancelled']) {
        await t.ensureVisible(find.byKey(Key(k)));
        await t.tap(find.byKey(Key(k)));
        await settle(t, maxRounds: 6);
        expect(englishLeaks(shownText(t)), isEmpty, reason: k);
      }
    },
  );

  uiTest('Telugu: sync centre when the server cannot be reached', (t) async {
    final srv = FakeServer()..down = true;
    final rig = (await t.runAsync(() => buildRig(lang: 'te', server: srv)))!;
    await pumpApp(
      t,
      rig,
      home: const SyncScreen(),
      size: const Size(412, 3000),
    );
    await settle(t, maxRounds: 20);
    await t.tap(find.byType(FilledButton).first);
    await settle(t, maxRounds: 25);
    expect(englishLeaks(shownText(t)), isEmpty);
  });

  uiTest('Telugu: sync centre when no server address is set', (t) async {
    final rig = (await t.runAsync(
      () => buildRig(lang: 'te', configured: false),
    ))!;
    await pumpApp(
      t,
      rig,
      home: const SyncScreen(),
      size: const Size(412, 3000),
    );
    await settle(t, maxRounds: 20);
    await t.tap(find.byType(FilledButton).first);
    await settle(t, maxRounds: 25);
    expect(englishLeaks(shownText(t)), isEmpty);
  });

  uiTest('Telugu: Settings after Test connection fails', (t) async {
    final srv = FakeServer()..down = true;
    final rig = (await t.runAsync(() => buildRig(lang: 'te', server: srv)))!;
    await pumpApp(
      t,
      rig,
      home: const SettingsScreen(),
      size: const Size(412, 3000),
    );
    await settle(t, maxRounds: 20);
    final test = find.byType(OutlinedButton).first;
    await t.ensureVisible(test);
    await t.tap(test);
    await settle(t, maxRounds: 25);
    expect(englishLeaks(shownText(t)), isEmpty);
  });

  for (final p in VoiceProblem.values) {
    uiTest('Telugu: voice problem message (${p.name})', (t) async {
      final voice = FakeVoice()..problem = p;
      final rig = (await t.runAsync(() => buildRig(lang: 'te', voice: voice)))!;
      await pumpApp(
        t,
        rig,
        home: const AskScreen(),
        size: const Size(412, 3000),
      );
      await t.tap(find.byKey(const Key('mic-button')));
      await settle(t, maxRounds: 10);
      expect(englishLeaks(shownText(t)), isEmpty, reason: p.name);
    });
  }

  uiTest('Telugu: reports screen after fetching the server report', (t) async {
    final rig = (await t.runAsync(() => buildRig(lang: 'te')))!;
    await pumpApp(
      t,
      rig,
      home: const ReportsScreen(),
      size: const Size(412, 3000),
    );
    await settle(t, maxRounds: 20);
    final b = find.byKey(const Key('server-report'));
    if (b.evaluate().isNotEmpty) {
      await t.ensureVisible(b);
      await t.tap(b);
      await settle(t, maxRounds: 25);
    }
    expect(englishLeaks(shownText(t)), isEmpty);
  });
}
