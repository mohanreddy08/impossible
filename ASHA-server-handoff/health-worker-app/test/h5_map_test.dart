import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/h5/h5_data.dart';
import 'package:health_companion/maps/offline_map_source.dart';
import 'package:health_companion/presentation/screens/add_household_screen.dart';
import 'package:health_companion/presentation/screens/h5_house_screen.dart';
import 'package:health_companion/presentation/screens/h5_map_screen.dart';
import 'package:health_companion/presentation/screens/households_screen.dart';
import 'package:health_companion/presentation/widgets/village_map_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

// The Chandrapuri map: the Offline map chip opens a map of every house in the data, and a new family can be placed on it.
void main() {
  sqfliteFfiInit();

  group('painter geometry (what a tap means)', () {
    late H5Data d;
    setUpAll(() async => d = await h5ForTests());

    test('every house of every village is found again by tapping exactly where it is drawn', () {
      for (final v in d.villages) {
        final map = d.maps[v.slug]!;
        final p = VillageMapPainter(map);
        const size = Size(380, 520);
        for (final e in map.houses.entries) {
          final px = p.project(e.value, size);
          // the nearest house to its own drawn point is itself (houses are metres apart, drawn pixels apart)
          final hit = p.houseAt(px, size);
          final back = p.unproject(px, size);
          expect(back.lat, closeTo(e.value.lat, 1e-7));
          expect(back.lng, closeTo(e.value.lng, 1e-7));
          expect(hit, isNotNull);
          final hp = p.project(map.houses[hit]!, size);
          expect((hp - px).distance, lessThan(1.0), reason: '${e.key} in ${v.name}');
        }
      }
    });

    test('the block overview has all 500 houses and every house point lies inside it', () {
      final b = d.block;
      expect(b.houses.length, 500);
      for (final p in b.houses.values) {
        expect(p.lat, inInclusiveRange(b.minLat, b.maxLat));
        expect(p.lng, inInclusiveRange(b.minLng, b.maxLng));
      }
    });

    test('a point is matched to the village map that covers it', () {
      for (final v in d.villages) {
        final map = d.maps[v.slug]!;
        final h = map.houses.values.first;
        expect(d.mapContaining(h)?.id, map.id);
      }
      expect(d.mapContaining(const LatLng(10, 10)), isNull);
    });
  });

  group('screens', () {
    uiTest('the Offline map chip on Households says how many houses and opens the map of all of them', (t) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      await pumpApp(t, rig, home: const HouseholdsScreen(), size: const Size(412, 892));
      await settle(t, maxRounds: 20);
      expect(find.text('Offline map: 500 houses. Tap to open.'), findsOneWidget);
      await t.tap(find.byKey(const Key('offline-map-chip')));
      await settle(t, maxRounds: 25);
      expect(find.byType(H5MapScreen), findsOneWidget);
      // all six villages and "all villages" are offered
      expect(find.byKey(const Key('map-village-all')), findsOneWidget);
      for (final slug in ['amrapur', 'belwadi-tola', 'dhanpura', 'kesarganj', 'navagaon-khurd', 'sitapahari']) {
        // the chips are a horizontal list that builds the ones in view: scroll to each
        await t.scrollUntilVisible(find.byKey(Key('map-village-$slug')), 120, scrollable: find.byType(Scrollable).first, maxScrolls: 20);
        expect(find.byKey(Key('map-village-$slug')), findsOneWidget, reason: slug);
      }
      final view = t.widget<VillageMapView>(find.byKey(const Key('h5-map')));
      expect(view.map.houses.length, 500);
      expect(view.houseColors!.length, 500);
      expect(find.text('Made-up map. The house positions are not real.  Visit list as of 2026-10-26'), findsOneWidget);
    });

    uiTest('choosing a village shows just its houses; tapping a house shows who lives there and opens it', (t) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      await pumpApp(t, rig, home: const H5MapScreen(), size: const Size(412, 892));
      await settle(t, maxRounds: 25);
      await t.scrollUntilVisible(find.byKey(const Key('map-village-sitapahari')), 120, scrollable: find.byType(Scrollable).first, maxScrolls: 20);
      await t.ensureVisible(find.byKey(const Key('map-village-sitapahari')));
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(find.byKey(const Key('map-village-sitapahari')), warnIfMissed: true);
      await settle(t, maxRounds: 10);
      final view = t.widget<VillageMapView>(find.byKey(const Key('h5-map')));
      expect(view.map.houses.length, 44);
      final d = (await t.runAsync(h5ForTests))!;
      final h = d.householdsOf('Sitapahari').first;
      view.onHouseTap!(h.id);
      await settle(t, maxRounds: 8);
      expect(find.text(h.head), findsOneWidget);
      await t.tap(find.byKey(const Key('map-open-house')));
      await settle(t, maxRounds: 25);
      expect(find.byType(H5HouseScreen), findsOneWidget);
      expect(find.text('People in this house'), findsOneWidget);
      for (final m in d.membersOf[h.id]!) {
        expect(find.text(m.name), findsWidgets, reason: m.name);
      }
    });

    uiTest('Add family: pick the house on the map, save, and the point is kept for that family', (t) async {
      final rig = (await t.runAsync(() => buildRig(configured: false)))!;
      await pumpApp(t, rig, home: const AddHouseholdScreen(), size: const Size(412, 1400));
      await settle(t, maxRounds: 20);
      // the Chandrapuri villages are offered as chips
      expect(find.byKey(const Key('village-Amrapur')), findsOneWidget);
      await t.tap(find.byKey(const Key('village-Amrapur')));
      await t.pump();
      expect(find.text('No location chosen yet.'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('pick-location')));
      await t.tap(find.byKey(const Key('pick-location')));
      await settle(t, maxRounds: 15);
      // Use is disabled until a spot is tapped
      expect(t.widget<FilledButton>(find.byKey(const Key('picker-use'))).onPressed, isNull);
      final d = (await t.runAsync(h5ForTests))!;
      final amr = d.maps['amrapur']!;
      final spot = LatLng((amr.minLat + amr.maxLat) / 2, (amr.minLng + amr.maxLng) / 2);
      t.widget<VillageMapView>(find.byKey(const Key('picker-map'))).onTapAt!(spot);
      await t.pump();
      expect(t.widget<FilledButton>(find.byKey(const Key('picker-use'))).onPressed, isNotNull);
      await t.tap(find.byKey(const Key('picker-use')));
      await settle(t, maxRounds: 15);
      expect(find.textContaining('Chosen: ${spot.lat.toStringAsFixed(5)}'), findsOneWidget);
      final before = (await t.runAsync(() => rig.services.store.geoAll()))!.keys.toSet();
      await t.ensureVisible(find.byKey(const Key('add-family-save')));
      await t.tap(find.byKey(const Key('add-family-save')));
      await settle(t, maxRounds: 30);
      final geo = (await t.runAsync(() => rig.services.store.geoAll()))!;
      final mine = geo.entries.where((e) => !before.contains(e.key)).toList();
      expect(mine, hasLength(1));
      expect(mine.single.value.$1, closeTo(spot.lat, 1e-6));
      expect(mine.single.value.$2, closeTo(spot.lng, 1e-6));
      // and the new family shows up on the village map, in the village it was placed in
      final map = d.mapContaining(spot)!;
      expect(map.id, amr.id);
    });
  });
}
