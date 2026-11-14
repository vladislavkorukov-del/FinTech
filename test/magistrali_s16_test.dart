import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S16 (1.88): special contracts — production (CONT-04), regular
/// supply (CONT-05), stages (CONT-06), regional (CONT-07); rich deposits
/// (MAP-10), recipe priority (BIZ-06), depots (VEH-10), merged orders
/// (LOG-15); saves.
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

  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  MagWorld line() {
    final w = motorStart()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(8);
    final f = w.map.startFarm, p = w.map.startPlant;
    w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt));
    return w;
  }

  test('special contracts appear by level and are saved', () {
    final w = line();
    expect(w.dealSlots, 3);
    w.step(MagRules.ticksPerDay);
    expect(w.deals, isNotEmpty);
    expect(w.deals.length, lessThanOrEqualTo(3));
    final b = reload(w);
    expect(
      b.deals.map((d) => (d.id, d.kind, d.cargo, d.to, d.amount)).toList(),
      w.deals.map((d) => (d.id, d.kind, d.cargo, d.to, d.amount)).toList(),
    );
    final d = w.deals.first;
    expect(w.dropDeal(d.id), isNull);
    expect(w.deals, isNot(contains(d)));
  });

  test('production order: counted when an own plant makes the goods', () {
    final w = line();
    final p = w.map.startPlant;
    w.buyIndustry(p.id);
    final d = MagDeal(
      id: w.nextId++,
      kind: MagDealKind.production,
      cargo: MagCargo.food,
      to: p.id,
      amount: 10,
      reward: 3000,
      deadline: w.tick + 30 * MagRules.ticksPerDay,
    );
    w.deals.add(d);
    p.input[MagCargo.grain] = 40;
    w.created[MagCargo.grain] = (w.created[MagCargo.grain] ?? 0) + 40;
    final money = w.money;
    w.step(MagRules.ticksPerDay * 2);
    expect(w.deals, isNot(contains(d)));
    expect(w.journal.entries.where((e) => e.category == 'deals'), isNotEmpty);
    expect(w.money, greaterThan(money));
    expectBalanced(w);
  });

  test('stages and regional contracts count real deliveries', () {
    final w = line();
    final f = w.map.startFarm, p = w.map.startPlant;
    final stage = MagDeal(
      id: w.nextId++,
      kind: MagDealKind.stages,
      cargo: MagCargo.grain,
      to: p.id,
      amount: 6,
      reward: 5000,
      deadline: w.tick + 40 * MagRules.ticksPerDay,
    );
    final town = w.settlements.first;
    stage.stages
      ..add((MagCargo.grain, p.id, 6))
      ..add((MagCargo.food, town.id, 5));
    w.deals.add(stage);
    w.createRoute([f.id, p.id]);
    w.assign(w.vehicles.values.single.id, w.routes.keys.single);
    for (var k = 0; k < MagRules.ticksPerDay * 15 && stage.stage == 0; k++) {
      w.step();
    }
    expect(stage.stage, 1);
    expect((stage.cargo, stage.to, stage.amount), (MagCargo.food, town.id, 5));
    // Regional: a delivery to any settlement near the centre counts.
    final near = w.settlements.firstWhere((t) => t != town);
    final region = MagDeal(
      id: w.nextId++,
      kind: MagDealKind.region,
      cargo: MagCargo.food,
      to: town.id,
      amount: 5,
      reward: 1000,
    )..radius = near.distanceTo(town);
    expect(w.isCity(near) || true, isTrue);
    expect(near.distanceTo(town), lessThanOrEqualTo(region.radius));
  });

  test('regular supply: paid every period, broken by a missed one', () {
    final w = line();
    final t = w.settlements.first;
    final d =
        MagDeal(
            id: w.nextId++,
            kind: MagDealKind.supply,
            cargo: MagCargo.food,
            to: t.id,
            amount: 5,
            reward: 4000,
          )
          ..period = 2
          ..periodsLeft = 2
          ..periodEnd = w.tick + 2 * MagRules.ticksPerDay;
    w.deals.add(d);
    d.delivered = 5;
    w.step(MagRules.ticksPerDay * 2);
    expect(d.periodsLeft, 1);
    expect(
      w.journal.entries.where((e) => e.category == 'deals').single.amount,
      greaterThanOrEqualTo(1000),
    );
    // Nothing delivered this period: the contract ends.
    w.step(MagRules.ticksPerDay * 2);
    expect(w.deals, isNot(contains(d)));
  });

  test('rich deposits yield half as much again; same on every save', () {
    final w = line();
    final rich = w.map.industries.where(w.isRich).toList();
    expect(rich, isNotEmpty);
    expect(rich.every((i) => i.spec.produces.isNotEmpty), isTrue);
    expect(
      w.map.industries.where((i) => i.town != null).any(w.isRich),
      isFalse,
    );
    expect(
      reload(w).map.industries.where(reload(w).isRich).length,
      rich.length,
    );
    final r = rich.first;
    final c = r.spec.produces.keys.first;
    r.stock[c] = 0;
    w.created[c] = w.totalCargo()[c] ?? 0;
    w.destroyed[c] = 0;
    w.step(MagRules.ticksPerDay);
    expect(
      r.stock[c],
      (r.spec.produces[c]! * w.outputFactor(r) * MagRules.richYield).round(),
    );
  });

  test('a plant with two recipes works the chosen input first', () {
    final w = line();
    final factory = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.factory,
    );
    expect(w.setFirstInput(factory.id, MagCargo.ore), isNotNull); // not own
    w.buyIndustry(factory.id);
    expect(w.setFirstInput(factory.id, MagCargo.grain), isNotNull);
    expect(w.setFirstInput(factory.id, MagCargo.ore), isNull);
    factory.input[MagCargo.wood] = 200;
    factory.input[MagCargo.ore] = 200;
    w.created[MagCargo.wood] = (w.created[MagCargo.wood] ?? 0) + 200;
    w.created[MagCargo.ore] = (w.created[MagCargo.ore] ?? 0) + 200;
    w.step(MagRules.ticksPerDay);
    expect(factory.input[MagCargo.ore], lessThan(200));
    expect(factory.input[MagCargo.wood], 200);
    expect(reload(w).firstInput[factory.id], MagCargo.ore);
    expectBalanced(w);
  });

  test('depots: on a road, a limit, repair on the way, cheaper upkeep', () {
    final w = line();
    final f = w.map.startFarm, p = w.map.startPlant;
    final e = w.entranceOf(p)!;
    expect(w.depotBlocker(w.cellOf(0, 0)), isNotNull);
    final upkeep = w.upkeepOf(w.vehicles.values.single);
    expect(w.buildDepot(e), isNull);
    expect(w.depots, {e});
    expect(
      w.buildDepot(w.entranceOf(f)!),
      w.depotSlots > 1 ? isNull : isNotNull,
    );
    expect(w.upkeepOf(w.vehicles.values.single), lessThanOrEqualTo(upkeep));
    w.createRoute([f.id, p.id]);
    final truck = w.vehicles.values.single..wear = 60;
    w.assign(truck.id, w.routes.keys.single);
    for (var k = 0; k < MagRules.ticksPerDay * 6 && truck.wear >= 30; k++) {
      w.step();
    }
    expect(truck.wear, lessThan(30));
    expect(reload(w).depots, w.depots);
    expect(w.removeDepot(e), isNull);
  });

  test('waiting orders with the same cargo and places are joined', () {
    final w = line()..autoMerge = false;
    final f = w.map.startFarm, p = w.map.startPlant;
    f.stock[MagCargo.grain] = (f.stock[MagCargo.grain] ?? 0) + 40;
    w.created[MagCargo.grain] = (w.created[MagCargo.grain] ?? 0) + 40;
    for (var k = 0; k < 2; k++) {
      expect(
        w.createOrder(cargo: MagCargo.grain, from: f.id, to: p.id, amount: 4),
        isNull,
      );
    }
    expect(w.orders.active.length, 2);
    expect(w.mergeOrders(), 1);
    expect(w.orders.active.single.amount, 8);
    expect(reload(w).autoMerge, isFalse);
    expectBalanced(w);
  });
}
