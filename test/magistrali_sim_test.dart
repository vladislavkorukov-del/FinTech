import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Магистрали» rules: map, road graph, A*, trucks on real roads, paid
/// deliveries, upgrades, saving, and cargo that never appears or vanishes.
void main() {
  /// Road from the start farm's right side to the plant's left side.
  MagRoadPlan startRoad(MagWorld w, [MagRoad type = MagRoad.dirt]) {
    final f = w.map.startFarm, p = w.map.startPlant;
    return w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, type);
  }

  void expectBalanced(MagWorld w) {
    final total = w.totalCargo();
    for (final c in MagCargo.values) {
      expect(
        total[c] ?? 0,
        (w.created[c] ?? 0) - (w.destroyed[c] ?? 0),
        reason: '$c at tick ${w.tick}',
      );
    }
  }

  /// A world with the start line built, routed and one truck on it.
  MagWorld running() {
    final w = MagWorld.start();
    expect(w.buildRoad(startRoad(w)), isNull);
    expect(w.createRoute([w.map.startFarm.id, w.map.startPlant.id]), isNull);
    final truck = w.vehicles.values.first;
    expect(w.assign(truck.id, w.routes.keys.first), isNull);
    return w;
  }

  int ticksToFirstDelivery(MagWorld w) {
    for (var t = 0; t < 4000; t++) {
      w.step();
      if (w.deliveries > 0) return t;
    }
    fail('no delivery');
  }

  test('the map is the same for a seed and the start line is possible', () {
    final a = MagMap.generate(7), b = MagMap.generate(7);
    expect(a.size, 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        expect(a.at(x, y), b.at(x, y));
      }
    }
    expect(a.industries.length, b.industries.length);
    final kinds = a.industries.map((i) => i.kind).toSet();
    expect(kinds, containsAll(MagIndustryKind.values));
    expect(a.startFarm.kind, MagIndustryKind.farm);
    expect(a.startPlant.kind, MagIndustryKind.foodPlant);
    final terrain = {
      for (var y = 0; y < 64; y++)
        for (var x = 0; x < 64; x++) a.at(x, y),
    };
    expect(terrain, containsAll(MagTerrain.values));
    // Places never overlap.
    for (final i in a.industries) {
      for (final o in a.industries) {
        if (i == o) continue;
        expect(
          i.x + i.size <= o.x ||
              o.x + o.size <= i.x ||
              i.y + i.size <= o.y ||
              o.y + o.size <= i.y,
          isTrue,
        );
      }
    }
    // Every seed allows the first line on dry land.
    for (final seed in [1, 2, 3, 99, 12345, MagRules.defaultSeed]) {
      final w = MagWorld.start(seed);
      final plan = startRoad(w);
      expect(plan.error, isNull, reason: 'seed $seed');
      expect(plan.cost, lessThan(MagRules.startMoney ~/ 3));
    }
  });

  test('A* finds the shortest way and goes round what is blocked', () {
    // A 10×10 grid with a wall at x = 5 except a gap at y = 9.
    double? step(int a, int b) => b % 10 == 5 && b ~/ 10 != 9 ? null : 1;
    final straight = magAStar(
      width: 10,
      height: 10,
      start: 0,
      isGoal: (c) => c == 4,
      step: step,
      heuristic: (c) => ((c % 10) - 4).abs() + (c ~/ 10).toDouble(),
    )!;
    expect(straight, [0, 1, 2, 3, 4]);
    final around = magAStar(
      width: 10,
      height: 10,
      start: 0,
      isGoal: (c) => c == 9,
      step: step,
      heuristic: (c) => ((c % 10) - 9).abs() + (c ~/ 10).toDouble(),
    )!;
    expect(around.first, 0);
    expect(around.last, 9);
    expect(around.length, 28); // down 9, across 9, up 9
    for (var i = 1; i < around.length; i++) {
      final d = (around[i] - around[i - 1]).abs();
      expect(d == 1 || d == 10, isTrue);
      expect(step(around[i - 1], around[i]), isNotNull);
    }
    expect(
      magAStar(
        width: 10,
        height: 10,
        start: 0,
        isGoal: (c) => c == 9,
        step: (a, b) => b % 10 == 5 ? null : 1,
        heuristic: (_) => 0,
      ),
      isNull,
    );
  });

  test('roads: plan, cost, money, terrain, joins and removal', () {
    final w = MagWorld.start();
    final plan = startRoad(w);
    expect(plan.cells, isNotEmpty);
    expect(plan.cost, greaterThan(0));
    final money = w.money;
    expect(w.buildRoad(plan), isNull);
    expect(w.money, money - plan.cost);
    expect(w.month.expense['roads'], plan.cost);
    expect(w.connected(w.map.startFarm, w.map.startPlant), isTrue);
    // The same road again costs nothing and is refused.
    expect(startRoad(w).cost, 0);
    expect(w.buildRoad(startRoad(w)), isNotNull);
    // A road cell joins its neighbours.
    final mid = plan.cells[plan.cells.length ~/ 2];
    final x = w.cx(mid), y = w.cy(mid);
    expect(w.connections(x, y), isNot(0));
    // Asphalt opens at level 2.
    expect(startRoad(w, MagRoad.asphalt).error, isNotNull);
    w.xp = MagWorldProgress.xpFor(2);
    final better = startRoad(w, MagRoad.asphalt);
    expect(better.error, isNull);
    expect(better.cost, greaterThan(0));
    expect(w.buildRoad(better), isNull);
    expect(w.roadAt(x, y), MagRoad.asphalt);
    // Not on a place, not on a lake, not without money.
    final f = w.map.startFarm;
    expect(w.planRoad(f.x, f.y, f.x + 5, f.y, MagRoad.dirt).error, isNotNull);
    w.money = 0;
    final far = w.planRoad(2, 2, 2, 12, MagRoad.dirt);
    if (far.error == null) expect(w.buildRoad(far), contains('кредит'));
    // Removal breaks the link.
    expect(w.removeRoad([mid]), isNull);
    expect(w.connected(w.map.startFarm, w.map.startPlant), isFalse);
  });

  test('a truck drives only on built roads and is paid on delivery', () {
    final w = running();
    final truck = w.vehicles.values.first;
    final farm = w.map.startFarm, plant = w.map.startPlant;
    var moneyBefore = w.money;
    var sawDriving = false;
    for (var t = 0; t < 3000 && w.deliveries == 0; t++) {
      w.step();
      expectBalanced(w);
      if (truck.onMap) expect(w.roads[truck.cell], isNot(0));
      if (truck.state == MagVehicleState.driving) {
        sawDriving = true;
        for (final c in truck.path) {
          expect(w.roads[c], isNot(0));
        }
        expect(truck.cargo, MagCargo.grain);
        expect(truck.loadFrom, farm.id);
        // No pay before arriving.
        expect(w.month.income['delivery'], isNull);
      }
      if (w.deliveries == 0) {
        expect(w.money, lessThanOrEqualTo(moneyBefore + 1));
        moneyBefore = w.money;
      }
    }
    expect(sawDriving, isTrue);
    expect(w.deliveries, 1);
    final pay = w.month.income['delivery']!;
    final units = w.delivered[MagCargo.grain]!;
    expect(units, w.capacityOf(truck));
    expect(
      pay,
      (units *
              MagRules.cargoRate[MagCargo.grain]! *
              farm.distanceTo(plant).clamp(MagRules.minPayDistance, 999))
          .round(),
    );
    expect(truck.income, pay);
    expect(plant.input[MagCargo.grain] ?? 0, greaterThan(0));
    expect(w.tasksDone, containsAll([1, 2, 3, 4]));
    // The plant turns grain into food over the next day.
    w.step(MagRules.ticksPerDay);
    expect(plant.stock[MagCargo.food] ?? 0, greaterThan(0));
    expectBalanced(w);
    expect(w.xp, greaterThan(0));
  });

  test('upgrades really change speed, capacity and costs', () {
    final slow = running(), fast = running();
    final t = fast.vehicles.values.first;
    fast.money = 100000;
    for (var i = 0; i < 2; i++) {
      expect(fast.upgrade(t.id, MagUpgrade.engine), isNull);
    }
    expect(fast.upgrade(t.id, MagUpgrade.body), isNull);
    expect(fast.upgrade(t.id, MagUpgrade.economy), isNull);
    expect(
      fast.speedOf(t),
      greaterThan(slow.speedOf(slow.vehicles.values.first)),
    );
    expect(fast.capacityOf(t), 11);
    expect(fast.runningCostOf(t), lessThan(t.spec.runningCost));
    // Capped by the company level.
    expect(fast.upgrade(t.id, MagUpgrade.engine), isNotNull);
    expect(fast.upgrade(t.id, MagUpgrade.engine), contains('компании'));
    final a = ticksToFirstDelivery(slow);
    final b = ticksToFirstDelivery(fast);
    expect(b, lessThan(a));
    expect(
      fast.delivered[MagCargo.grain],
      greaterThan(slow.delivered[MagCargo.grain]!),
    );
    expect(
      fast.upgradeCost(t, MagUpgrade.engine)!,
      greaterThan(fast.upgradeCost(t, MagUpgrade.reliability)!),
    );
  });

  test('a broken road stops the truck; a new road lets it go on', () {
    final w = running();
    final truck = w.vehicles.values.first;
    while (truck.state != MagVehicleState.driving) {
      w.step();
    }
    // Cut the road somewhere the truck is not.
    final busy = w.occupied;
    final cut = truck.path.reversed.firstWhere((c) => !busy.contains(c));
    expect(w.removeRoad(busy.take(1)), contains('грузовик'));
    expect(w.removeRoad([cut]), isNull);
    for (var t = 0; t < 400; t++) {
      w.step();
      if (truck.onMap) expect(w.roads[truck.cell], isNot(0));
    }
    expect(truck.state, isNot(MagVehicleState.driving));
    expect(w.deliveries, 0);
    // Mend it: the truck re-plans and delivers.
    final x = w.cx(cut), y = w.cy(cut);
    expect(w.buildRoad(w.planRoad(x, y, x, y, MagRoad.dirt)), isNull);
    for (var t = 0; t < 3000 && w.deliveries == 0; t++) {
      w.step();
    }
    expect(w.deliveries, 1);
    expectBalanced(w);
  });

  test('saving and loading continues exactly from the same place', () {
    final a = running();
    a.step(437);
    final saved = jsonEncode(a.toJson());
    final b = magWorldFromJson(jsonDecode(saved) as Map<String, dynamic>);
    expect(jsonEncode(b.toJson()), saved);
    a.step(2500);
    b.step(2500);
    expect(b.money, a.money);
    expect(b.deliveries, a.deliveries);
    expect(b.deliveries, greaterThan(0));
    expect(jsonEncode(b.toJson()), jsonEncode(a.toJson()));
    expectBalanced(b);
  });

  test('cargo never doubles: reassigning, selling, saving, broken files', () {
    final w = running();
    final truck = w.vehicles.values.first;
    while (truck.load == 0) {
      w.step();
    }
    final grainBefore = w.totalCargo()[MagCargo.grain];
    // Taking it off the route sends the load back where it came from.
    final farm = w.map.startFarm;
    final stock = farm.stock[MagCargo.grain] ?? 0;
    final load = truck.load;
    expect(w.assign(truck.id, null), isNull);
    expect(truck.load, 0);
    expect(farm.stock[MagCargo.grain], stock + load);
    expect(w.totalCargo()[MagCargo.grain], grainBefore);
    expectBalanced(w);
    // Back on the route, loaded again, saved and loaded twice.
    w.assign(truck.id, w.routes.keys.first);
    while (truck.load == 0) {
      w.step();
    }
    var copy = w;
    for (var i = 0; i < 2; i++) {
      copy = magWorldFromJson(
        jsonDecode(jsonEncode(copy.toJson())) as Map<String, dynamic>,
      );
    }
    expect(copy.totalCargo(), w.totalCargo());
    // Selling keeps the ledger too.
    final money = w.money;
    expect(w.sellTruck(truck.id), isNull);
    expect(w.money, greaterThan(money));
    expectBalanced(w);
    // An edited file with extra cargo is refused.
    final bad = w.toJson();
    (bad['industries'] as List).first['stock'] = {'grain': 9999};
    expect(() => magWorldFromJson(bad), throwsFormatException);
    // A road on a lake is refused.
    final lake = [
      for (var c = 0; c < 64 * 64; c++)
        if (w.map.at(c % 64, c ~/ 64) == MagTerrain.lake) c,
    ].first;
    final roads = base64Decode(w.toJson()['roads'] as String)..[lake] = 1;
    expect(
      () => magWorldFromJson(w.toJson()..['roads'] = base64Encode(roads)),
      throwsFormatException,
    );
  });

  test('economy: upkeep, stats, levels, contracts and unlocks', () {
    final w = MagWorld.start();
    final money = w.money;
    w.step(MagRules.ticksPerDay);
    expect(w.money, money - w.upkeepOf(w.vehicles.values.first));
    expect(w.month.expense['upkeep'], greaterThan(0));
    expect(w.month.profit, lessThan(0));
    // Levels go on past 100.
    expect(
      MagWorldProgress.xpFor(101),
      greaterThan(MagWorldProgress.xpFor(100)),
    );
    w.xp = MagWorldProgress.xpFor(100);
    expect(w.level, 100);
    w.xp = MagWorldProgress.xpFor(140);
    expect(w.level, 140);
    expect(w.maxUpgradeLevel, MagRules.maxUpgrade);
    // Trucks open with levels.
    final fresh = MagWorld.start()..money = 1000000;
    expect(fresh.buyTruck('lorry'), contains('уровне'));
    fresh.xp = MagWorldProgress.xpFor(3);
    expect(fresh.buyTruck('lorry'), isNull);
    expect(fresh.vehicles.length, 2);
    // A month rolls over with its own figures.
    fresh.step(MagRules.ticksPerDay * MagRules.daysPerMonth);
    expect(fresh.months.length, 2);
    expect(fresh.months.first.expense['vehicles'], 6800);
    // Contracts pay once when filled.
    final c = fresh.contracts.first;
    expect(fresh.contracts.length, fresh.contractSlots);
    expect(fresh.replaceContract(c.id), isNull);
    expect(fresh.contracts.any((o) => o.id == c.id), isFalse);
    // Finora world rewards: first delivery and every fifth level.
    final r = running();
    ticksToFirstDelivery(r);
    expect(r.earnedRewards, contains('magistrali:first_delivery:v1'));
    r.xp = MagWorldProgress.xpFor(12);
    expect(
      r.earnedRewards,
      containsAll(['magistrali:level:5:v1', 'magistrali:level:10:v1']),
    );
    expect(r.companyValue, greaterThan(0));
  });

  test('a two-line network: food goes on to the village', () {
    final w = running()..money = 50000;
    final plant = w.map.startPlant;
    final village = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.village,
    );
    final plan = w.planRoad(
      plant.x + 1,
      plant.y + plant.size,
      village.x,
      village.y - 1,
      MagRoad.dirt,
    );
    expect(plan.error, isNull);
    expect(w.buildRoad(plan), isNull);
    expect(w.connected(plant, village), isTrue);
    expect(w.createRoute([plant.id, village.id]), isNull);
    expect(w.buyTruck('pickup'), isNull);
    final second = w.vehicles.values.last;
    expect(w.assign(second.id, w.routes.keys.last), isNull);
    for (var t = 0; t < 8000 && (w.delivered[MagCargo.food] ?? 0) == 0; t++) {
      w.step();
    }
    expect(w.delivered[MagCargo.food], greaterThan(0));
    expect(w.routes.values.last.income, greaterThan(0));
    expect(w.tasksDone, containsAll([6, 7]));
    expectBalanced(w);
  });
}
