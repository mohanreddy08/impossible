import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/h5/h5_visit_list.dart';

/// The visit list for all 2,234 register members, built on the phone, must equal the one the Python engine wrote for the hackathon
/// submission (which scores 1.000 on the dev truth). Golden: health-worker-backend/h5 (see docs/H5.md). Skipped without it.
void main() {
  final golden = File(Platform.environment['H5_GOLDEN_VISIT'] ?? '/private/tmp/h5work/golden_visit.json');
  test('Dart visit list == Python visit list (today 2026-10-26)', () {
    final reg = jsonDecode(File('assets/h5/register.json').readAsStringSync()) as Map<String, dynamic>;
    final cols = (reg['cols'] as List).cast<String>();
    final members = [
      for (final row in (reg['rows'] as List)) {for (var i = 0; i < cols.length; i++) cols[i]: '${(row as List)[i] ?? ''}'},
    ];
    final mine = buildVisitList(members, day(2026, 10, 26)).map((r) => r.toList().join('|')).toList()..sort();
    final theirs = [for (final r in (jsonDecode(golden.readAsStringSync()) as List)) (r as List).join('|')]..sort();
    expect(members.length, 2234);
    expect(theirs.length, greaterThan(100));
    expect(mine, theirs);
  }, skip: golden.existsSync() ? false : 'golden file not found');
}
