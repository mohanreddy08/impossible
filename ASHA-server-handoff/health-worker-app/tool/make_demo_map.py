#!/usr/bin/env python3
"""Makes the DEMO village map: puts a lat/lng on every household in assets/demo/demo_seed.json and writes assets/demo/demo_village.json
(roads, a few landmarks, one point per household). The village is made up (a street grid with one curved main road): it is NOT a real place.
Deterministic: running it again gives the same files. The real map would arrive as a separate downloaded pack (5-6 MB at most), read by
the same OfflineMapSource interface (lib/maps/offline_map_source.dart); this demo pack is only about 15 KB.
    python3 tool/make_demo_map.py
"""
import json, math, os, random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = os.path.join(ROOT, 'assets/demo/demo_seed.json')
PACK = os.path.join(ROOT, 'assets/demo/demo_village.json')
LAT0, LNG0 = 16.5000, 80.7000          # centre of the made-up village
M_LAT = 1 / 111320.0                    # degrees of latitude per metre
M_LNG = 1 / (111320.0 * math.cos(math.radians(LAT0)))


def ll(x, y):  # metres east / north of the centre -> [lat, lng]
    return [round(LAT0 + y * M_LAT, 6), round(LNG0 + x * M_LNG, 6)]


def main():
    rnd = random.Random(20261013)
    seed = json.load(open(SEED, encoding='utf-8'))
    ids = [h['household_id'] for h in seed['households']]

    # streets: 6 east-west, 7 north-south, 90 m apart, plus a curved main road through the middle
    ew = [-225, -135, -45, 45, 135, 225]
    ns = [-270, -180, -90, 0, 90, 180, 270]
    roads = []
    for i, y in enumerate(ew):
        roads.append({'n': f'Street {i + 1}', 'k': 1, 'p': [ll(-300, y), ll(300, y)]})
    for i, x in enumerate(ns):
        roads.append({'n': f'Lane {i + 1}', 'k': 1, 'p': [ll(x, -255), ll(x, 255)]})
    main = [ll(-320 + i * 40, 20 * math.sin(i / 2.2) + 10) for i in range(17)]
    roads.append({'n': 'Main road', 'k': 2, 'p': main})

    # houses: spread along the streets, a little off the road, never twice in the same place
    spots = []
    for y in ew:
        for x in range(-285, 286, 30):
            spots.append((x + rnd.uniform(-4, 4), y + rnd.choice((-1, 1)) * rnd.uniform(9, 14)))
    rnd.shuffle(spots)
    houses = []
    for hid, (x, y) in zip(ids, spots):
        houses.append([hid] + ll(x, y))

    places = [
        {'n': 'PHC', 't': 'phc', 'p': ll(-90, 135 + 25)},
        {'n': 'School', 't': 'school', 'p': ll(180, -45 - 28)},
        {'n': 'Temple', 't': 'temple', 'p': ll(0, 45 + 30)},
    ]
    lats = [p[0] for r in roads for p in r['p']]
    lngs = [p[1] for r in roads for p in r['p']]
    pack = {
        'v': 1,
        'id': 'DEMO-VILLAGE-01',
        'name': 'Demo village (made up, not a real map)',
        'bounds': [min(lats), min(lngs), max(lats), max(lngs)],
        'roads': roads,
        'places': places,
        'houses': houses,
    }
    json.dump(pack, open(PACK, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))

    pos = {h[0]: (h[1], h[2]) for h in houses}
    for h in seed['households']:
        h['lat'], h['lng'] = pos[h['household_id']]
    json.dump(seed, open(SEED, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
    print('households with a position:', len(houses), '| pack bytes:', os.path.getsize(PACK), '| seed bytes:', os.path.getsize(SEED))


if __name__ == '__main__':
    main()
