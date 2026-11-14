import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Master plan stage 4: settlements growing from level 1 to 3. Growth asks
/// for the new goods (bread, planks, stone) when the world can make them;
/// a development contract pays once per level; surplus growth stock goes
/// to the market; contracts never ask for what nobody makes; a sensible
/// pace of growth.
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

  List<(int, int)> sides(MagWorld w, MagIndustry i) => [
    for (var y = i.top - 1; y <= i.bottom + 1; y++)
      for (var x = i.left - 1; x <= i.right + 1; x++)
        if (w.map.roadable(x, y) &&
            List.generate(
              4,
              (d) => i.covers(x + MagDir.dx[d], y + MagDir.dy[d]),
            ).any((e) => e))
          (x, y),
  ];

  void connect(MagWorld w, MagIndustry a, MagIndustry b) {
    for (final (ax, ay) in sides(w, a)) {
      for (final (bx, by) in sides(w, b)) {
        final plan = w.planRoad(ax, ay, bx, by, MagRoad.dirt);
        if (plan.error == null && w.buildRoad(plan) == null) {
          if (w.connected(a, b)) return;
        }
      }
    }
    fail('cannot join ${a.name} and ${b.name}');
  }

  void give(MagWorld w, Map<MagCargo, int> into, MagCargo c, int n) {
    into[c] = (into[c] ?? 0) + n;
    w.created[c] = (w.created[c] ?? 0) + n;
  }

  MagIndustry startVillage(MagWorld w) =>
      w.settlements.firstWhere((i) => i.name == 'Луговое');

  test('growth asks for the new goods where the world makes them', () {
    final w = MagWorld.start();
    final hamlet = w.settlements.firstWhere((t) => t.town!.level == 1);
    expect(
      w.developmentAsks(hamlet).keys,
      containsAll([MagCargo.planks, MagCargo.bread]),
    );
    final village = startVillage(w);
    expect(
      w.developmentAsks(village).keys,
      containsAll([MagCargo.planks, MagCargo.stone, MagCargo.bread]),
    );
    expect(w.developmentReward(village), greaterThan(0));
    // On an old map nobody makes bread or planks: those are waived, the
    // rest still asked for.
    final old = MagWorld(map: MagMap.generate(MagRules.defaultSeed));
    final town = old.settlements.firstWhere((t) => t.town!.level == 3);
    final asks = old.developmentAsks(town);
    expect(asks.keys, isNot(contains(MagCargo.planks)));
    expect(asks.keys, isNot(contains(MagCargo.stone)));
    expect(asks, isNotEmpty);
  });

  test('a development contract pays once per level, on real delivery', () {
    final w = motorStart()..money = 100000;
    final plant = w.map.startPlant, village = startVillage(w);
    final t = village.town!;
    // Everything but the food is already there; the food comes by truck.
    for (final e in w.developmentAsks(village).entries) {
      if (e.key != MagCargo.food) give(w, t.devStock, e.key, e.value);
    }
    give(w, plant.stock, MagCargo.food, 200);
    connect(w, plant, village);
    w.createRoute([plant.id, village.id]);
    w.assign(w.vehicles.values.single.id, w.routes.keys.single);
    final reward = w.developmentReward(village);
    for (var k = 0; k < 6000 && !t.devPaid; k++) {
      w.step();
    }
    expect(t.devPaid, isTrue);
    expect(t.devStock.values, isNot(contains(0)));
    final paid = w.journal.entries.where((e) => e.category == 'development');
    expect(paid.length, 1);
    expect(paid.single.amount, reward);
    expect(paid.single.kind, MagEntryKind.revenue);
    expect(paid.single.sourceId, village.id);
    expect(t.history.last.text, contains('Контракт развития'));
    // Saved and loaded: it does not pay again.
    final b = magWorldFromJson(
      jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
    );
    b.step(2000);
    expect(
      b.journal.entries.where((e) => e.category == 'development').length,
      1,
    );
    expectBalanced(w);
    // Growing opens the next level's contract.
    t
      ..population = MagTowns.of(3).population
      ..satisfaction.addAll(List.filled(6, 1.0));
    w.step(MagRules.ticksPerDay);
    expect(t.level, 3);
    expect(t.devPaid, isFalse);
    expect(w.developmentAsks(village).keys, contains(MagCargo.stone));
  });

  test('growth stock beyond what is asked goes to the market', () {
    final w = MagWorld.start();
    final village = startVillage(w);
    final t = village.town!;
    give(w, t.devStock, MagCargo.ore, 25); // not asked at all
    final asked = w.developmentAsks(village)[MagCargo.planks]!;
    give(w, t.devStock, MagCargo.planks, asked + 7); // 7 too many
    final before = w.destroyed[MagCargo.planks] ?? 0;
    w.step(MagRules.ticksPerDay);
    expect(t.devStock[MagCargo.ore], isNull);
    expect(t.devStock[MagCargo.planks], asked);
    expect(w.destroyed[MagCargo.planks]! - before, 7);
    expectBalanced(w);
  });

  test('contracts never ask for cargo nobody can make', () {
    for (final w in [
      MagWorld(map: MagMap.generate(MagRules.defaultSeed))..money = 100000,
      MagWorld.start()..money = 100000,
    ]) {
      for (var k = 0; k < 40; k++) {
        if (w.contracts.isEmpty) {
          w.replaceContract(-1); // fills the slots
        }
        final c = w.contracts.isEmpty ? null : w.contracts.first;
        if (c != null) {
          expect(w.cargoAvailable(c.cargo), isTrue, reason: '${c.cargo}');
          w.money += 150;
          w.replaceContract(c.id);
        } else {
          w.step(MagRules.ticksPerDay);
        }
      }
    }
  });

  test('a well supplied hamlet grows to a village in a sensible time', () {
    final w = MagWorld.start();
    final hamlet = w.settlements.firstWhere((t) => t.town!.level == 1);
    final t = hamlet.town!;
    for (final e in w.developmentAsks(hamlet).entries) {
      give(w, t.devStock, e.key, e.value);
    }
    var days = 0;
    while (t.level == 1 && days < 200) {
      // Keep the pantry full: the daily need is always met.
      for (final e in w.needsOf(hamlet).entries) {
        give(w, t.pantry, e.key, e.value);
      }
      w.step(MagRules.ticksPerDay);
      days++;
    }
    expect(t.level, 2);
    // Twenty to sixty people at full supply: about a month and a bit.
    expect(days, inInclusiveRange(25, 60));
    expect(t.cells.length, 2);
    expect(t.devPaid, isFalse); // the new level's contract is open
    expectBalanced(w);
  });
}
