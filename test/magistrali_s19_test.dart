import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S19 (1.91): rivals (META-09) and buying them out (META-10), stars
/// of a megalopolis (META-12), future transport (TECH-06), the collection
/// (VEH-14, META-08), the sandbox (MAP-12); reputation (CITY-12, CONT-09),
/// research by achievements (TECH-08), the overdraft (FIN-16); saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  test('rivals appear at level 5, claim places and cut their pay', () {
    final w = motorStart()..money = 1000000;
    w.step(MagRules.ticksPerDay);
    expect(w.rivals, isEmpty);
    w.xp = MagWorldProgress.xpFor(MagRules.rivalLevel);
    w.step(MagRules.ticksPerDay * MagRules.rivalEvery * 2);
    expect(w.rivals.length, 2);
    expect(w.rivalsMet, isTrue);
    final claimed = w.rivals.expand((r) => r.claims).toList();
    expect(claimed, isNotEmpty);
    final place = w.map.industry(claimed.first)!;
    expect(w.rivalAt(place), isNotNull);
    expect(w.rivalFactor(place), closeTo(1 - MagRules.rivalCut, 1e-9));
    expect(w.rivalFactor(w.settlements.first), 1);
    final back = reload(w);
    expect(back.rivals.length, 2);
    expect(back.rivals.first.claims, w.rivals.first.claims);
    expect(back.rivalsMet, isTrue);
  });

  test('buying a rival out makes its places the company\'s', () {
    final w = motorStart()..money = 10;
    w.xp = MagWorldProgress.xpFor(MagRules.rivalLevel);
    w.step(MagRules.ticksPerDay * MagRules.rivalEvery * 2);
    final r = w.rivals.first;
    final ids = [...r.claims];
    expect(w.acquireRival(0), contains('Не хватает'));
    w.money = w.rivalValue(r) + 1;
    expect(w.acquireRival(0), isNull);
    expect(w.money, 1);
    expect(w.rivals.length, 1);
    for (final id in ids) {
      final i = w.map.industry(id)!;
      if (w.forSale(i)) expect(i.owned, isTrue);
    }
    expect(w.acquireRival(5), isNotNull);
  });

  test('no rivals and no achievement rewards in the sandbox', () {
    final w = MagWorld.start(MagRules.defaultSeed, MagScenario.sandbox);
    expect(w.money, 10000000);
    expect(w.level, greaterThanOrEqualTo(30));
    expect(w.techs.length, MagTechTree.all.length);
    w.step(MagRules.ticksPerDay * 14);
    expect(w.rivals, isEmpty);
    expect(w.achieved, isEmpty);
    expect(w.buyTruck('maglev'), isNull);
    expect(reload(w).scenario, MagScenario.sandbox);
  });

  test('stars of a megalopolis: after 20 happy days at level 10', () {
    final w = motorStart();
    final t = w.settlements.first;
    final s = t.town!;
    expect(w.starsOf(t), 0);
    s.level = 10;
    s.satisfaction
      ..clear()
      ..addAll([1, 1, 1]);
    final pop = s.population;
    for (var d = 0; d < MagRules.starDays; d++) {
      w.step(MagRules.ticksPerDay);
      s.satisfaction
        ..clear()
        ..addAll([1, 1, 1]);
    }
    expect(w.starsOf(t), greaterThanOrEqualTo(1));
    expect(s.population, greaterThan(pop));
    expect(reload(w).starsOf(reload(w).settlements.first), w.starsOf(t));
  });

  test('the collection pays at 5 models and opens the veteran at 8', () {
    final w = MagWorld.start()
      ..money = 10000000
      ..xp = MagWorldProgress.xpFor(30);
    w.techs.addAll(MagTechTree.all.map((t) => t.id));
    expect(w.buyTruck('veteran'), contains('коллекции'));
    final road = [
      for (final m in MagRules.trucks)
        if (!m.water && !m.rail && m.id != 'veteran') m.id,
    ];
    final paid0 = w.month.income['collection'] ?? 0;
    for (final id in road.take(5)) {
      expect(w.buyTruck(id), isNull, reason: id);
    }
    expect(w.collected.length, greaterThanOrEqualTo(5));
    expect((w.month.income['collection'] ?? 0) - paid0, greaterThan(0));
    for (final id in road.skip(5).take(4)) {
      w.buyTruck(id);
    }
    expect(w.collected.length, greaterThanOrEqualTo(MagRules.veteranAfter));
    expect(w.buyTruck('veteran'), isNull);
    final vet = w.vehicles.values.last;
    expect(w.cargoPayFactor(vet, MagCargo.grain), MagRules.veteranBonus);
    final back = reload(w);
    expect(back.collected, w.collected);
    expect(back.collectionPaid, w.collectionPaid);
  });

  test('future transport needs its research', () {
    final w = MagWorld.start()
      ..money = 10000000
      ..xp = MagWorldProgress.xpFor(30);
    w.techs.addAll(['combustion', 'stud', 'steam']);
    expect(w.buyTruck('autotruck'), contains('технология'));
    expect(MagTechTree.byId('autopilot'), isNotNull);
    expect(MagTechTree.byId('maglev'), isNotNull);
    w.techs.add('autopilot');
    expect(w.buyTruck('autotruck'), isNull);
    expect(MagRules.truck('maglev')!.rail, isTrue);
  });

  test('reputation pays up to 10% more; achievements cheapen research', () {
    final w = motorStart();
    final t = w.settlements.first;
    expect(w.reputationBonus(t), 0);
    t.town!.reputation = 250;
    expect(w.reputationBonus(t), closeTo(.05, 1e-9));
    t.town!.reputation = 1 << 30;
    expect(w.reputationBonus(t), MagRules.reputationMax);
    expect(w.reputationBonus(w.map.startFarm), 0);
    final tech = MagTechTree.all.first;
    expect(w.techCost(tech), tech.cost);
    for (var k = 0; k < 30; k++) {
      w.achieved['a$k'] = 0;
    }
    expect(w.techCost(tech), (tech.cost * .8).round());
  });

  test('an overdraft: 1% a day on the minus, warned at 30 days', () {
    final w = motorStart()..money = -10000;
    w.step(MagRules.ticksPerDay);
    expect(w.negativeDays, greaterThanOrEqualTo(1));
    expect(w.money, lessThan(-10000));
    expect(reload(w).negativeDays, w.negativeDays);
    w.money = 100;
    w.step(MagRules.ticksPerDay);
    expect(w.negativeDays, 0);
  });
}
