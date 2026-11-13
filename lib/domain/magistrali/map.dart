import 'dart:math' as math;
import 'dart:typed_data';

import 'config.dart';
import 'entities.dart';

/// A place on the map that makes or takes cargo.
class MagIndustry {
  MagIndustry({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.name,
  });
  final int id;
  final MagIndustryKind kind;

  /// Top-left cell of the footprint.
  final int x, y;
  final String name;

  /// Cargo waiting to be picked up (made or processed here).
  final Map<MagCargo, int> stock = {};

  /// Delivered cargo waiting to be processed.
  final Map<MagCargo, int> input = {};

  /// A warehouse's rules per cargo.
  final Map<MagCargo, MagStockRule> rules = {};

  /// Fractional production carried between days is not needed: production
  /// is whole units per day.
  MagIndustrySpec get spec => MagRules.industries[kind]!;
  int get size => spec.size;
  double get centerX => x + size / 2;
  double get centerY => y + size / 2;

  bool covers(int cx, int cy) =>
      cx >= x && cy >= y && cx < x + size && cy < y + size;

  /// Cargo this place hands to trucks.
  Set<MagCargo> get supplies => {
    if (spec.stores) ...MagCargo.values,
    ...spec.produces.keys,
    ...spec.converts.values,
  };

  /// Manhattan distance between the centres of two places (pay distance).
  int distanceTo(MagIndustry o) =>
      ((centerX - o.centerX).abs() + (centerY - o.centerY).abs()).round();
}

/// The ground: terrain per cell and the places on it, generated from a
/// seed. The same seed always gives the same map, so saves keep only the
/// seed and what changed.
class MagMap {
  MagMap._(this.seed, this.size, this._terrain, this.industries);

  final int seed, size;
  final Uint8List _terrain;
  final List<MagIndustry> industries;

  MagTerrain at(int x, int y) => MagTerrain.values[_terrain[y * size + x]];
  bool inside(int x, int y) => x >= 0 && y >= 0 && x < size && y < size;

  MagIndustry? industryAt(int x, int y) {
    for (final i in industries) {
      if (i.covers(x, y)) return i;
    }
    return null;
  }

  MagIndustry? industry(int id) =>
      industries.where((i) => i.id == id).firstOrNull;

  /// Can a road go on this cell (ignoring money)?
  bool roadable(int x, int y) =>
      inside(x, y) &&
      MagRules.terrainCost(at(x, y)) != null &&
      industryAt(x, y) == null;

  /// The two places of the first, guaranteed line.
  late final MagIndustry startFarm = industries[0];
  late final MagIndustry startPlant = industries[1];

  static const _cities = [
    'Северск',
    'Бирюзов',
    'Мятноград',
    'Заречье',
    'Ясногорск',
    'Сосновка',
    'Каменск',
    'Озёрный',
  ];
  static const _villages = [
    'Луговое',
    'Ольховка',
    'Рябиновка',
    'Ключи',
    'Подгорье',
    'Тихий Брод',
  ];

  static MagMap generate(int seed, {int size = MagRules.mapSize}) {
    final rnd = math.Random(seed);
    final t = Uint8List(size * size);
    double noise(int ox, int oy, double scale, int x, int y) =>
        _valueNoise(seed + ox * 7919 + oy, x / scale, y / scale);

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final elev = noise(1, 0, 11, x, y) * .65 + noise(2, 0, 4.5, x, y) * .35;
        final wood = noise(3, 0, 7, x, y) * .7 + noise(4, 0, 3, x, y) * .3;
        var k = MagTerrain.grass;
        if (elev < .2) {
          k = MagTerrain.lake;
        } else if (elev > .72) {
          k = MagTerrain.hill;
        } else if (wood > .6) {
          k = MagTerrain.forest;
        }
        t[y * size + x] = k.index;
      }
    }
    // A river across the map, meandering.
    var rx = size * (.25 + rnd.nextDouble() * .5);
    for (var y = 0; y < size; y++) {
      rx += (rnd.nextDouble() - .5) * 1.6;
      rx = rx.clamp(3, size - 4.0);
      final c = rx.round();
      for (final x in [c, if (rnd.nextDouble() < .35) c + 1]) {
        if (t[y * size + x] != MagTerrain.lake.index) {
          t[y * size + x] = MagTerrain.river.index;
        }
      }
    }

    final places = <MagIndustry>[];
    var id = 1;
    bool free(int x, int y, int s, {int gap = 2}) {
      if (x < 2 || y < 2 || x + s > size - 2 || y + s > size - 2) return false;
      for (var yy = y; yy < y + s; yy++) {
        for (var xx = x; xx < x + s; xx++) {
          final k = MagTerrain.values[t[yy * size + xx]];
          if (k == MagTerrain.lake || k == MagTerrain.river) return false;
        }
      }
      for (final p in places) {
        if (x < p.x + p.size + gap &&
            p.x < x + s + gap &&
            y < p.y + p.size + gap &&
            p.y < y + s + gap) {
          return false;
        }
      }
      return true;
    }

    void clear(int x, int y, int s) {
      for (var yy = y - 1; yy <= y + s; yy++) {
        for (var xx = x - 1; xx <= x + s; xx++) {
          if (xx < 0 || yy < 0 || xx >= size || yy >= size) continue;
          final k = MagTerrain.values[t[yy * size + xx]];
          if (k != MagTerrain.river && k != MagTerrain.lake) {
            t[yy * size + xx] = MagTerrain.grass.index;
          }
        }
      }
    }

    MagIndustry put(MagIndustryKind kind, int x, int y, String name) {
      final s = MagRules.industries[kind]!.size;
      clear(x, y, s);
      final p = MagIndustry(id: id++, kind: kind, x: x, y: y, name: name);
      places.add(p);
      return p;
    }

    // The first line is guaranteed: a farm and a food plant 10–12 cells
    // apart near the centre, with dry land between them, and a village
    // next to the plant for the food.
    final c = size ~/ 2;
    final fx = c - 7, fy = c - 2, px = c + 4, py = c + 1;
    for (var x = fx; x <= px + 2; x++) {
      for (var y = math.min(fy, py) - 1; y <= math.max(fy, py) + 2; y++) {
        final k = MagTerrain.values[t[y * size + x]];
        if (k == MagTerrain.lake ||
            k == MagTerrain.river ||
            k == MagTerrain.hill) {
          t[y * size + x] = MagTerrain.grass.index;
        }
      }
    }
    put(MagIndustryKind.farm, fx, fy, 'Ферма «Колос»');
    put(MagIndustryKind.foodPlant, px, py, 'Пищевой завод «Нива»');
    var vx = px + 5, vy = py + 5;
    for (var tries = 0; !free(vx, vy, 2, gap: 1) && tries < 40; tries++) {
      vx = px - 4 + rnd.nextInt(10);
      vy = py + 4 + rnd.nextInt(6);
    }
    put(MagIndustryKind.village, vx, vy, _villages[0]);

    // The rest spread over the map.
    const plan = [
      (MagIndustryKind.city, 4),
      (MagIndustryKind.village, 4),
      (MagIndustryKind.farm, 4),
      (MagIndustryKind.sawmill, 4),
      (MagIndustryKind.mine, 3),
      (MagIndustryKind.foodPlant, 2),
      (MagIndustryKind.factory, 3),
    ];
    var cityName = 0, villageName = 1, n = 0;
    for (final (kind, count) in plan) {
      final s = MagRules.industries[kind]!.size;
      for (var i = 0; i < count; i++) {
        for (var tries = 0; tries < 300; tries++) {
          final x = 2 + rnd.nextInt(size - s - 4);
          final y = 2 + rnd.nextInt(size - s - 4);
          // Sawmills want forest, mines want hills nearby.
          if (kind == MagIndustryKind.sawmill &&
              !_near(t, size, x, y, s, MagTerrain.forest) &&
              tries < 200) {
            continue;
          }
          if (kind == MagIndustryKind.mine &&
              !_near(t, size, x, y, s, MagTerrain.hill) &&
              tries < 200) {
            continue;
          }
          if (!free(x, y, s, gap: kind == MagIndustryKind.city ? 4 : 3)) {
            continue;
          }
          n++;
          put(kind, x, y, switch (kind) {
            MagIndustryKind.city => _cities[cityName++ % _cities.length],
            MagIndustryKind.village =>
              _villages[villageName++ % _villages.length],
            MagIndustryKind.farm => 'Ферма №$n',
            MagIndustryKind.sawmill => 'Лесопилка №$n',
            MagIndustryKind.mine => 'Рудник №$n',
            MagIndustryKind.foodPlant => 'Пищевой завод №$n',
            MagIndustryKind.factory => 'Завод №$n',
            MagIndustryKind.warehouse => 'Склад №$n',
          });
          break;
        }
      }
    }
    return MagMap._(seed, size, t, places);
  }

  static bool _near(Uint8List t, int size, int x, int y, int s, MagTerrain k) {
    for (var yy = y - 2; yy < y + s + 2; yy++) {
      for (var xx = x - 2; xx < x + s + 2; xx++) {
        if (xx < 0 || yy < 0 || xx >= size || yy >= size) continue;
        if (t[yy * size + xx] == k.index) return true;
      }
    }
    return false;
  }

  /// Smooth value noise in 0..1.
  static double _valueNoise(int seed, double x, double y) {
    final x0 = x.floor(), y0 = y.floor();
    final fx = x - x0, fy = y - y0;
    double h(int ix, int iy) {
      var n = ix * 374761393 + iy * 668265263 + seed * 2147483647;
      n = (n ^ (n >> 13)) * 1274126177;
      n = n ^ (n >> 16);
      return (n & 0xffff) / 0xffff;
    }

    double s(double v) => v * v * (3 - 2 * v);
    final a = h(x0, y0), b = h(x0 + 1, y0);
    final c = h(x0, y0 + 1), d = h(x0 + 1, y0 + 1);
    final u = s(fx), v = s(fy);
    return (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v;
  }
}
