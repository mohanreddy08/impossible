import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../maps/offline_map_source.dart';
import 'h5_visit_list.dart';

/// The visit list in the hackathon pack is made "as of" this day (README: today = 2026-10-26).
final DateTime h5Today = DateTime.utc(2026, 10, 26);

class H5Household {
  const H5Household({
    required this.id,
    required this.village,
    required this.asha,
    required this.houseNo,
    required this.head,
    required this.headMember,
    required this.members,
    required this.lat,
    required this.lng,
  });
  final String id, village, asha, houseNo, head, headMember;
  final int members;
  final double lat, lng;
  LatLng get at => LatLng(lat, lng);
}

class H5Member {
  const H5Member(this.row);
  final Map<String, String> row;
  String get id => row['member_id'] ?? '';
  String get householdId => row['household_id'] ?? '';
  String get name => row['name'] ?? '';
  String get relation => row['relation'] ?? '';
  String get sex => row['sex'] ?? '';
  DateTime? get dob => parseDate(row['dob']);
  bool get pregnant => (row['pregnant'] ?? '').trim().toUpperCase() == 'Y';

  /// "34 y", "5 m" or "12 d": age on [today], as a health worker reads it.
  String ageText(DateTime today) {
    final d = dob;
    if (d == null) return '';
    final days = daysBetween(today, d);
    if (days < 60) return '$days d';
    if (days < 730) return '${(days / 30.44).floor()} m';
    return '${(days / 365.25).floor()} y';
  }
}

class H5Asha {
  const H5Asha(this.id, this.name, this.villages);
  final String id, name;
  final List<String> villages;
}

class H5Village {
  const H5Village(this.name, this.slug, this.households);
  final String name, slug;
  final int households;
}

/// How soon a house needs a visit, by its most urgent due item (VIS-1.2: priority 1 = high-risk and overdue/today).
enum H5Level { urgent, due, soon, none }

H5Level levelOfPriority(int p) => switch (p) {
      1 => H5Level.urgent,
      2 => H5Level.due,
      _ => H5Level.soon,
    };

/// Everything of the Chandrapuri block that the app shows: 500 houses, 2,234 people, the six village maps and the visit list for
/// [today]. All of it is read from files bundled in the app, so it works with no internet.
class H5Data {
  H5Data._({
    required this.today,
    required this.households,
    required this.members,
    required this.ashas,
    required this.villages,
    required this.maps,
    required this.visitRows,
  }) {
    for (final h in households) {
      byId[h.id] = h;
    }
    for (final m in members) {
      membersOf.putIfAbsent(m.householdId, () => []).add(m);
      memberById[m.id] = m;
    }
    for (final r in visitRows) {
      final m = memberById[r.memberId];
      if (m == null) continue;
      itemsOfMember.putIfAbsent(r.memberId, () => []).add(r);
      itemsOfHousehold.putIfAbsent(m.householdId, () => []).add(r);
    }
  }

  final DateTime today;
  final List<H5Household> households;
  final List<H5Member> members;
  final List<H5Asha> ashas;
  final List<H5Village> villages;

  /// village slug -> its offline map.
  final Map<String, VillageMap> maps;
  final List<H5VisitRow> visitRows;

  final Map<String, H5Household> byId = {};
  final Map<String, H5Member> memberById = {};
  final Map<String, List<H5Member>> membersOf = {};
  final Map<String, List<H5VisitRow>> itemsOfMember = {};
  final Map<String, List<H5VisitRow>> itemsOfHousehold = {};

  static String slugOf(String village) => village.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

  /// Most urgent level among the house's due items.
  H5Level levelOf(String householdId) {
    final items = itemsOfHousehold[householdId];
    if (items == null || items.isEmpty) return H5Level.none;
    return levelOfPriority(items.map((r) => r.priority).reduce((a, b) => a < b ? a : b));
  }

  /// The village map that covers this point (a little margin around the village), or null.
  VillageMap? mapContaining(LatLng p, {double margin = 0.0015}) {
    for (final m in maps.values) {
      if (p.lat >= m.minLat - margin && p.lat <= m.maxLat + margin && p.lng >= m.minLng - margin && p.lng <= m.maxLng + margin) return m;
    }
    return null;
  }

  List<H5Household> householdsOf(String village) => [for (final h in households) if (h.village == village) h];

  H5Village? villageNamed(String name) {
    for (final v in villages) {
      if (v.name == name) return v;
    }
    return null;
  }

  /// All six villages in one picture (the block overview): the roads, places and houses of every village pack.
  VillageMap get block {
    final all = maps.values.toList();
    return VillageMap(
      id: 'H5-BLOCK',
      name: 'Chandrapuri block (made-up map, not a real place)',
      minLat: all.map((m) => m.minLat).reduce((a, b) => a < b ? a : b),
      minLng: all.map((m) => m.minLng).reduce((a, b) => a < b ? a : b),
      maxLat: all.map((m) => m.maxLat).reduce((a, b) => a > b ? a : b),
      maxLng: all.map((m) => m.maxLng).reduce((a, b) => a > b ? a : b),
      roads: [for (final m in all) ...m.roads],
      // each village's name, drawn just above it (north of its roads) when the whole block is in view
      places: [
        for (final v in villages)
          if (maps[v.slug] != null)
            MapPlace(v.name, 'village', LatLng(maps[v.slug]!.maxLat + 0.0013, (maps[v.slug]!.minLng + maps[v.slug]!.maxLng) / 2)),
        for (final m in all) ...m.places,
      ],
      houses: {for (final m in all) ...m.houses},
    );
  }

  static Future<H5Data> load([Future<String> Function(String path)? read]) async {
    final rd = read ?? rootBundle.loadString;
    final hh = jsonDecode(await rd('assets/h5/households.json')) as List;
    final reg = jsonDecode(await rd('assets/h5/register.json')) as Map<String, dynamic>;
    final ash = jsonDecode(await rd('assets/h5/ashas.json')) as Map<String, dynamic>;
    final villages = [
      for (final v in (ash['villages'] as List).cast<Map<String, dynamic>>()) H5Village(v['village'] as String, v['slug'] as String, v['households'] as int),
    ];
    final maps = <String, VillageMap>{
      for (final v in villages) v.slug: VillageMap.fromJson(await rd('assets/h5/maps/${v.slug}.json')),
    };
    return fromParts(hh, reg, ash, villages, maps);
  }

  static H5Data fromParts(List hh, Map<String, dynamic> reg, Map<String, dynamic> ash, List<H5Village> villages, Map<String, VillageMap> maps) {
    final cols = (reg['cols'] as List).cast<String>();
    final rows = [
      for (final row in (reg['rows'] as List)) {for (var i = 0; i < cols.length; i++) cols[i]: '${(row as List)[i] ?? ''}'},
    ];
    return H5Data._(
      today: h5Today,
      households: [
        for (final h in hh.cast<Map<String, dynamic>>())
          H5Household(
            id: h['id'] as String,
            village: h['village'] as String,
            asha: h['asha'] as String,
            houseNo: h['house_no'] as String,
            head: h['head'] as String,
            headMember: h['head_member'] as String,
            members: h['members'] as int,
            lat: (h['lat'] as num).toDouble(),
            lng: (h['lng'] as num).toDouble(),
          ),
      ],
      members: [for (final r in rows) H5Member(r)],
      ashas: [
        for (final a in (ash['ashas'] as List).cast<Map<String, dynamic>>())
          H5Asha(a['id'] as String, a['name'] as String, [for (final v in (a['villages'] as List)) v as String]),
      ],
      villages: villages,
      maps: maps,
      visitRows: buildVisitList(rows, h5Today),
    );
  }
}
