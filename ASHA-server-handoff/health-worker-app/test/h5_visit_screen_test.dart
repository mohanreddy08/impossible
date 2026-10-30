import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/presentation/screens/h5_house_screen.dart';
import 'package:health_companion/presentation/screens/h5_visit_list_screen.dart';
import 'package:health_companion/presentation/screens/more_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

void main() {
  sqfliteFfiInit();

  uiTest('More has the visit list and the houses map', (t) async {
    final rig = (await t.runAsync(() => buildRig(configured: false)))!;
    await pumpApp(t, rig, home: const MoreScreen());
    expect(find.byKey(const Key('more-h5-visits')), findsOneWidget);
    expect(find.byKey(const Key('more-h5-map')), findsOneWidget);
  });

  uiTest('the visit list shows the official rows by priority, one ASHA at a time, and opens a house', (t) async {
    final rig = (await t.runAsync(() => buildRig(configured: false)))!;
    await pumpApp(t, rig, home: const H5VisitListScreen(), size: const Size(412, 892));
    await settle(t, maxRounds: 25);
    final d = (await t.runAsync(h5ForTests))!;
    expect(d.visitRows.length, 346);
    expect(find.text('As of 2026-10-26. 346 items.'), findsOneWidget);
    expect(find.text('Priority 1: high risk, due now'), findsOneWidget);
    // choosing an ASHA keeps only her villages' rows; the five add up to everything
    var total = 0;
    for (final a in d.ashas) {
      final mine = d.visitRows.where((r) => d.byId[d.memberById[r.memberId]!.householdId]!.asha == a.id).length;
      total += mine;
    }
    expect(total, 346);
    final a = d.ashas.first;
    await t.scrollUntilVisible(find.byKey(Key('visit-asha-${a.id}')), 100, scrollable: find.byType(Scrollable).first, maxScrolls: 10);
    await t.ensureVisible(find.byKey(Key('visit-asha-${a.id}')));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.byKey(Key('visit-asha-${a.id}')));
    await settle(t, maxRounds: 10);
    final mine = d.visitRows.where((r) => d.byId[d.memberById[r.memberId]!.householdId]!.asha == a.id).length;
    expect(find.text('As of 2026-10-26. $mine items.'), findsOneWidget);
    // tap the first row: the house opens
    final first = (d.visitRows.where((r) => d.byId[d.memberById[r.memberId]!.householdId]!.asha == a.id).toList()
          ..sort((x, y) => x.priority != y.priority ? x.priority.compareTo(y.priority) : x.dueDate != y.dueDate ? x.dueDate.compareTo(y.dueDate) : x.memberId.compareTo(y.memberId)))
        .first;
    final key = Key('visit-${first.memberId}-${first.item}');
    await t.scrollUntilVisible(find.byKey(key), 200, scrollable: find.byType(Scrollable).last, maxScrolls: 30);
    await t.ensureVisible(find.byKey(key));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.byKey(key));
    await settle(t, maxRounds: 25);
    expect(find.byType(H5HouseScreen), findsOneWidget);
    expect(find.text(d.memberById[first.memberId]!.name), findsWidgets);
  });
}
