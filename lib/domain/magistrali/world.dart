import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'config.dart';
import 'entities.dart';
import 'map.dart';
import 'orders.dart';
import 'pathfinding.dart';

part 'world_orders.dart';
part 'world_progress.dart';
part 'world_save.dart';
part 'world_sim.dart';

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
    final w = MagWorld(map: MagMap.generate(seed));
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
    return r == MagRoad.none ? 0 : MagRules.roads[r]!.speed;
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
    return magAStar(
      width: size,
      height: size,
      starts: from,
      isGoal: (c) => _touches(c, to),
      step: (a, b) => roads[b] == 0 ? null : 1 / _roadSpeed(b),
      heuristic: (c) {
        final x = cx(c), y = cy(c);
        final dx = math.max(0, math.max(to.x - x, x - (to.x + to.size - 1)));
        final dy = math.max(0, math.max(to.y - y, y - (to.y + to.size - 1)));
        return math.max(0, dx + dy - 1) / 1.6;
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
    return ((MagRules.roads[type]!.cost - before) * k).round();
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

  // ---- Vehicles ----

  MagVehicle _newVehicle(MagTruckModel m) {
    final v = MagVehicle(id: nextId++, model: m.id, name: m.name);
    vehicles[v.id] = v;
    return v;
  }

  double speedOf(MagVehicle v) =>
      v.spec.speed * (1 + .08 * v.level(MagUpgrade.engine));

  int capacityOf(MagVehicle v) =>
      (v.spec.capacity * (1 + .1 * v.level(MagUpgrade.body))).round();

  double runningCostOf(MagVehicle v) =>
      v.spec.runningCost * (1 - .06 * v.level(MagUpgrade.economy));

  int upkeepOf(MagVehicle v) =>
      (v.spec.upkeep * (1 - .05 * v.level(MagUpgrade.economy))).round();

  /// Wear in percent per cell driven.
  double wearRateOf(MagVehicle v) =>
      .05 * (1 - .07 * v.level(MagUpgrade.reliability));

  /// Speed lost to wear (worn out: 35 % slower).
  double wearFactor(MagVehicle v) => 1 - .35 * v.wear / 100;

  /// Price of the next level of an upgrade line (null at the top).
  int? upgradeCost(MagVehicle v, MagUpgrade u) {
    final l = v.level(u);
    if (l >= MagRules.maxUpgrade) return null;
    return (v.spec.price * .22 * math.pow(1.34, l)).round();
  }

  int serviceCost(MagVehicle v) => (v.spec.price * .0016 * v.wear).round();

  int valueOf(MagVehicle v) =>
      (v.spec.price * .55 * (1 - v.wear / 200) + v.upgradeSpent * .3).round();

  String? buyTruck(String modelId) {
    final m = MagRules.truck(modelId);
    if (m == null) return 'Нет такой модели';
    if (level < m.level) return 'Откроется на ${m.level} уровне';
    if (money < m.price) return 'Не хватает кредитов';
    _spend(m.price, 'vehicles');
    final v = _newVehicle(m);
    final same = vehicles.values.where((o) => o.model == m.id).length;
    v.name = '${m.name.split(' ').first} №$same';
    _say('Куплен ${m.name}');
    return null;
  }

  String? upgrade(int id, MagUpgrade u) {
    final v = vehicles[id];
    if (v == null) return 'Нет такой машины';
    final cost = upgradeCost(v, u);
    if (cost == null) return 'Максимальный уровень';
    if (v.level(u) >= maxUpgradeLevel) {
      return 'Следующий уровень — с ростом компании';
    }
    if (money < cost) return 'Не хватает кредитов';
    _spend(cost, 'upgrades');
    v.upgrades[u.index]++;
    v.upgradeSpent += cost;
    return null;
  }

  String? service(int id) {
    final v = vehicles[id];
    if (v == null) return 'Нет такой машины';
    final cost = serviceCost(v);
    if (cost == 0) return 'Машина в порядке';
    if (money < cost) return 'Не хватает кредитов';
    _spend(cost, 'service');
    v.wear = 0;
    return null;
  }

  /// Takes a truck off the map; cargo on board goes back where it was
  /// loaded, so nothing appears or vanishes.
  void _park(MagVehicle v) {
    // An order it carries is cancelled first (its cargo goes back).
    final o = v.orderId == null ? null : orders.byId(v.orderId!);
    if (o != null && o.status.active) {
      _closeOrder(
        o,
        o.status == MagOrderStatus.unloading
            ? MagOrderStatus.done
            : MagOrderStatus.cancelled,
      );
    }
    v.orderId = null;
    if (v.load > 0) {
      final from = map.industry(v.loadFrom ?? -1);
      if (from != null) {
        from.stock[v.cargo!] = (from.stock[v.cargo!] ?? 0) + v.load;
      } else {
        destroyed[v.cargo!] = (destroyed[v.cargo!] ?? 0) + v.load;
      }
    }
    v
      ..load = 0
      ..cargo = null
      ..loadFrom = null
      ..routeId = null
      ..state = MagVehicleState.garage
      ..cell = -1
      ..path = const []
      ..pathIndex = 0
      ..progress = 0
      ..wait = 0;
  }

  String? sellTruck(int id) {
    final v = vehicles[id];
    if (v == null) return 'Нет такой машины';
    final value = valueOf(v);
    _park(v);
    vehicles.remove(id);
    money += value;
    month.income['sales'] = (month.income['sales'] ?? 0) + value;
    return null;
  }

  /// Puts a truck on a route (null: back to the garage).
  String? assign(int vehicleId, int? routeId) {
    final v = vehicles[vehicleId];
    if (v == null) return 'Нет такой машины';
    if (routeId != null && !routes.containsKey(routeId)) return 'Нет маршрута';
    _park(v);
    if (routeId == null) return null;
    v
      ..routeId = routeId
      ..stop = 0
      ..state = MagVehicleState.noRoad
      ..wait = 0;
    _tryStart(v);
    return null;
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
