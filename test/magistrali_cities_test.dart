import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Master plan stage 6: cities, levels 4–7. Industrial needs (only what
/// can be made), a specialization made by what the company brings, a
/// market paying more for its own cargo and for the demand of the week,
/// big city orders with a deadline that pay once, expire without a fine
/// and never disturb the regular contracts; saves.
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

  MagIndustry village(MagWorld w) =>
      w.settlements.firstWhere((i) => i.name == 'Луговое');

  test('cities need industrial goods — only what the world can make', () {
    final w = MagWorld.start();
    final v = village(w);
    v.town!.level = 4;
    expect(w.needsOf(v).keys, containsAll([MagCargo.bread, MagCargo.planks]));
    v.town!.level = 6;
    expect(w.needsOf(v).keys, containsAll([MagCargo.bricks, MagCargo.steel]));
    v.town!.level = 7;
    expect(w.needsOf(v).keys, contains(MagCargo.parts));
    // A map from before 1.72: its cities (level 6) ask for none of it.
    final old = MagWorld(map: MagMap.generate(MagRules.defaultSeed));
    final city = old.cities.first;
    expect(city.town!.level, 6);
    expect(old.needsOf(city).keys, isNot(contains(MagCargo.steel)));
    expect(old.needsOf(city).keys, isNot(contains(MagCargo.bricks)));
    expect(old.needsOf(city), isNotEmpty);
  });

  test('becoming a city: the specialization of what it was brought', () {
    final w = MagWorld.start();
    final v = village(w);
    final t = v.town!..level = 3;
    t.cells.clear();
    t.cells.add(MagSettlement.key(v.x, v.y));
    expect(w.isCity(v), isFalse);
    t.received.addAll({MagCargo.ore: 40, MagCargo.coal: 30, MagCargo.food: 50});
    expect(MagTowns.specializationFor(t.received), MagSpecialization.mining);
    for (final e in t.spec.development.entries) {
      if (w.cargoAvailable(e.key)) give(w, t.devStock, e.key, e.value);
    }
    t
      ..population = MagTowns.of(4).population
      ..satisfaction.addAll(List.filled(7, 1.0));
    w.step(MagRules.ticksPerDay);
    expect(t.level, 4);
    expect(w.isCity(v), isTrue);
    expect(t.specialization, MagSpecialization.mining);
    expect(
      t.history.map((e) => e.text),
      contains('Специализация: горняцкое город'),
    );
    // Its market now buys its own cargo.
    expect(v.accepts, containsAll([MagCargo.ore, MagCargo.coal]));
    // Nothing brought: a city keeps the specialization it had.
    expect(MagTowns.specializationFor(const {}), isNull);
  });

  test('a city pays more for its cargo and for the demand of the week', () {
    final w = MagWorld.start();
    final v = village(w);
    final t = v.town!
      ..level = 5
      ..specialization = MagSpecialization.industry;
    final base = 1 + t.spec.payBonus;
    final demand = w.weeklyDemand(v)!;
    expect(v.accepts, contains(demand));
    for (final c in [MagCargo.steel, MagCargo.food]) {
      var k = base;
      if (MagTowns.favoured(t.specialization).contains(c)) {
        k += MagTowns.favouredBonus;
      }
      if (c == demand) k += MagTowns.weeklyBonus;
      expect(w.marketFactor(v, c), closeTo(k, 1e-9), reason: '$c');
    }
    t.specialization = MagSpecialization.trade;
    expect(
      w.marketFactor(v, MagCargo.ore) - base,
      closeTo(
        MagTowns.tradeBonus + (w.weeklyDemand(v) == MagCargo.ore ? .3 : 0),
        1e-9,
      ),
    );
    // A village is not a city: only its market bonus.
    t.level = 2;
    expect(w.weeklyDemand(v), isNull);
    expect(w.marketFactor(v, MagCargo.food), 1 + t.spec.payBonus);
    // The demand is the same after a reload and changes with the weeks.
    t.level = 6;
    final seen = <MagCargo?>{};
    for (var week = 0; week < 8; week++) {
      final now = w.weeklyDemand(v);
      final b = magWorldFromJson(
        jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
      );
      expect(b.weeklyDemand(b.map.industry(v.id)!), now);
      seen.add(now);
      w.step(MagRules.ticksPerDay * MagTowns.daysPerWeek);
    }
    expect(seen.length, greaterThan(1));
  });

  test('city orders: one per city, bigger, apart from regular contracts', () {
    final w = MagWorld(map: MagMap.generate(MagRules.defaultSeed))
      ..money = 100000;
    w.replaceContract(-1); // fills the regular slots
    final regular = w.regularContracts.length;
    w.step(MagRules.ticksPerDay);
    final orders = w.cityOrders.toList();
    expect(orders.length, w.cities.length);
    expect(orders.map((o) => o.to).toSet().length, orders.length);
    expect(w.regularContracts.length, regular);
    for (final o in orders) {
      final city = w.map.industry(o.to)!;
      expect(city.accepts, contains(o.cargo));
      expect(w.cargoAvailable(o.cargo), isTrue);
      expect(o.amount, greaterThanOrEqualTo(50 + 25 * 2));
      expect(o.deadline! - w.tick, (20 + 4 * 2) * MagRules.ticksPerDay);
      expect(
        o.reward,
        greaterThan(o.amount * MagRules.cargoRate[o.cargo]! * 22),
      );
    }
    expect(
      w.replaceContract(orders.first.id),
      'Городской заказ заменить нельзя',
    );
    // Saved and loaded with their deadlines.
    final b = magWorldFromJson(
      jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
    );
    expect(
      b.cityOrders.map((o) => (o.id, o.deadline)).toList(),
      orders.map((o) => (o.id, o.deadline)).toList(),
    );
    // Past its deadline an order goes, with no fine; a new one comes
    // after the pause.
    final first = orders.first;
    final money = w.money;
    while (w.tick <= first.deadline!) {
      w.step(MagRules.ticksPerDay);
    }
    w.step(MagRules.ticksPerDay);
    expect(w.contracts.where((c) => c.id == first.id), isEmpty);
    final t = w.map.industry(first.to)!.town!;
    expect(
      t.history.map((e) => e.text),
      contains('Городской заказ не выполнен в срок'),
    );
    // No fine and no pay: nothing in the journal is about city orders.
    expect(
      w.journal.entries.where((e) => e.category.contains('city')),
      isEmpty,
    );
    expect(w.money, lessThanOrEqualTo(money + w.month.totalIncome));
    w.step(MagRules.ticksPerDay * (MagRules.cityOrderPause + 1));
    expect(w.cityOrders.where((c) => c.to == first.to), isNotEmpty);
    expectBalanced(w);
  });

  test('a city order paid once on real delivery', () {
    final w = motorStart()..money = 100000;
    final plant = w.map.startPlant, v = village(w);
    final t = v.town!..level = 4;
    give(w, plant.stock, MagCargo.food, 80);
    connect(w, plant, v);
    w.createRoute([plant.id, v.id]);
    w.assign(w.vehicles.values.single.id, w.routes.keys.single);
    t.orderAt = 1 << 40; // no order of its own: the test's one only
    final order = MagContract(
      id: w.nextId++,
      cargo: MagCargo.food,
      to: v.id,
      amount: 12,
      reward: 2000,
      xp: 200,
      deadline: w.tick + 40 * MagRules.ticksPerDay,
    );
    w.contracts.add(order);
    for (var k = 0; k < 8000 && w.contracts.contains(order); k++) {
      w.step();
    }
    expect(w.contracts, isNot(contains(order)));
    final paid = w.journal.entries.where((e) => e.category == 'city_orders');
    expect(paid.length, 1);
    expect(paid.single.kind, MagEntryKind.revenue);
    expect(paid.single.amount, (2000 * w.factor(MagBonus.contract)).round());
    expect(t.revenue, greaterThanOrEqualTo(paid.single.amount));
    expect(t.orderAt, greaterThan(w.tick - MagRules.ticksPerDay * 5));
    expect(t.received[MagCargo.food], greaterThan(0));
    w.step(MagRules.ticksPerDay * 3);
    expect(
      w.journal.entries.where((e) => e.category == 'city_orders').length,
      1,
    );
    // What it was brought survives a save.
    final b = magWorldFromJson(
      jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
    );
    final tb = b.map.industry(v.id)!.town!;
    expect(tb.received, t.received);
    expect(tb.orderAt, t.orderAt);
    expectBalanced(w);
  });
}
