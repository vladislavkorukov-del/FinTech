import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Master plan stage 5: industry and the finance centre, plus the road and
/// warehouse work asked for with it. Chains with two inputs (steel from
/// ore and coal, parts from steel and planks), build levels, new cargo
/// asked for only when it can be made; road stretches and better
/// surfaces; warehouse levels; the finance centre's figures and saves.
void main() {
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

  MagIndustry first(MagWorld w, MagIndustryKind k) =>
      w.map.industries.firstWhere((i) => i.kind == k);

  void give(MagWorld w, Map<MagCargo, int> into, MagCargo c, int n) {
    into[c] = (into[c] ?? 0) + n;
    w.created[c] = (w.created[c] ?? 0) + n;
  }

  MagWorld rich() => MagWorld.start()
    ..money = 1000000
    ..xp = MagWorldProgress.xpFor(10)
    ..techs.add('combustion');

  /// A free square of [s] cells near [x], [y] for building [k].
  (int, int) spot(MagWorld w, MagIndustryKind k, int x, int y) {
    for (var r = 2; r < 30; r++) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (w.buildBlocker(k, x + dx, y + dy) == null) {
            return (x + dx, y + dy);
          }
        }
      }
    }
    fail('no place for $k');
  }

  test('new maps have the industry; older generators are unchanged', () {
    final w = MagWorld.start();
    expect(w.map.version, 4);
    for (final (k, n) in [
      (MagIndustryKind.coalMine, 2),
      (MagIndustryKind.clayPit, 2),
      (MagIndustryKind.brickworks, 2),
      (MagIndustryKind.steelMill, 1),
      (MagIndustryKind.partsFactory, 1),
    ]) {
      expect(
        w.map.industries.where((i) => i.kind == k).length,
        n,
        reason: '$k',
      );
    }
    // Generator 3 is generator 4 without the new places: same land, same
    // places in the same spots.
    for (final seed in [MagRules.defaultSeed, 3, 77]) {
      final g3 = MagMap.generate(seed, version: 3);
      final g4 = MagMap.generate(seed, version: 4);
      expect(g4.industries.length, g3.industries.length + 8);
      for (var k = 0; k < g3.industries.length; k++) {
        final a = g3.industries[k], b = g4.industries[k];
        expect(
          (b.id, b.kind, b.x, b.y, b.name),
          (a.id, a.kind, a.x, a.y, a.name),
        );
      }
      // The new places level the ground under them; the rest is the same.
      final added = g4.industries.skip(g3.industries.length).toList();
      for (var y = 0; y < g3.size; y++) {
        for (var x = 0; x < g3.size; x++) {
          // (with a ring of one cell round each).
          if (added.any(
            (i) =>
                x >= i.x - 1 &&
                x <= i.x + i.size &&
                y >= i.y - 1 &&
                y <= i.y + i.size,
          )) {
            continue;
          }
          expect(g4.at(x, y), g3.at(x, y), reason: '($x, $y)');
        }
      }
    }
  });

  test('steel needs ore and coal; parts need steel and planks', () {
    final w = MagWorld.start();
    final mill = first(w, MagIndustryKind.steelMill);
    // Ore alone: the furnaces stay cold.
    give(w, mill.input, MagCargo.ore, 20);
    w.step(MagRules.ticksPerDay);
    expect(mill.stock[MagCargo.steel], isNull);
    // Coal arrives: 2 ore + 1 coal → 1 steel, as far as coal allows.
    give(w, mill.input, MagCargo.coal, 4);
    w.step(MagRules.ticksPerDay);
    expect(mill.stock[MagCargo.steel], 4);
    expect(mill.input[MagCargo.ore], 12);
    expect(mill.input[MagCargo.coal], isNull);
    final parts = first(w, MagIndustryKind.partsFactory);
    give(w, parts.input, MagCargo.steel, 6);
    give(w, parts.input, MagCargo.planks, 3);
    w.step(MagRules.ticksPerDay);
    expect(parts.stock[MagCargo.parts], 3);
    expect(parts.input[MagCargo.steel], 3);
    final bricks = first(w, MagIndustryKind.brickworks);
    give(w, bricks.input, MagCargo.clay, 9);
    w.step(MagRules.ticksPerDay);
    expect(bricks.stock[MagCargo.bricks], 4); // 2 clay per brick
    expectBalanced(w);
    // A mill takes coal into its store (it does not vanish on delivery).
    expect(w.roomOf(mill, MagCargo.coal), lessThan(1 << 20));
    expect(mill.accepts, containsAll([MagCargo.ore, MagCargo.coal]));
  });

  test('build levels and places; new cargo only where it can be made', () {
    final w = MagWorld.start()..money = 1000000;
    final c = w.map.startPlant;
    w.xp = MagWorldProgress.xpFor(3);
    expect(
      w.buildBlocker(MagIndustryKind.steelMill, c.x + 4, c.y + 4),
      contains('4 уровня'),
    );
    w.xp = MagWorldProgress.xpFor(5);
    final (sx, sy) = spot(w, MagIndustryKind.partsFactory, c.x, c.y);
    expect(w.buildIndustry(MagIndustryKind.partsFactory, sx, sy), isNull);
    expect(w.map.industries.last.since, w.tick);
    // A clay pit wants a river near.
    var dry = false;
    for (var y = 2; y < w.size - 4 && !dry; y++) {
      for (var x = 2; x < w.size - 4 && !dry; x++) {
        final why = w.buildBlocker(MagIndustryKind.clayPit, x, y);
        if (why != null && why.contains('река')) dry = true;
      }
    }
    expect(dry, isTrue);
    // An old map (generator 3) has ore but no coal: nobody asks for steel
    // or parts until a coal mine stands.
    final old = MagWorld(map: MagMap.generate(MagRules.defaultSeed, version: 3))
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(6);
    expect(old.cargoAvailable(MagCargo.steel), isFalse);
    expect(old.cargoAvailable(MagCargo.parts), isFalse);
    final town = old.settlements.firstWhere((t) => t.town!.level == 2);
    town.town!.level = 5;
    expect(old.developmentAsks(town).keys, isNot(contains(MagCargo.steel)));
    // It builds a coal mine and a steel mill: steel can now be made.
    final p = old.map.startPlant;
    final (mx, my) = spot(old, MagIndustryKind.coalMine, p.x, p.y);
    expect(old.buildIndustry(MagIndustryKind.coalMine, mx, my), isNull);
    expect(old.cargoAvailable(MagCargo.steel), isFalse); // no mill yet
    final (fx, fy) = spot(old, MagIndustryKind.steelMill, p.x, p.y);
    expect(old.buildIndustry(MagIndustryKind.steelMill, fx, fy), isNull);
    expect(old.cargoAvailable(MagCargo.steel), isTrue);
    expect(old.developmentAsks(town).keys, contains(MagCargo.steel));
    // Settlements' markets take bricks from level 3, steel from 5.
    expect(MagTowns.marketGoods(3), contains(MagCargo.bricks));
    expect(MagTowns.marketGoods(4), isNot(contains(MagCargo.steel)));
    expect(MagTowns.marketGoods(5), contains(MagCargo.steel));
  });

  test('a road stretch, a better surface, a road carried on', () {
    final w = MagWorld.start()..money = 100000;
    final p = w.map.startPlant;
    // A straight dirt road with a branch in the middle.
    final y = p.y + 6;
    var x0 = p.x - 6;
    while (!List.generate(
      9,
      (k) =>
          w.map.roadable(x0 + k, y) && w.map.roadable(x0 + 4, y + 1 + (k % 3)),
    ).every((e) => e)) {
      x0++;
    }
    final main = w.planRoad(x0, y, x0 + 8, y, MagRoad.dirt);
    expect(w.buildRoad(main), isNull);
    final branch = w.planRoad(x0 + 4, y + 1, x0 + 4, y + 3, MagRoad.dirt);
    expect(w.buildRoad(branch), isNull);
    final left = w.roadSegment(w.cellOf(x0 + 1, y));
    // From the start to the crossroads (5 cells), not past it.
    expect(left.length, 5);
    expect(left, contains(w.cellOf(x0 + 4, y)));
    expect(left, isNot(contains(w.cellOf(x0 + 5, y))));
    expect(w.roadSegment(w.cellOf(x0 + 4, y)), [w.cellOf(x0 + 4, y)]);
    // Asphalt opens at level 2.
    expect(w.upgradePlan(left).error, contains('2 уровне'));
    w.xp = MagWorldProgress.xpFor(2);
    final plan = w.upgradePlan(left);
    expect(plan.type, MagRoad.asphalt);
    expect(
      plan.cost,
      left.fold(0, (s, c) => s + w.cellCost(c, MagRoad.asphalt)),
    );
    final money = w.money;
    expect(w.buildRoad(plan), isNull);
    expect(w.money, money - plan.cost);
    for (final c in left) {
      expect(w.roads[c], MagRoad.asphalt.index);
    }
    expect(w.roads[w.cellOf(x0 + 5, y)], MagRoad.dirt.index);
    // The asphalt stretch now ends where the dirt begins.
    expect(w.roadSegment(w.cellOf(x0 + 1, y)).length, 5);
    // A drawn road carried on: no cell twice, priced again.
    final a = w.planRoad(x0, y + 8, x0 + 3, y + 8, MagRoad.dirt);
    final b = w.planRoad(x0 + 3, y + 8, x0 + 6, y + 8, MagRoad.dirt);
    final j = w.joinPlans(a, b);
    expect(j.cells.length, a.cells.length + b.cells.length - 1);
    expect(j.cells.toSet().length, j.cells.length);
    expect(j.cost, a.cost + b.cost - w.cellCost(b.cells.first, MagRoad.dirt));
  });

  test('warehouse levels: more room, priced, journaled, saved', () {
    final w = rich()..techs.add('storage');
    final p = w.map.startPlant;
    late int wx, wy;
    search:
    for (var r = 3; r < 20; r++) {
      for (var d = -r; d <= r; d++) {
        if (w.warehouseBlocker(p.x + d, p.y + r) == null) {
          wx = p.x + d;
          wy = p.y + r;
          break search;
        }
      }
    }
    if (w.warehouseSlots == 0) {
      for (final t in MagTechTree.all) {
        if (t.effects.containsKey(MagBonus.warehouses)) w.techs.add(t.id);
      }
    }
    expect(w.buildWarehouse(wx, wy), isNull);
    final wh = w.warehouses.single;
    final base = w.warehouseCapacityOf(wh);
    expect(base, w.warehouseCapacity);
    final price = w.warehouseUpgradePrice(wh)!;
    expect(w.upgradeWarehouse(wh.id), isNull);
    expect(wh.level, 2);
    expect(w.warehouseCapacityOf(wh), (base * 1.5).round());
    final e = w.journal.entries.last;
    expect(
      (e.category, e.kind, e.amount),
      ('warehouse_upgrade', MagEntryKind.capex, -price),
    );
    while (w.warehouseUpgradePrice(wh) != null) {
      expect(w.upgradeWarehouse(wh.id), isNull);
    }
    expect(wh.level, MagRules.maxIndustryLevel);
    expect(w.upgradeWarehouse(wh.id), 'Максимальный уровень');
    final b = magWorldFromJson(
      jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
    );
    final wb = b.warehouses.single;
    expect(wb.level, MagRules.maxIndustryLevel);
    expect(b.warehouseCapacityOf(wb), w.warehouseCapacityOf(wh));
    // Taking it down gives back half of the build price and upgrades.
    final before = b.money;
    expect(b.removeWarehouse(wb.id), isNull);
    expect(
      b.money - before,
      ((MagRules.warehousePrice + wh.invested) * .5).round(),
    );
  });

  test('finance centre: periods, vehicles, settlements, assets, saves', () {
    final w = rich();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    final village = w.settlements.firstWhere((i) => i.name == 'Луговое');
    w.buyIndustry(farm.id);
    // A cart and a pickup: a route farm → plant → village.
    for (final (a, b) in [(farm, plant), (plant, village)]) {
      var done = false;
      for (var y = a.top - 1; y <= a.bottom + 1 && !done; y++) {
        for (var x = a.left - 1; x <= a.right + 1 && !done; x++) {
          for (var yy = b.top - 1; yy <= b.bottom + 1 && !done; yy++) {
            for (var xx = b.left - 1; xx <= b.right + 1 && !done; xx++) {
              final plan = w.planRoad(x, y, xx, yy, MagRoad.dirt);
              if (plan.error == null && w.buildRoad(plan) == null) {
                done = w.connected(a, b);
              }
            }
          }
        }
      }
      expect(done, isTrue);
    }
    w.createRoute([farm.id, plant.id]);
    w.assign(w.vehicles.values.single.id, w.routes.keys.last);
    w.createRoute([plant.id, village.id]);
    w.buyTruck('pickup');
    w.assign(w.vehicles.values.last.id, w.routes.keys.last);
    w.step(MagRules.ticksPerDay * 40);
    final this0 = w.periods.first;
    final all = w.periods.last;
    // Investments are kept apart from costs; the sum matches the months.
    var revenue = 0, expense = 0;
    for (final m in w.months) {
      revenue += m.totalIncome;
      expense += m.totalExpense;
    }
    expect(all.revenue + all.assetSales, revenue);
    expect(all.opex + all.capex, expense);
    expect(all.capex, greaterThanOrEqualTo(w.buyPrice(farm) ~/ 2));
    expect(this0.operating, this0.revenue - this0.opex);
    // Vehicles carry their costs; the pickup drove part of the way empty.
    for (final f in w.vehicleFigures) {
      expect(f.vehicle.costs, greaterThan(0));
      expect(f.profit, f.vehicle.income - f.vehicle.costs);
      expect(f.loaded, isNotNull);
      expect(f.loaded!, inInclusiveRange(0, 1));
    }
    // The village shows what the company earned there.
    expect(w.servedTowns, contains(village));
    expect(village.town!.revenue, greaterThan(0));
    expect(village.town!.delivered, greaterThan(0));
    // The farm: owned since it was bought, with its figures.
    final ff = w.industryFigures.single;
    expect(ff.industry, farm);
    expect(farm.since, 0);
    expect(w.fleetValue, greaterThan(0));
    expect(w.roadsValue, greaterThan(0));
    // Everything survives a save.
    final b = magWorldFromJson(
      jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
    );
    final vb = b.vehicles.values.last, va = w.vehicles.values.last;
    expect((vb.costs, vb.emptyCells), (va.costs, va.emptyCells));
    final tb = b.map.industry(village.id)!.town!;
    expect(
      (tb.revenue, tb.delivered),
      (village.town!.revenue, village.town!.delivered),
    );
    expect(b.map.industry(farm.id)!.since, 0);
    expectBalanced(w);
  });

  test('older saves load with the new figures at zero', () {
    for (final name in [
      'magistrali_save_v3.json',
      'magistrali_save_v5_map2.json',
    ]) {
      final w = magWorldFromJson(
        jsonDecode(File('test/fixtures/$name').readAsStringSync())
            as Map<String, dynamic>,
      );
      for (final v in w.vehicles.values) {
        expect((v.costs, v.emptyCells), (0, 0));
      }
      for (final i in w.settlements) {
        expect(i.town!.revenue, 0);
      }
      expect(w.warehouses.every((x) => x.level == 1), isTrue);
      w.step(MagRules.ticksPerDay * 2);
      expectBalanced(w);
    }
  });

  test('the first motor technologies of the industrial age', () {
    final steel = MagTechTree.byId('steelbodies')!;
    expect(steel.requires, ['combustion']);
    expect(MagTechTree.byId('spareparts')!.requires, ['steelbodies']);
    expect(MagTechTree.byId('heavycargo')!.effects[MagBonus.pay], .03);
    final w = rich()..deliveries = 100;
    final before = w.capacityOf(w.vehicles.values.single);
    w.buyTruck('pickup');
    final truck = w.vehicles.values.last;
    final c0 = w.capacityOf(truck);
    expect(w.research('steelbodies'), isNull);
    expect(w.capacityOf(truck), greaterThan(c0));
    // Horses are not helped by motor technologies.
    expect(w.capacityOf(w.vehicles.values.first), before);
  });
}
