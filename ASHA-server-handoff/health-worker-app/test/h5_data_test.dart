import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/h5/h5_data.dart';

void main() {
  test('the bundled Chandrapuri data loads: 500 houses, 2,234 people, 6 village maps, a visit list', () async {
    final d = await H5Data.load((p) async => File(p).readAsString());
    expect(d.households.length, 500);
    expect(d.members.length, 2234);
    expect(d.maps.length, 6);
    expect(d.visitRows.length, 346);
    // every house has a point on its village's map, and the map has exactly the village's houses
    for (final v in d.villages) {
      final m = d.maps[v.slug]!;
      expect(m.houses.length, v.households, reason: v.name);
      for (final h in d.householdsOf(v.name)) {
        expect(m.houses.containsKey(h.id), isTrue, reason: h.id);
      }
    }
    expect(d.block.houses.length, 500);
    // a house with a priority-1 item is "urgent"
    final urgent = d.households.where((h) => d.levelOf(h.id) == H5Level.urgent).length;
    expect(urgent, greaterThan(0));
    // every household's head is in the register and heads the house
    for (final h in d.households) {
      expect(d.memberById[h.headMember], isNotNull, reason: h.id);
    }
  });
}
