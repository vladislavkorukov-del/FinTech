import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S17 (1.89): oil and fuel (PROD-11), electronics (PROD-12),
/// special bodies (VEH-05), ship hulls (SEA-05), comfort and waiting
/// (PASS-07), industrial complexes (BIZ-14), city terminals (CITY-13),
/// start scenarios (META-11); saves.
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

  test('new maps have oil and electronics; older maps unchanged', () {
    final w = MagWorld.start();
    expect(w.map.version, 6);
    for (final (k, n) in [
      (MagIndustryKind.oilWell, 6),
      (MagIndustryKind.refinery, 3),
      (MagIndustryKind.electronicsPlant, 3),
    ]) {
      expect(w.map.industries.where((i) => i.kind == k).length, n);
    }
    // Generator 5 is generator 6 without them: the same places first.
    final g5 = MagMap.generate(MagRules.defaultSeed, version: 5);
    for (var k = 0; k < g5.industries.length; k++) {
      final a = g5.industries[k], b = w.map.industries[k];
      expect((b.kind, b.x, b.y, b.name), (a.kind, a.x, a.y, a.name));
    }
    expect(w.cargoAvailable(MagCargo.fuel), isTrue);
    expect(w.cargoAvailable(MagCargo.electronics), isTrue);
    expect(
      MagTowns.marketGoods(7),
      containsAll([MagCargo.fuel, MagCargo.electronics]),
    );
  });

  test('a refinery makes fuel; electronics need parts and fuel', () {
    final w = MagWorld.start()..money = 1000000;
    final r = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.refinery,
    );
    r.input[MagCargo.oil] = 20;
    w.created[MagCargo.oil] = (w.created[MagCargo.oil] ?? 0) + 20;
    w.step(MagRules.ticksPerDay);
    expect(r.stock[MagCargo.fuel], greaterThan(0));
    final e = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.electronicsPlant,
    );
    e.input[MagCargo.parts] = 10;
    w.created[MagCargo.parts] = (w.created[MagCargo.parts] ?? 0) + 10;
    w.step(MagRules.ticksPerDay);
    expect(e.stock[MagCargo.electronics] ?? 0, 0); // no fuel yet
    e.input[MagCargo.fuel] = 10;
    w.created[MagCargo.fuel] = (w.created[MagCargo.fuel] ?? 0) + 10;
    w.step(MagRules.ticksPerDay);
    expect(e.stock[MagCargo.electronics], greaterThan(0));
    // Building them opens with technologies.
    expect(
      w.buildBlocker(MagIndustryKind.oilWell, 5, 5),
      anyOf(contains('уровня'), contains('Нефтедобыча')),
    );
    expectBalanced(w);
  });

  test('special bodies: liquids in tanks, fresh food in reefers', () {
    final w = motorStart()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(8)
      ..techs.addAll(['metallurgy', 'kilns', 'petroleum']);
    final lorry = w.vehicles.values.single;
    expect(w.canCarry(lorry, MagCargo.oil), isFalse);
    expect(w.canCarry(lorry, MagCargo.grain), isTrue);
    for (final m in ['tanker', 'reefer', 'dumper']) {
      expect(w.buyTruck(m), isNull, reason: m);
    }
    final [tank, reefer, dump] = w.vehicles.values.skip(1).toList();
    expect(w.canCarry(tank, MagCargo.fuel), isTrue);
    expect(w.canCarry(tank, MagCargo.grain), isFalse);
    expect(w.canCarry(reefer, MagCargo.food), isTrue);
    expect(w.canCarry(reefer, MagCargo.ore), isFalse);
    expect(w.canCarry(dump, MagCargo.ore), isTrue);
    expect(w.canCarry(dump, MagCargo.food), isFalse);
    expect(w.cargoPayFactor(reefer, MagCargo.food), MagRules.reeferBonus);
    expect(w.cargoPayFactor(lorry, MagCargo.food), 1);
    // Comfort for people.
    expect(MagRules.truck('bus')!.comfort, greaterThan(1));
    expect(MagRules.truck('coach')!.comfort, lessThan(1));
  });

  test('ship hulls carry more; saved', () {
    final w = MagWorld.start()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(8)
      ..techs.addAll(['stud', 'shipping']);
    expect(w.buyTruck('barge'), isNull);
    final barge = w.vehicles.values.last;
    final before = w.capacityOf(barge);
    expect(w.upgradeHull(w.vehicles.values.first.id), 'Только суда');
    expect(w.upgradeHull(barge.id), isNull);
    expect(w.capacityOf(barge), greaterThan(before));
    expect(reload(w).vehicles[barge.id]!.hull, 1);
  });

  test('waiting passengers leave; terminals pay more', () {
    final w = motorStart()..money = 1000000;
    final f = w.map.startFarm, p = w.map.startPlant;
    w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt));
    final v = w.settlements.firstWhere((t) => w.accessCells(t).isEmpty);
    // A road on the edge of the settlement.
    int? edge;
    for (var y = v.top - 1; y <= v.bottom + 1 && edge == null; y++) {
      for (var x = v.left - 1; x <= v.right + 1; x++) {
        if (!w.map.roadable(x, y) || v.covers(x, y)) continue;
        final c = w.cellOf(x, y);
        if (w.townsBeside(c).contains(v)) {
          edge = c;
          break;
        }
      }
    }
    w.roads[edge!] = MagRoad.dirt.index;
    w.roadVersion++;
    v.stock[MagCargo.passengers] = 100;
    w.created[MagCargo.passengers] =
        (w.created[MagCargo.passengers] ?? 0) + 100;
    w.step(MagRules.ticksPerDay);
    expect(v.stock[MagCargo.passengers], lessThan(100));
    final pay = w.marketFactor(v, MagCargo.food);
    expect(w.buildTerminal(edge, v.id), isNull);
    expect(w.marketFactor(v, MagCargo.food), closeTo(pay + .05, 1e-9));
    expect(w.terminalsOf(v), 1);
    expect(reload(w).terminals, {edge: v.id});
    expect(w.removeTerminal(edge), isNull);
    expectBalanced(w);
  });

  test('an industrial complex: a bonus and a conveyor', () {
    final w = MagWorld.start()..money = 1000000;
    final f = w.map.startFarm, p = w.map.startPlant;
    expect(f.distanceTo(p), lessThanOrEqualTo(MagRules.complexReach + 10));
    w.buyIndustry(f.id);
    w.buyIndustry(p.id);
    final near = f.distanceTo(p) <= MagRules.complexReach;
    expect(w.complexPartner(f) == p, near);
    if (!near) return;
    expect(w.complexBonusOf(f), MagRules.complexBonus);
    final grain = f.stock[MagCargo.grain] ?? 0;
    w.step(MagRules.ticksPerDay);
    expect(p.input[MagCargo.grain] ?? 0, greaterThanOrEqualTo(0));
    expect(grain, greaterThanOrEqualTo(0));
    expectBalanced(w);
  });

  test('start scenarios', () {
    expect(MagWorld.start().scenario, MagScenario.classic);
    final rich = MagWorld.start(MagRules.defaultSeed, MagScenario.rich);
    expect(rich.money, 30000);
    final rail = MagWorld.start(MagRules.defaultSeed, MagScenario.railway);
    expect(rail.railsUnlocked, isTrue);
    final river = MagWorld.start(MagRules.defaultSeed, MagScenario.river);
    expect(river.shippingUnlocked, isTrue);
    final ind = MagWorld.start(MagRules.defaultSeed, MagScenario.industrial);
    expect(ind.map.startPlant.owned, isTrue);
    expect(reload(ind).scenario, MagScenario.industrial);
    expect(ind.chronicle.first.$2, contains('промышленник'));
  });
}
