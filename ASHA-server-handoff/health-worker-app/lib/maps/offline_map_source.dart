import 'dart:convert';
import 'dart:io';

/// A point on the map.
class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat, lng;
}

class MapRoad {
  const MapRoad(this.name, this.major, this.points);
  final String name;

  /// true = the main road (drawn thicker).
  final bool major;
  final List<LatLng> points;
}

/// A landmark: type is 'phc', 'school' or 'temple' (anything else is drawn as a plain dot).
class MapPlace {
  const MapPlace(this.name, this.type, this.at);
  final String name, type;
  final LatLng at;
}

/// One village: roads, landmarks and one point per household. Everything is plain data, so a different pack format (for example the real
/// MBTiles pack later) only has to produce this same object.
class VillageMap {
  const VillageMap({
    required this.id,
    required this.name,
    required this.minLat,
    required this.minLng,
    required this.maxLat,
    required this.maxLng,
    required this.roads,
    required this.places,
    required this.houses,
  });
  final String id, name;
  final double minLat, minLng, maxLat, maxLng;
  final List<MapRoad> roads;
  final List<MapPlace> places;
  final Map<String, LatLng> houses;

  /// Parses the compact pack JSON (see tool/make_demo_map.py). Throws FormatException on a damaged pack.
  factory VillageMap.fromJson(String text) {
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (j['v'] != 1) throw const FormatException('unknown pack version');
      LatLng pt(Object? p) {
        final l = p! as List;
        return LatLng((l[0] as num).toDouble(), (l[1] as num).toDouble());
      }

      final b = (j['bounds'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
      return VillageMap(
        id: j['id'] as String,
        name: j['name'] as String,
        minLat: b[0],
        minLng: b[1],
        maxLat: b[2],
        maxLng: b[3],
        roads: [
          for (final r in j['roads'] as List)
            MapRoad((r as Map)['n'] as String, r['k'] == 2, [
              for (final p in r['p'] as List) pt(p),
            ]),
        ],
        places: [
          for (final p in j['places'] as List)
            MapPlace((p as Map)['n'] as String, p['t'] as String, pt(p['p'])),
        ],
        houses: {
          for (final h in j['houses'] as List)
            (h as List)[0] as String: LatLng(
              (h[1] as num).toDouble(),
              (h[2] as num).toDouble(),
            ),
        },
      );
    } on FormatException {
      rethrow;
    } on Object catch (e) {
      throw FormatException('damaged map pack: $e');
    }
  }
}

/// The only thing the screens know about maps. The demo reads a small JSON pack from the phone's own storage; the real pack
/// (MBTiles, 5-6 MB) would be another implementation of this interface, so no screen has to change.
abstract class OfflineMapSource {
  /// True when a map pack is on this phone (the chip on the Households screen says so).
  Future<bool> isAvailable();

  /// The village map, or null when there is no pack (or it is damaged).
  Future<VillageMap?> load();
}

/// Reads `<dir>/maps/village.json`. [installDemoPack] copies the bundled demo pack there: it stands in for "download the map pack".
class JsonPackMapSource implements OfflineMapSource {
  JsonPackMapSource({
    required Future<Directory> Function() baseDir,
    required Future<String> Function() demoPack,
  }) : _base = baseDir,
       _demo = demoPack;
  final Future<Directory> Function() _base;
  final Future<String> Function() _demo;
  VillageMap? _cache;

  Future<File> _file() async => File(
    '${(await _base()).path}${Platform.pathSeparator}maps${Platform.pathSeparator}village.json',
  );

  @override
  Future<bool> isAvailable() async => (await _file()).existsSync();

  @override
  Future<VillageMap?> load() async {
    if (_cache != null) return _cache;
    try {
      final f = await _file();
      if (!f.existsSync()) return null;
      return _cache = VillageMap.fromJson(await f.readAsString());
    } on Object {
      return null;
    }
  }

  Future<void> installDemoPack() async {
    final f = await _file();
    f.parent.createSync(recursive: true);
    await f.writeAsString(await _demo());
    _cache = null;
  }

  /// "Delete all data on this phone" also removes the map pack.
  Future<void> remove() async {
    final f = await _file();
    if (f.existsSync()) f.deleteSync();
    _cache = null;
  }
}
