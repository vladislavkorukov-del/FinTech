import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S15 (1.87): achievements (META-02), the chronicle (META-05),
/// loans (FIN-15), the fleet in bulk (VEH-11), replacing old vehicles
/// (VEH-12), the minimum load (ROUTE-06), stops visited only when needed
/// (ROUTE-10); saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  MagWorld line() {
    final w = motorStart()..money = 1000000;
    final f = w.map.startFarm, p = w.map.startPlant;
    w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt));
    return w;
  }

  test('achievements pay once, from the real state; chronicle', () {
    final w = line();
    expect(MagAchievements.all.length, greaterThanOrEqualTo(20));
    expect(w.achievementProgress('fleet5'), 1);
    for (var k = 0; k < 4; k++) {
      w.buyTruck('pickup');
    }
    final money = w.money;
    w.step(MagRules.ticksPerDay);
    expect(w.achieved, contains('fleet5'));
    final paid = w.journal.entries.where((e) => e.category == 'achievements');
    expect(paid.map((e) => e.amount), contains(2000));
    expect(w.money, greaterThanOrEqualTo(money + 2000 - 500));
    w.step(MagRules.ticksPerDay * 2);
    expect(
      w.journal.entries.where((e) => e.category == 'achievements').length,
      paid.length,
    );
    expect(
      w.chronicle.map((e) => e.$2),
      contains('Достижение «Свой автопарк»'),
    );
    final b = reload(w);
    expect(b.achieved, w.achieved);
    expect(b.chronicle.length, w.chronicle.length);
  });

  test('loans: a limit by level, interest a day, paid back', () {
    final w = line()..money = 1000;
    expect(w.loanLimit, MagRules.loanBase + w.level * MagRules.loanPerLevel);
    expect(w.takeLoan(w.loanLimit + 1), isNotNull);
    expect(w.takeLoan(10000), isNull);
    expect((w.money, w.debt), (11000, 10000));
    final e = w.journal.entries.last;
    expect((e.kind, e.category), (MagEntryKind.financing, 'loan'));
    // Not revenue.
    expect(w.month.totalIncome, isNot(greaterThanOrEqualTo(10000)));
    final before = w.money;
    w.step(MagRules.ticksPerDay);
    expect(
      w.journal.entries.where((x) => x.category == 'interest').single.amount,
      -40,
    );
    expect(w.money, lessThan(before));
    expect(reload(w).debt, 10000);
    w.money = 100000;
    expect(w.repayLoan(4000), isNull);
    expect(w.debt, 6000);
    expect(w.repayLoan(1 << 30), isNull);
    expect(w.debt, 0);
    expect(w.repayLoan(1), 'Долга нет');
  });

  test('the fleet in bulk; an old vehicle replaced on its route', () {
    final w = line()..xp = MagWorldProgress.xpFor(6);
    final f = w.map.startFarm, p = w.map.startPlant;
    w.createRoute([f.id, p.id]);
    final r = w.routes.values.single;
    final pickup = w.vehicles.values.single;
    w.buyTruck('pickup');
    w.buyTruck('pickup');
    expect(w.assignIdle(r.id), 3);
    for (final v in w.vehicles.values) {
      v.wear = 80;
    }
    expect(w.repairAllCost, greaterThan(0));
    expect(w.repairAll(), 3);
    expect(w.vehicles.values.every((v) => v.wear == 0), isTrue);
    // A newer model of the same kind: the lorry (or better).
    final m = w.newerModelFor(pickup)!;
    expect(m.capacity, greaterThan(pickup.spec.capacity));
    expect(m.motorGoods, isTrue);
    final name = pickup.name;
    expect(w.replaceVehicle(pickup.id), isNull);
    expect(w.vehicles.containsKey(pickup.id), isFalse);
    final n = w.vehicles.values.last;
    expect((n.model, n.name, n.routeId), (m.id, name, r.id));
    expect(w.replaceAllOutdated(), 2);
  });

  test('minimum load: 100% waits to be full, 0% never waits', () {
    final w = line();
    final f = w.map.startFarm, p = w.map.startPlant;
    w.createRoute([f.id, p.id]);
    final r = w.routes.values.single;
    final truck = w.vehicles.values.single;
    w.created[MagCargo.grain] =
        (w.created[MagCargo.grain] ?? 0) + 2 - (f.stock[MagCargo.grain] ?? 0);
    f.stock[MagCargo.grain] = 2;
    w.assign(truck.id, r.id);
    expect(w.setMinLoad(r.id, 120), isNotNull);
    expect(w.setMinLoad(r.id, 0), isNull);
    var left = false;
    for (var k = 0; k < MagRules.ticksPerDay ~/ 2 && !left; k++) {
      w.step();
      left = truck.stop == 1 && truck.state == MagVehicleState.driving;
    }
    expect(left, isTrue);
    expect(truck.load, lessThan(w.capacityOf(truck)));
    expect(reload(w).routes[r.id]!.minLoad, 0);
  });

  test('a stop visited only when needed is passed by', () {
    final w = line();
    final f = w.map.startFarm, p = w.map.startPlant;
    // A logging camp: it takes no grain, and its wood is wanted by no
    // other stop — nothing to do there.
    final v = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.sawmill,
    );
    w.createRoute([f.id, v.id, p.id]);
    final r = w.routes.values.single;
    expect(w.setStopOrder(r.id, 1, ifCargo: true), isNull);
    final truck = w.vehicles.values.single;
    w.assign(truck.id, r.id);
    var atVillage = false;
    for (var k = 0; k < MagRules.ticksPerDay * 12; k++) {
      w.step();
      if (truck.stop == 1) atVillage = true;
      if ((w.delivered[MagCargo.grain] ?? 0) > 0) break;
    }
    expect(atVillage, isFalse);
    expect(w.delivered[MagCargo.grain], greaterThan(0));
    expect(reload(w).routes[r.id]!.ifCargo, {1});
  });
}
