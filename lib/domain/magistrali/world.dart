import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'config.dart';
import 'dispatcher.dart';
import 'entities.dart';
import 'map.dart';
import 'orders.dart';
import 'pathfinding.dart';
import 'settlements.dart';
import 'tech.dart';

part 'world_dispatch.dart';
part 'world_fleet.dart';
part 'world_orders.dart';
part 'world_progress.dart';
part 'world_save.dart';
part 'world_settlements.dart';
part 'world_sim.dart';
part 'world_storage.dart';
part 'world_tech.dart';

/// A road to build: its cells in order and what it costs.
class MagRoadPlan {
  const MagRoadPlan(this.cells, this.cost, this.type, [this.error]);
  final List<int> cells;
  final int cost;
  final MagRoad type;

  /// Why it cannot be built (null: it can, money permitting).
  final String? error;
}

/// The whole company: map, roads, vehicles, routes, money and progress.
/// Everything changes through its methods, on a fixed 100 ms step, so the
/// same actions always give the same result.
class MagWorld {
  MagWorld({required this.map}) : roads = Uint8List(map.size * map.size);

  factory MagWorld.start([int seed = MagRules.defaultSeed]) {
    // New games: generator 2 — hamlets and villages with room to grow.
    final w = MagWorld(map: MagMap.generate(seed, version: 2));
    for (final s in w.settlements) {
      s.town!.remember(0, 'Основано: ${s.town!.spec.name}');
    }
    w.money = MagRules.startMoney;
    final v = w._newVehicle(MagRules.trucks.first);
    v.name = 'Пикап №1';
    for (final i in w.map.industries) {
      for (final c in i.supplies) {
        if (i.spec.produces.containsKey(c)) {
          // Raw producers start with a day of goods ready.
          final n = i.spec.produces[c]!;
          i.stock[c] = n;
          w.created[c] = (w.created[c] ?? 0) + n;
        }
      }
    }
    w._refillContracts();
    final f = w.map.startFarm;
    w.cameraX = (f.centerX + w.map.startPlant.centerX) / 2;
    w.cameraY = (f.centerY + w.map.startPlant.centerY) / 2;
    return w;
  }

  final MagMap map;
  int get seed => map.seed;
  int get size => map.size;

  /// Road surface per cell (MagRoad index).
  final Uint8List roads;

  int tick = 0;
  int money = 0;
  int xp = 0;
  int nextId = 1;

  /// Simulation speed: 0 (pause), 1, 2 or 4.
  int speed = 1;

  final vehicles = <int, MagVehicle>{};
  final routes = <int, MagRoute>{};
  final contracts = <MagContract>[];

  /// How the dispatcher weighs trucks, and its latest choices.
  MagDispatchMode dispatchMode = MagDispatchMode.balanced;
  final dispatchLog = <MagDispatchNote>[];

  /// Technologies learned (ids of MagTechTree).
  final techs = <String>{};

  /// Logistics orders (stage 1 of automation).
  final orders = MagOrderBook();
  final tasksDone = <int>{};

  /// Cargo ledger: made (production, processing) and used up (processing,
  /// towns). Everything that exists equals created − destroyed.
  final created = <MagCargo, int>{}, destroyed = <MagCargo, int>{};

  /// Delivered units per cargo, all time.
  final delivered = <MagCargo, int>{};
  int deliveries = 0;
  int earnedTotal = 0;

  /// Months of statistics, the current one last (at most 12 kept).
  final months = <MagMonth>[MagMonth(0)];
  MagMonth get month => months.last;

  /// State of the contract generator.
  int rng = 1;

  /// Bumped whenever roads change; drivers re-plan when it moves.
  int roadVersion = 0;

  double cameraX = 32, cameraY = 32, zoom = 1;
  bool autoService = true;
  bool sound = true;

  /// Messages for the screen, taken by [takeEvents].
  final _events = <String>[];

  List<String> takeEvents() {
    final e = List<String>.of(_events);
    _events.clear();
    return e;
  }

  void _say(String s) {
    _events.add(s);
    if (_events.length > 20) _events.removeAt(0);
  }

  // ---- Cells and roads ----

  int cellOf(int x, int y) => y * size + x;
  int cx(int cell) => cell % size;
  int cy(int cell) => cell ~/ size;

  MagRoad roadAt(int x, int y) =>
      map.inside(x, y) ? MagRoad.values[roads[cellOf(x, y)]] : MagRoad.none;
  bool hasRoad(int x, int y) => roadAt(x, y) != MagRoad.none;

  /// Directions (bit per MagDir) in which a road cell joins neighbours,
  /// including the places it serves.
  int connections(int x, int y) {
    var mask = 0;
    for (var d = 0; d < 4; d++) {
      final nx = x + MagDir.dx[d], ny = y + MagDir.dy[d];
      if (hasRoad(nx, ny) ||
          map.inside(nx, ny) && map.industryAt(nx, ny) != null) {
        mask |= 1 << d;
      }
    }
    return mask;
  }

  /// Road cells next to a place, in a stable order: where trucks stop.
  List<int> accessCells(MagIndustry i) {
    if (i.town != null) {
      // A settlement: road cells next to any cell of its land.
      final out = <int>[];
      for (var y = i.top - 1; y <= i.bottom + 1; y++) {
        for (var x = i.left - 1; x <= i.right + 1; x++) {
          if (!map.inside(x, y) || i.covers(x, y) || !hasRoad(x, y)) continue;
          if (_touches(cellOf(x, y), i)) out.add(cellOf(x, y));
        }
      }
      return out;
    }
    final out = <int>[];
    for (var y = i.y - 1; y <= i.y + i.size; y++) {
      for (var x = i.x - 1; x <= i.x + i.size; x++) {
        final edge =
            (x == i.x - 1 || x == i.x + i.size) !=
            (y == i.y - 1 || y == i.y + i.size);
        if (edge && hasRoad(x, y)) out.add(cellOf(x, y));
      }
    }
    return out;
  }

  bool _touches(int cell, MagIndustry i) {
    final x = cx(cell), y = cy(cell);
    if (i.town != null) {
      if (i.covers(x, y)) return false;
      for (var d = 0; d < 4; d++) {
        if (i.covers(x + MagDir.dx[d], y + MagDir.dy[d])) return true;
      }
      return false;
    }
    final dx = x < i.x
        ? i.x - x
        : (x >= i.x + i.size ? x - i.x - i.size + 1 : 0);
    final dy = y < i.y
        ? i.y - y
        : (y >= i.y + i.size ? y - i.y - i.size + 1 : 0);
    return dx + dy == 1;
  }

  double _roadSpeed(int cell) {
    final r = MagRoad.values[roads[cell]];
    return r == MagRoad.none
        ? 0
        : MagRules.roads[r]!.speed * factor(MagBonus.roadSpeed);
  }

  /// The quickest way by road from any of [from] to any stop of [to]. A
  /// place joins all roads that reach it, so a truck leaving a stop may
  /// start from any of its stop cells.
  List<int>? roadPath(List<int> from, MagIndustry to) {
    from = [
      for (final c in from)
        if (roads[c] != 0) c,
    ];
    if (from.isEmpty) return null;
    final l = to.left, r = to.right, t = to.top, b = to.bottom;
    return magAStar(
      width: size,
      height: size,
      starts: from,
      isGoal: (c) => _touches(c, to),
      step: (a, b) => roads[b] == 0 ? null : 1 / _roadSpeed(b),
      heuristic: (c) {
        final x = cx(c), y = cy(c);
        final dx = math.max(0, math.max(l - x, x - r));
        final dy = math.max(0, math.max(t - y, y - b));
        return math.max(0, dx + dy - 1) / (1.6 * factor(MagBonus.roadSpeed));
      },
    );
  }

  /// Are two places joined by road?
  bool connected(MagIndustry a, MagIndustry b) {
    return roadPath(accessCells(a), b) != null;
  }

  bool roadUnlocked(MagRoad r) =>
      r != MagRoad.none && level >= MagRules.roads[r]!.level;

  /// Cost of one cell of [type] where the road is now [old].
  int cellCost(int cell, MagRoad type) {
    final old = MagRoad.values[roads[cell]];
    if (old.index >= type.index) return 0;
    final k = MagRules.terrainCost(map.at(cx(cell), cy(cell)))!;
    final before = old == MagRoad.none ? 0 : MagRules.roads[old]!.cost;
    final t = map.at(cx(cell), cy(cell));
    final tech =
        factor(MagBonus.roadCost) *
        (t == MagTerrain.river ? factor(MagBonus.bridge) : 1);
    return ((MagRules.roads[type]!.cost - before) * k * tech).round();
  }

  /// Plans a road between two cells along the cheapest buildable way,
  /// reusing roads already there.
  MagRoadPlan planRoad(int sx, int sy, int ex, int ey, MagRoad type) {
    if (!roadUnlocked(type)) {
      return MagRoadPlan(const [], 0, type, 'Покрытие откроется позже');
    }
    if (!map.roadable(sx, sy) || !map.roadable(ex, ey)) {
      return MagRoadPlan(const [], 0, type, 'Здесь нельзя строить');
    }
    final goal = cellOf(ex, ey);
    final path = magAStar(
      width: size,
      height: size,
      start: cellOf(sx, sy),
      isGoal: (c) => c == goal,
      step: (a, b) {
        final x = cx(b), y = cy(b);
        if (!map.roadable(x, y)) return null;
        final c = cellCost(b, type);
        // Existing road is almost free, so plans follow it.
        return c == 0 ? .2 : c / MagRules.roads[type]!.cost;
      },
      heuristic: (c) => ((cx(c) - ex).abs() + (cy(c) - ey).abs()) * .2,
      maxNodes: 20000,
    );
    if (path == null) {
      return MagRoadPlan(const [], 0, type, 'Сюда не проложить дорогу');
    }
    final cost = path.fold(0, (s, c) => s + cellCost(c, type));
    return MagRoadPlan(path, cost, type);
  }

  /// Builds a planned road (or improves the surface along it).
  String? buildRoad(MagRoadPlan plan) {
    if (plan.error != null) return plan.error;
    if (plan.cells.isEmpty) return 'Нечего строить';
    final cost = plan.cells.fold(0, (s, c) => s + cellCost(c, plan.type));
    if (cost == 0) return 'Здесь уже есть такая дорога';
    if (cost > money) return 'Не хватает кредитов: нужно $cost';
    for (final c in plan.cells) {
      if (!map.roadable(cx(c), cy(c))) return 'Здесь нельзя строить';
    }
    for (final c in plan.cells) {
      if (roads[c] < plan.type.index) roads[c] = plan.type.index;
    }
    _spend(cost, 'roads');
    roadVersion++;
    return null;
  }

  /// Cells a truck stands on or is about to enter.
  Set<int> get occupied => {
    for (final v in vehicles.values)
      if (v.onMap) ...{
        v.cell,
        if (v.state == MagVehicleState.driving &&
            v.pathIndex + 1 < v.path.length)
          v.path[v.pathIndex + 1],
      },
  };

  /// Removes road cells (free; nothing is refunded).
  String? removeRoad(Iterable<int> cells) {
    final busy = occupied;
    final list = cells.where((c) => roads[c] != 0).toList();
    if (list.isEmpty) return 'Здесь нет дороги';
    if (list.any(busy.contains)) return 'Здесь сейчас едет грузовик';
    for (final c in list) {
      roads[c] = 0;
    }
    roadVersion++;
    return null;
  }

  // ---- Money ----

  void _spend(int amount, String category) {
    money -= amount;
    month.expense[category] = (month.expense[category] ?? 0) + amount;
  }

  void _earn(int amount, String category) {
    money += amount;
    earnedTotal += amount;
    month.income[category] = (month.income[category] ?? 0) + amount;
  }

  // ---- Routes ----

  String? createRoute(List<int> stops, {String? name}) {
    if (stops.length < 2) return 'Нужно хотя бы две остановки';
    for (var i = 0; i < stops.length; i++) {
      if (map.industry(stops[i]) == null) return 'Нет такого предприятия';
      if (stops[i] == stops[(i + 1) % stops.length]) {
        return 'Две одинаковые остановки подряд';
      }
    }
    final r = MagRoute(
      id: nextId++,
      name:
          name ??
          stops.map((s) => map.industry(s)!.name.split(' «').first).join(' → '),
      stops: List.of(stops),
    );
    routes[r.id] = r;
    return null;
  }

  void deleteRoute(int id) {
    for (final v in vehicles.values) {
      if (v.routeId == id) _park(v);
    }
    routes.remove(id);
  }

  /// All cargo that exists now (stocks, inputs and loads).
  Map<MagCargo, int> totalCargo() {
    final out = <MagCargo, int>{};
    void add(MagCargo c, int n) => out[c] = (out[c] ?? 0) + n;
    for (final i in map.industries) {
      i.stock.forEach(add);
      i.input.forEach(add);
      i.town?.devStock.forEach(add);
      i.town?.pantry.forEach(add);
    }
    for (final v in vehicles.values) {
      if (v.load > 0) add(v.cargo!, v.load);
    }
    return out;
  }

  /// Value of the company: money, trucks and roads.
  int get companyValue {
    var roadsValue = 0;
    for (var c = 0; c < roads.length; c++) {
      if (roads[c] != 0) {
        roadsValue += MagRules.roads[MagRoad.values[roads[c]]]!.cost ~/ 2;
      }
    }
    return money +
        roadsValue +
        vehicles.values.fold(0, (s, v) => s + valueOf(v));
  }
}
