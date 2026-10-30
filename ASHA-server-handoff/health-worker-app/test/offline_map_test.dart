import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/data/local/local_store.dart';
import 'package:health_companion/maps/offline_map_source.dart';
import 'package:health_companion/presentation/widgets/village_map_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/builders.dart';
import 'support/harness.dart';

// The offline village map: the demo pack, the source that reads it from the phone's own storage, the painter, and the two new
// local-only tables (house position, phone numbers).
void main() {
  sqfliteFfiInit();
  final pack = File('assets/demo/demo_village.json').readAsStringSync();
  final seed = jsonDecode(File('assets/demo/demo_seed.json').readAsStringSync())
      as Map<String, dynamic>;

  test('the demo pack is tiny (APK budget) and every demo household is on the map', () {
    expect(pack.length, lessThan(60 * 1024));
    final map = VillageMap.fromJson(pack);
    expect(map.roads, isNotEmpty);
    expect(map.places.map((p) => p.type), containsAll(['phc', 'school', 'temple']));
    final ids = [for (final h in seed['households'] as List) (h as Map)['household_id'] as String];
    expect(ids, hasLength(80));
    for (final id in ids) {
      expect(map.houses, contains(id));
    }
    // the seed and the pack agree on where each house is
    for (final h in seed['households'] as List) {
      final m = h as Map<String, dynamic>;
      final p = map.houses[m['household_id']]!;
      expect((m['lat'] as num).toDouble(), closeTo(p.lat, 1e-6));
      expect((m['lng'] as num).toDouble(), closeTo(p.lng, 1e-6));
    }
    // every house is inside the map bounds
    for (final p in map.houses.values) {
      expect(p.lat, inInclusiveRange(map.minLat, map.maxLat));
      expect(p.lng, inInclusiveRange(map.minLng, map.maxLng));
    }
  });

  test('a damaged or unknown pack is refused cleanly', () {
    expect(() => VillageMap.fromJson('not json'), throwsFormatException);
    expect(() => VillageMap.fromJson('{"v":2}'), throwsFormatException);
    expect(() => VillageMap.fromJson('{"v":1,"id":"x"}'), throwsFormatException);
  });

  group('JsonPackMapSource', () {
    late Directory dir;
    late JsonPackMapSource src;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('mapsrc_');
      src = JsonPackMapSource(baseDir: () async => dir, demoPack: () async => pack);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('missing until installed, then available, loadable and removable', () async {
      expect(await src.isAvailable(), isFalse);
      expect(await src.load(), isNull);
      await src.installDemoPack();
      expect(await src.isAvailable(), isTrue);
      final m = await src.load();
      expect(m, isNotNull);
      expect(m!.houses, hasLength(80));
      await src.remove();
      expect(await src.isAvailable(), isFalse);
      expect(await src.load(), isNull);
    });

    test('a damaged pack file reads as "no map", not a crash', () async {
      File('${dir.path}/maps/village.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{broken');
      expect(await src.isAvailable(), isTrue);
      expect(await src.load(), isNull);
    });
  });

  testWidgets('the map paints with no network: whole village, focused house, and the big interactive view', (t) async {
    final map = VillageMap.fromJson(pack);
    const id = 'HH-SYN-00001';
    for (final (focus, interactive) in [(false, false), (true, false), (false, true)]) {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 300,
              child: VillageMapView(map: map, selectedHouseId: id, focus: focus, interactive: interactive),
            ),
          ),
        ),
      );
      expect(t.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    }
  });

  group('local-only tables (migration 6)', () {
    test('upgrading from v5 keeps existing rows and adds the new tables', () async {
      final path = await tempDbPath();
      final v5 = await openTestDb(path: path, target: 5);
      await LocalStore(v5).upsertHouseholds([hh('HH-A')], respectPending: false);
      await v5.close();
      final v6 = await openTestDb(path: path);
      final s = LocalStore(v6);
      expect((await s.household('HH-A'))!.memberCount, 4);
      expect(await s.geoCount(), 0);
      expect(await s.contactsFor('HH-A'), isNull);
      await v6.close();
    });

    test('position and phone numbers are saved, replaced, and removed by "delete all data"', () async {
      final adb = await openTestDb();
      final s = LocalStore(adb);
      await s.upsertHouseholds([hh('HH-A')], respectPending: false);
      await s.setGeo({'HH-A': (16.5, 80.7)});
      expect(await s.geoFor('HH-A'), (16.5, 80.7));
      await s.saveContacts('HH-A', '9876543210', null, DateTime.utc(2026, 10, 29));
      expect(await s.contactsFor('HH-A'), ('9876543210', null));
      await s.saveContacts('HH-A', '9876543210', '8123456789', DateTime.utc(2026, 10, 29));
      expect(await s.contactsFor('HH-A'), ('9876543210', '8123456789'));
      // a pull from the server replaces the household row: position and numbers must survive that
      await s.upsertHouseholds([hh('HH-A')], respectPending: false);
      expect(await s.geoFor('HH-A'), isNotNull);
      expect(await s.contactsFor('HH-A'), isNotNull);
      await s.wipe();
      expect(await s.geoCount(), 0);
      expect(await s.contactsFor('HH-A'), isNull);
      await adb.close();
    });
  });
}
