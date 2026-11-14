import 'dart:math' as math;
import 'dart:typed_data';

import 'config.dart';
import 'entities.dart';
import 'settlements.dart';

part 'map_names.dart';
part 'map_noise.dart';

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

  /// A settlement's life (towns and villages); its land is [MagSettlement.cells].
  MagSettlement? town;

  /// Owned by the player (bought or built) and its modernisation level.
  bool owned = false;
  int level = 1;

  /// Built by the player (not part of the generated map).
  bool built = false;

  /// What owning it has cost and brought (management figures, credits),
  /// and units it made and sold to outside buyers.
  int invested = 0, revenue = 0, costs = 0, produced = 0, sold = 0;

  /// Tick it became the company's (null: not known, e.g. an older save).
  int? since;

  /// A megaproject (stage S10): which, the city it is for, what it needs,
  /// what has arrived, and whether it is done.
  String? project;
  int? projectTown;
  final Map<MagCargo, int> projectNeeds = {}, projectProgress = {};
  bool projectDone = false;

  /// Cargo a megaproject still waits for.
  Map<MagCargo, int> get projectLeft => {
    for (final e in projectNeeds.entries)
      if ((projectProgress[e.key] ?? 0) < e.value)
        e.key: e.value - (projectProgress[e.key] ?? 0),
  };

  /// A logistics centre: what it supplies, and how many orders it wrote.
  bool supplyPlants = true, supplyTowns = true;
  int ordersMade = 0;

  /// Fractional production carried between days is not needed: production
  /// is whole units per day.
  MagIndustrySpec get spec => MagRules.industries[kind]!;
  int get size => spec.size;

  /// Centre of its land (a settlement: the middle of all its cells, which
  /// for an old square town is exactly where its centre always was).
  double get centerX => town != null
      ? town!.cells.fold(0, (a, k) => a + MagSettlement.keyX(k)) /
                town!.cells.length +
            .5
      : x + size / 2;
  double get centerY => town != null
      ? town!.cells.fold(0, (a, k) => a + MagSettlement.keyY(k)) /
                town!.cells.length +
            .5
      : y + size / 2;

  bool covers(int cx, int cy) => town != null
      ? town!.cells.contains(MagSettlement.key(cx, cy))
      : cx >= x && cy >= y && cx < x + size && cy < y + size;

  /// Bounds of the land it covers (inclusive).
  int get left =>
      town == null ? x : _bound((k) => MagSettlement.keyX(k), false);
  int get right =>
      town == null ? x + size - 1 : _bound((k) => MagSettlement.keyX(k), true);
  int get top => town == null ? y : _bound((k) => MagSettlement.keyY(k), false);
  int get bottom =>
      town == null ? y + size - 1 : _bound((k) => MagSettlement.keyY(k), true);

  int _bound(int Function(int) of, bool max) {
    var v = max ? -1 << 30 : 1 << 30;
    for (final k in town!.cells) {
      final c = of(k);
      if (max ? c > v : c < v) v = c;
    }
    return v;
  }

  /// Cargo it takes: a settlement takes what its level needs and what
  /// its growth asks for.
  Set<MagCargo> get accepts => kind == MagIndustryKind.megaproject
      ? projectLeft.keys.toSet()
      : town == null
      ? spec.accepts.where((c) => c != MagCargo.passengers).toSet()
      : {
          ...town!.spec.needs.keys,
          ...town!.spec.development.keys,
          ...MagTowns.marketGoods(town!.level, town!.specialization),
          MagCargo.passengers,
        };

  /// Cargo this place hands to trucks.
  Set<MagCargo> get supplies => {
    if (spec.stores) ...MagCargo.values.where((c) => c != MagCargo.passengers),
    ...spec.produces.keys,
    ...spec.converts.values,
    // Settlements send people (stage S11).
    if (town != null) MagCargo.passengers,
  };

  /// Manhattan distance between the centres of two places (pay distance).
  int distanceTo(MagIndustry o) =>
      ((centerX - o.centerX).abs() + (centerY - o.centerY).abs()).round();
}

/// The ground: terrain per cell and the places on it, generated from a
/// seed. The same seed always gives the same map, so saves keep only the
/// seed and what changed.
class MagMap {
  MagMap._(this.seed, this.size, this._terrain, this.industries, this.version);

  final int seed, size;

  /// Generator version: 1 for maps made before 1.72 (towns of fixed
  /// size), 2 for new games (hamlets with room to grow).
  final int version;
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

  /// Grows a set of cells to [target] cells: the free neighbour touching
  /// the most cells already in it goes first (compact land), ties by
  /// position, so the result is always the same. Returns false if not
  /// enough free land was found.
  static bool expandCells(
    Set<int> cells,
    int target,
    bool Function(int x, int y) free,
  ) {
    while (cells.length < target) {
      int? best;
      var bestScore = -1;
      final seen = <int>{};
      for (final k in cells.toList()..sort()) {
        final x = MagSettlement.keyX(k), y = MagSettlement.keyY(k);
        for (var d = 0; d < 4; d++) {
          final nx = x + MagDir.dx[d], ny = y + MagDir.dy[d];
          final nk = MagSettlement.key(nx, ny);
          if (nx < 0 || ny < 0 || cells.contains(nk) || !seen.add(nk)) {
            continue;
          }
          if (!free(nx, ny)) continue;
          var score = 0;
          for (var e = 0; e < 4; e++) {
            if (cells.contains(
              MagSettlement.key(nx + MagDir.dx[e], ny + MagDir.dy[e]),
            )) {
              score++;
            }
          }
          if (score > bestScore || score == bestScore && nk < best!) {
            best = nk;
            bestScore = score;
          }
        }
      }
      if (best == null) return false;
      cells.add(best);
    }
    return true;
  }

  static MagMap generate(int seed, {int? size, int version = 1}) => _generate(
    seed,
    size ?? (version >= 5 ? MagRules.bigMapSize : MagRules.mapSize),
    version,
  );

  static MagMap _generate(int seed, int size, int version) {
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
    // Generator 5: a big river always splits the map.
    if (version >= 5) _carveBigRiver(t, size, seed, rnd);
    // A river across the map, meandering (on the big map, west of the
    // start).
    var rx = version >= 5
        ? size * (.1 + rnd.nextDouble() * .2)
        : size * (.25 + rnd.nextDouble() * .5);
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
        // A settlement keeps a free ring so it can grow (new maps).
        final g = p.town != null && version >= 2
            ? math.max(gap, MagTowns.room)
            : gap;
        if (x < p.x + p.size + g &&
            p.x < x + s + g &&
            y < p.y + p.size + g &&
            p.y < y + s + g) {
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

    /// A settlement of [level] with its land grown to the level's size.
    void settle(int x, int y, String name, int level) {
      final p = put(MagIndustryKind.village, x, y, name);
      var forest = 0, hills = 0;
      for (var yy = y - 3; yy <= y + 3; yy++) {
        for (var xx = x - 3; xx <= x + 3; xx++) {
          if (xx < 0 || yy < 0 || xx >= size || yy >= size) continue;
          final k = t[yy * size + xx];
          if (k == MagTerrain.forest.index) forest++;
          if (k == MagTerrain.hill.index) hills++;
        }
      }
      final town = MagSettlement(
        level: level,
        population: MagTowns.of(level).population,
        specialization: hills > 4
            ? MagSpecialization.mining
            : forest > 6
            ? MagSpecialization.forestry
            : MagSpecialization.farming,
      )..cells.add(MagSettlement.key(x, y));
      p.town = town;
      MagMap.expandCells(town.cells, MagTowns.of(level).cells, (cx, cy) {
        if (cx < 1 || cy < 1 || cx >= size - 1 || cy >= size - 1) return false;
        final k = t[cy * size + cx];
        if (k == MagTerrain.lake.index || k == MagTerrain.river.index) {
          return false;
        }
        return !places.any((o) => o != p && o.covers(cx, cy));
      });
    }

    var vx = px + 5, vy = py + 5;
    if (version >= 2) {
      // New games: the first village by the plant, then hamlets and two
      // more villages spread wide, each with room to become a city.
      for (
        var tries = 0;
        !free(vx, vy, 1, gap: MagTowns.room) && tries < 60;
        tries++
      ) {
        vx = px - 5 + rnd.nextInt(12);
        vy = py + 4 + rnd.nextInt(7);
      }
      settle(vx, vy, _villages[0], 2);
      var named = 0, vn = 0, hn = 0;
      final levels = version >= 5
          ? [2, 2, 2, 2, 2, for (var k = 0; k < 13; k++) 1]
          : [2, 2, 1, 1, 1, 1, 1, 1];
      for (final level in levels) {
        for (var tries = 0; tries < 400; tries++) {
          final x = 4 + rnd.nextInt(size - 8), y = 4 + rnd.nextInt(size - 8);
          if (!free(x, y, 1, gap: MagTowns.room + 1)) continue;
          settle(
            x,
            y,
            version >= 5
                ? (level == 2
                      ? _villages[1 + vn++ % (_villages.length - 1)]
                      : _hamlets[hn++ % _hamlets.length])
                : level == 2
                ? _villages[1 + named % 5]
                : _hamlets[named % 10],
            level,
          );
          named++;
          break;
        }
      }
    } else {
      for (var tries = 0; !free(vx, vy, 2, gap: 1) && tries < 40; tries++) {
        vx = px - 4 + rnd.nextInt(10);
        vy = py + 4 + rnd.nextInt(6);
      }
      put(MagIndustryKind.village, vx, vy, _villages[0]);
    }

    // The rest spread over the map.
    final plan = [
      if (version < 2) (MagIndustryKind.city, 4),
      if (version < 2) (MagIndustryKind.village, 4),
      (MagIndustryKind.farm, 4),
      (MagIndustryKind.sawmill, 4),
      (MagIndustryKind.mine, 3),
      (MagIndustryKind.foodPlant, 2),
      (MagIndustryKind.factory, 3),
      // Generator 3 (1.74): the first production chains.
      if (version >= 3) (MagIndustryKind.quarry, 3),
      if (version >= 3) (MagIndustryKind.mill, 2),
      if (version >= 3) (MagIndustryKind.bakery, 2),
      if (version >= 3) (MagIndustryKind.lumbermill, 2),
      // Generator 4 (1.76): industry — coal, clay and bricks, steel, parts.
      if (version >= 4) (MagIndustryKind.coalMine, 2),
      if (version >= 4) (MagIndustryKind.clayPit, 2),
      if (version >= 4) (MagIndustryKind.brickworks, 2),
      if (version >= 4) (MagIndustryKind.steelMill, 1),
      if (version >= 4) (MagIndustryKind.partsFactory, 1),
    ];
    var cityName = 0, villageName = 1, n = 0;
    for (final (kind, count) in plan) {
      final s = MagRules.industries[kind]!.size;
      for (var i = 0; i < count * (version >= 5 ? 3 : 1); i++) {
        for (var tries = 0; tries < 300; tries++) {
          final x = 2 + rnd.nextInt(size - s - 4);
          final y = 2 + rnd.nextInt(size - s - 4);
          // Logging camps want forest, mines and quarries hills nearby.
          final near = MagRules.industries[kind]!.near;
          if (near != null && !_near(t, size, x, y, s, near) && tries < 200) {
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
            MagIndustryKind.sawmill => 'Лесозаготовка №$n',
            MagIndustryKind.mine => 'Рудник №$n',
            MagIndustryKind.foodPlant => 'Пищевой завод №$n',
            MagIndustryKind.factory => 'Завод №$n',
            MagIndustryKind.warehouse => 'Склад №$n',
            MagIndustryKind.quarry => 'Каменоломня №$n',
            MagIndustryKind.mill => 'Мельница №$n',
            MagIndustryKind.bakery => 'Пекарня №$n',
            MagIndustryKind.lumbermill => 'Лесопилка №$n',
            MagIndustryKind.coalMine => 'Угольная шахта №$n',
            MagIndustryKind.clayPit => 'Глиняный карьер №$n',
            MagIndustryKind.brickworks => 'Кирпичный завод №$n',
            MagIndustryKind.steelMill => 'Сталелитейный завод №$n',
            MagIndustryKind.partsFactory => 'Завод деталей №$n',
            MagIndustryKind.logisticsCenter => 'Логистический центр №$n',
            MagIndustryKind.megaproject => 'Мегапроект №$n',
          });
          break;
        }
      }
    }
    if (version < 2) {
      // Maps made before 1.72: their villages and cities become
      // settlements of a matching level on the land they already cover.
      for (final p in places) {
        final level = switch (p.kind) {
          MagIndustryKind.village => 3,
          MagIndustryKind.city => 6,
          _ => 0,
        };
        if (level == 0) continue;
        final town = MagSettlement(
          level: level,
          population: MagTowns.of(level).population,
          specialization: level >= 6
              ? MagSpecialization.industry
              : MagSpecialization.trade,
        );
        for (var yy = p.y; yy < p.y + p.size; yy++) {
          for (var xx = p.x; xx < p.x + p.size; xx++) {
            town.cells.add(MagSettlement.key(xx, yy));
          }
        }
        p.town = town;
      }
    }
    return MagMap._(seed, size, t, places, version);
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
}
