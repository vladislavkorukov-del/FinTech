import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Master plan stage 1: independent settlements. The ten levels and the
/// production chains as configuration, new maps with hamlets and room to
/// grow, old maps keeping their towns, supply and growth that each
/// settlement lives on its own, land that never covers roads, and saves.
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

  /// Is a set of cells one connected piece?
  bool connected(Set<int> cells) {
    final seen = <int>{cells.first};
    final todo = [cells.first];
    while (todo.isNotEmpty) {
      final k = todo.removeLast();
      for (var d = 0; d < 4; d++) {
        final n = MagSettlement.key(
          MagSettlement.keyX(k) + MagDir.dx[d],
          MagSettlement.keyY(k) + MagDir.dy[d],
        );
        if (cells.contains(n) && seen.add(n)) todo.add(n);
      }
    }
    return seen.length == cells.length;
  }

  MagIndustry startVillage(MagWorld w) =>
      w.settlements.firstWhere((i) => i.name == 'Луговое');

  /// A road from the plant to a free cell next to [town].
  void roadTo(MagWorld w, MagIndustry from, MagIndustry town) {
    final targets = [
      for (var y = town.top - 1; y <= town.bottom + 1; y++)
        for (var x = town.left - 1; x <= town.right + 1; x++)
          if (w.map.roadable(x, y) &&
              List.generate(
                4,
                (d) => town.covers(x + MagDir.dx[d], y + MagDir.dy[d]),
              ).any((e) => e))
            (x, y),
    ];
    for (final (x, y) in targets) {
      final plan = w.planRoad(
        from.x + 1,
        from.y + from.size,
        x,
        y,
        MagRoad.dirt,
      );
      if (plan.error == null && w.buildRoad(plan) == null) return;
    }
    fail('no road to ${town.name}');
  }

  test('ten levels as configuration, each opening new ways to earn', () {
    expect(MagTowns.levels.length, 10);
    expect(MagTowns.levels.map((l) => l.cells).toList(), [
      1,
      2,
      3,
      5,
      7,
      10,
      15,
      21,
      28,
      37,
    ]);
    for (var k = 0; k < 10; k++) {
      final l = MagTowns.levels[k];
      expect(l.level, k + 1);
      expect(l.name, isNotEmpty);
      expect(l.opens, isNotEmpty, reason: 'level ${l.level} opens nothing');
      expect(l.needs, isNotEmpty);
      if (k > 0) {
        final prev = MagTowns.levels[k - 1];
        expect(l.population, greaterThan(prev.population));
        expect(l.payBonus, greaterThanOrEqualTo(prev.payBonus));
        // Needs grow with the level.
        final total = l.needs.values.fold(0, (a, b) => a + b);
        final before = prev.needs.values.fold(0, (a, b) => a + b);
        expect(total, greaterThanOrEqualTo(before));
      }
      expect(l.development.isEmpty, k == 9, reason: 'level ${l.level}');
    }
  });

  test('the production chains are whole, era by era', () {
    final ids = MagEconomy.resources.map((r) => r.id).toSet();
    expect(ids.length, MagEconomy.resources.length);
    for (final rc in MagEconomy.recipes) {
      for (final id in [...rc.inputs.keys, ...rc.outputs.keys]) {
        expect(ids, contains(id), reason: rc.building);
      }
      for (final o in rc.outputs.keys) {
        expect(MagEconomy.resource(o)!.raw, isFalse, reason: rc.building);
        expect(rc.inputs.containsKey(o), isFalse); // not made from itself
      }
      // Every input can be made in the recipe's era.
      final can = MagEconomy.makeable(rc.era);
      for (final i in rc.inputs.keys) {
        expect(can, contains(i), reason: '${rc.building}: $i');
      }
    }
    // By the last era everything can be made.
    expect(MagEconomy.makeable(MagEra.electric), containsAll(ids));
    // The cargo the game already carries is all in the catalogue.
    for (final c in MagCargo.values) {
      expect(MagEconomy.resource(c.name)?.active, isTrue, reason: c.name);
    }
    // Settlements only ask for cargo the simulation carries.
    for (final l in MagTowns.levels) {
      for (final c in [...l.needs.keys, ...l.development.keys]) {
        expect(MagCargo.values, contains(c));
      }
    }
  });

  test('new games: hamlets and villages with room to grow', () {
    for (final seed in [MagRules.defaultSeed, 3, 77, 2026]) {
      final w = motorStart(seed);
      expect(w.map.version, 2);
      final towns = w.settlements.toList();
      expect(towns.length, greaterThanOrEqualTo(7), reason: 'seed $seed');
      expect(towns.map((t) => t.town!.level).toSet(), {1, 2});
      expect(
        w.map.industries.where((i) => i.kind == MagIndustryKind.city),
        isEmpty,
      );
      for (final t in towns) {
        expect(t.town!.cells.length, t.town!.spec.cells);
        expect(connected(t.town!.cells), isTrue);
        expect(t.town!.history, isNotEmpty);
        expect(t.town!.population, t.town!.spec.population);
      }
      // Several can become big cities on the empty land.
      var roomy = 0;
      for (final t in towns) {
        final land = Set<int>.of(t.town!.cells);
        final ok = MagMap.expandCells(land, 15, (x, y) {
          if (!w.map.inside(x, y)) return false;
          final g = w.map.at(x, y);
          if (g == MagTerrain.lake || g == MagTerrain.river) return false;
          final o = w.map.industryAt(x, y);
          return o == null || o == t;
        });
        if (ok) roomy++;
      }
      expect(roomy, greaterThanOrEqualTo(3), reason: 'seed $seed');
      // The first line still works from the start.
      final f = w.map.startFarm, p = w.map.startPlant;
      expect(
        w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt).error,
        isNull,
      );
    }
  });

  test('old maps keep their towns as settlements of a fitting level', () {
    final w = MagWorld(map: MagMap.generate(MagRules.defaultSeed));
    expect(w.map.version, 1);
    final villages = w.map.industries.where(
      (i) => i.kind == MagIndustryKind.village,
    );
    final cities = w.map.industries.where(
      (i) => i.kind == MagIndustryKind.city,
    );
    expect(villages, isNotEmpty);
    expect(cities, isNotEmpty);
    for (final v in villages) {
      expect(v.town!.level, 3);
      expect(v.town!.cells.length, 4);
      expect(v.centerX, v.x + 1.0); // the centre of the old 2×2 square
      expect(v.accepts, contains(MagCargo.food));
    }
    for (final c in cities) {
      expect(c.town!.level, 6);
      expect(c.town!.cells.length, 9);
      expect(c.centerY, c.y + 1.5);
      expect(c.accepts, containsAll([MagCargo.food, MagCargo.goods]));
    }
  });

  test('settlements live on their own: supplied ones grow, others wait', () {
    final w = motorStart()..money = 100000;
    final farm = w.map.startFarm,
        plant = w.map.startPlant,
        village = startVillage(w);
    w.buildRoad(
      w.planRoad(
        farm.x + farm.size,
        farm.y,
        plant.x - 1,
        plant.y,
        MagRoad.dirt,
      ),
    );
    roadTo(w, plant, village);
    roadTo(w, farm, village);
    w.createRoute([farm.id, plant.id]);
    w.createRoute([plant.id, village.id]);
    w.createRoute([farm.id, village.id]);
    w.buyTruck('pickup');
    w.buyTruck('pickup');
    w.buyTruck('pickup');
    final ids = w.vehicles.keys.toList();
    final routes = w.routes.keys.toList();
    w.assign(ids[0], routes[0]);
    w.assign(ids[1], routes[1]);
    w.assign(ids[2], routes[1]);
    w.assign(ids[3], routes[2]);
    final others = w.settlements.where((s) => s != village).toList();
    for (var t = 0; t < 6000; t++) {
      w.step();
      if (t % 500 == 0) expectBalanced(w);
    }
    final v = village.town!;
    expect(v.reputation, greaterThan(0));
    expect(v.satisfaction, isNotEmpty);
    expect(v.averageSatisfaction, greaterThan(0));
    expect(v.population, greaterThan(MagTowns.of(2).population));
    // Food beyond the daily need went towards growth, no more than asked.
    expect(v.devStock[MagCargo.food] ?? 0, greaterThan(0));
    expect(v.devStock[MagCargo.food]!, lessThanOrEqualTo(40));
    expect(v.history.any((e) => e.text.contains('Первая поставка')), isTrue);
    // Settlements nobody supplies stay as they were (never below level).
    for (final o in others) {
      expect(o.town!.population, o.town!.spec.population);
      expect(o.town!.reputation, 0);
    }
    expectBalanced(w);
  });

  test('growth: real land, the delivery used once, never over a road', () {
    final w = motorStart();
    final village = startVillage(w);
    final t = village.town!;
    // Ready to grow: people and the growth delivery (recorded as made).
    t.population = MagTowns.of(3).population;
    t.satisfaction.addAll(List.filled(6, 1.0)); // well supplied lately
    for (final e in t.spec.development.entries) {
      t.devStock[e.key] = e.value;
      w.created[e.key] = (w.created[e.key] ?? 0) + e.value;
    }
    final destroyed = Map.of(w.destroyed);
    final version = w.roadVersion;
    final cellsBefore = Set.of(t.cells);
    w.step(MagRules.ticksPerDay);
    expect(t.level, 3);
    expect(t.cells.length, 3);
    expect(t.cells.containsAll(cellsBefore), isTrue);
    expect(connected(t.cells), isTrue);
    expect(t.devStock, isEmpty);
    expect(
      w.destroyed[MagCargo.food]! - (destroyed[MagCargo.food] ?? 0),
      greaterThanOrEqualTo(40),
    );
    expect(w.roadVersion, greaterThan(version));
    expect(t.history.last.text, contains('Большое село'));
    expectBalanced(w);
    // Ringed by roads, it cannot grow: a reason, the level and stock kept.
    for (var y = village.top - 1; y <= village.bottom + 1; y++) {
      for (var x = village.left - 1; x <= village.right + 1; x++) {
        if (w.map.roadable(x, y)) {
          w.buildRoad(w.planRoad(x, y, x, y, MagRoad.dirt));
        }
      }
    }
    // Any cell next to its land that is still free gets a road too.
    for (final k in t.cells.toList()) {
      for (var d = 0; d < 4; d++) {
        final x = MagSettlement.keyX(k) + MagDir.dx[d];
        final y = MagSettlement.keyY(k) + MagDir.dy[d];
        if (w.map.roadable(x, y) && !w.hasRoad(x, y)) {
          w.buildRoad(w.planRoad(x, y, x, y, MagRoad.dirt));
        }
      }
    }
    t.population = MagTowns.of(4).population;
    t.satisfaction
      ..clear()
      ..addAll(List.filled(6, 1.0));
    for (final e in t.spec.development.entries) {
      t.devStock[e.key] = e.value;
      w.created[e.key] = (w.created[e.key] ?? 0) + e.value;
    }
    w.step(MagRules.ticksPerDay);
    if (t.level == 3) {
      expect(t.blocked, isNotNull);
      expect(t.devStock, isNotEmpty); // nothing used up
    }
    for (final k in t.cells) {
      expect(w.hasRoad(MagSettlement.keyX(k), MagSettlement.keyY(k)), isFalse);
    }
    expectBalanced(w);
  });

  test('poor supply never takes a level away', () {
    final w = MagWorld(map: MagMap.generate(MagRules.defaultSeed));
    final city = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.city,
    );
    final t = city.town!..population = 2500;
    w.step(MagRules.ticksPerDay * 200);
    expect(t.level, 6);
    expect(t.population, MagTowns.of(6).population);
    expect(t.averageSatisfaction, 0);
  });

  test('needs and growth skip cargo nobody can make', () {
    final w = MagWorld(map: MagMap.generate(MagRules.defaultSeed));
    final city = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.city,
    );
    expect(w.needsOf(city), contains(MagCargo.ore));
    w.map.industries.removeWhere((i) => i.kind == MagIndustryKind.mine);
    expect(w.cargoAvailable(MagCargo.ore), isFalse);
    expect(w.needsOf(city), isNot(contains(MagCargo.ore)));
    expect(w.missingForGrowth(city), isNot(contains(MagCargo.ore)));
  });

  test('saves: format 5 round trip; old formats keep their towns', () {
    final w = motorStart();
    final t = startVillage(w).town!;
    t.population = MagTowns.of(3).population;
    t.satisfaction.addAll(List.filled(6, 1.0)); // well supplied lately
    for (final e in t.spec.development.entries) {
      t.devStock[e.key] = e.value;
      w.created[e.key] = (w.created[e.key] ?? 0) + e.value;
    }
    w.step(MagRules.ticksPerDay + 7);
    expect(t.level, 3);
    final saved = jsonEncode(w.toJson());
    final b = magWorldFromJson(jsonDecode(saved) as Map<String, dynamic>);
    expect(jsonEncode(b.toJson()), saved);
    expect(startVillage(b).town!.cells, t.cells);
    w.step(3000);
    b.step(3000);
    expect(jsonEncode(b.toJson()), jsonEncode(w.toJson()));
    // Land on a lake is refused.
    final bad = jsonDecode(saved) as Map<String, dynamic>;
    final lake = [
      for (var y = 0; y < 64; y++)
        for (var x = 0; x < 64; x++)
          if (w.map.at(x, y) == MagTerrain.lake) MagSettlement.key(x, y),
    ].first;
    final entry = (bad['settlements'] as List).first as Map;
    (entry['cells'] as List).add(lake);
    expect(() => magWorldFromJson(bad), throwsFormatException);
    for (final f in ['v1', 'v2', 'v3']) {
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/magistrali_save_$f.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final old = magWorldFromJson(raw);
      expect(old.map.version, 1, reason: f);
      expect(old.money, raw['money']);
      expect(old.settlements.map((s) => s.town!.level).toSet(), {3, 6});
      expect(
        old.settlements.every(
          (s) => s.town!.history.single.text.contains('1.72'),
        ),
        isTrue,
      );
      old.step(1000);
      final again = magWorldFromJson(
        jsonDecode(jsonEncode(old.toJson())) as Map<String, dynamic>,
      );
      expect(again.map.version, 1);
      expect(jsonEncode(again.toJson()), jsonEncode(old.toJson()));
      expectBalanced(old);
    }
  });
}
