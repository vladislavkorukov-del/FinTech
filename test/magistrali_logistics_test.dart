import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage S7, smart logistics: logistics centres (LOG-08, LOG-09) that
/// supply the company's plants (LOG-11) and the settlements around them
/// (LOG-12) through ordinary reserved orders carried by the automatic
/// fleet; line statistics (ROUTE-11, FIN-04, ROUTE-14); problems and
/// advice from real figures (LOG-18, FIN-11, FIN-12); saves.
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

  /// A rich company that may build a centre and has a fleet.
  MagWorld ready() {
    final w = MagWorld.start()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(8)
      ..techs.addAll(['combustion', 'storage', 'autosupply', 'dispatch'])
      ..techs.add('logcenter');
    return w;
  }

  MagIndustry buildCenter(MagWorld w, MagIndustry near) {
    for (var r = 3; r < 20; r++) {
      for (var d = -r; d <= r; d++) {
        for (final (x, y) in [
          (near.x + d, near.y + r),
          (near.x + r, near.y + d),
          (near.x + d, near.y - r),
          (near.x - r, near.y + d),
        ]) {
          if (w.buildBlocker(MagIndustryKind.logisticsCenter, x, y) == null) {
            expect(
              w.buildIndustry(MagIndustryKind.logisticsCenter, x, y),
              isNull,
            );
            return w.map.industries.last;
          }
        }
      }
    }
    fail('no room for a centre');
  }

  MagIndustry village(MagWorld w) =>
      w.settlements.firstWhere((i) => i.name == 'Луговое');

  test('a centre: technology, level, how many, why it waits', () {
    final w = MagWorld.start()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(8);
    final p = w.map.startPlant;
    expect(
      w.buildBlocker(MagIndustryKind.logisticsCenter, p.x + 5, p.y + 5),
      'Нужна технология «Логистический центр»',
    );
    w.techs.add('logcenter');
    w.xp = MagWorldProgress.xpFor(5);
    expect(
      w.buildBlocker(MagIndustryKind.logisticsCenter, p.x + 5, p.y + 5),
      contains('6 уровня'),
    );
    w.xp = MagWorldProgress.xpFor(8);
    final c = buildCenter(w, p);
    expect(c.owned && c.built, isTrue);
    expect(w.centers.single, c);
    buildCenter(w, village(w));
    expect(w.centers.length, w.centerSlots);
    var refused = false;
    for (var y = 3; y < w.size - 3 && !refused; y++) {
      for (var x = 3; x < w.size - 3 && !refused; x++) {
        final why = w.buildBlocker(MagIndustryKind.logisticsCenter, x, y);
        if (why == 'Больше центров не разрешено') refused = true;
      }
    }
    expect(refused, isTrue);
    expect(w.centerIdle(c), 'Нужна технология «Диспетчерская»');
    w.techs.add('dispatch');
    expect(w.centerIdle(c), contains('автопарке'));
    w.setAuto(w.vehicles.values.single.id, true);
    expect(w.centerIdle(c), isNull);
    // A bigger centre reaches further and keeps more orders open.
    final r1 = w.centerRadius(c), o1 = w.centerOrderCap(c);
    expect(w.upgradeIndustry(c.id), isNull);
    expect(w.centerRadius(c), r1 + MagRules.centerRadiusStep);
    expect(w.centerOrderCap(c), o1 + MagRules.centerOrdersStep);
  });

  test('a centre keeps an own plant in input and a village in food', () {
    final w = ready();
    final farm = w.map.startFarm, plant = w.map.startPlant, v = village(w);
    expect(w.buyIndustry(plant.id), isNull);
    connect(w, farm, plant);
    connect(w, plant, v);
    w.buyTruck('pickup');
    w.buyTruck('pickup');
    for (final t in w.vehicles.values) {
      expect(w.setAuto(t.id, true), isNull);
    }
    final c = buildCenter(w, plant);
    // A level-3 centre reaches the village too.
    while (c.level < 3) {
      expect(w.upgradeIndustry(c.id), isNull);
    }
    expect(w.centerArea(c), containsAll([plant, v]));
    // Before anything arrives: the plant and the village are short.
    expect(w.shortages(plant).keys, contains(MagCargo.grain));
    expect(w.shortages(v).keys, contains(MagCargo.food));
    final money = w.money;
    var sawOrders = false;
    for (var k = 0; k < 40 * 25; k++) {
      w.step();
      final open = w.centerOrders(c);
      if (open.isNotEmpty) sawOrders = true;
      expect(open.length, lessThanOrEqualTo(w.centerOrderCap(c)));
      // Never two orders for the same place and cargo.
      final keys = open.map((o) => (o.receiver, o.cargo)).toList();
      expect(keys.toSet().length, keys.length);
    }
    expect(sawOrders, isTrue);
    expect(c.ordersMade, greaterThan(1));
    final done = w.orders.orders.where(
      (o) => o.tag == 'lc:${c.id}' && o.status == MagOrderStatus.done,
    );
    expect(done.map((o) => o.receiver), contains(plant.id));
    expect(
      done.where((o) => o.receiver == v.id).map((o) => o.cargo),
      contains(MagCargo.food),
    );
    expect(w.money, isNot(money)); // trading and costs happened
    expectBalanced(w);
    // Saved and loaded: the centre and its settings.
    expect(w.setCenterSupply(c.id, towns: false), isNull);
    final b = magWorldFromJson(
      jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
    );
    final cb = b.map.industry(c.id)!;
    expect(cb.kind, MagIndustryKind.logisticsCenter);
    expect(
      (cb.supplyPlants, cb.supplyTowns, cb.ordersMade),
      (true, false, c.ordersMade),
    );
    expect(b.centerArea(cb), isNot(contains(b.map.industry(v.id))));
  });

  test('a centre without a fleet writes nothing and locks no stock', () {
    final w = ready();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    w.buyIndustry(plant.id);
    connect(w, farm, plant);
    final c = buildCenter(w, plant);
    give(w, farm.stock, MagCargo.grain, 40);
    w.step(MagRules.ticksPerDay * 3);
    expect(w.centerOrders(c), isEmpty);
    expect(w.orders.reservedOut(farm.id, MagCargo.grain), 0);
    expect(w.advice.map((a) => a.kind), contains(MagAdviceKind.centerIdle));
  });

  test('line statistics: costs, profit and empty running', () {
    final w = ready();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    connect(w, farm, plant);
    w.createRoute([farm.id, plant.id]);
    final r = w.routes.values.single;
    w.assign(w.vehicles.values.single.id, r.id);
    w.step(MagRules.ticksPerDay * 20);
    final cart = w.vehicles.values.single;
    expect(r.costs, greaterThan(0));
    expect(r.costs, lessThanOrEqualTo(cart.costs));
    expect(r.cells, greaterThan(0));
    expect(r.emptyShare!, inInclusiveRange(.2, .8)); // back empty
    expect(r.profit, r.income - r.costs);
    final b = magWorldFromJson(
      jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
    );
    final rb = b.routes.values.single;
    expect(
      (rb.costs, rb.cells, rb.emptyCells),
      (r.costs, r.cells, r.emptyCells),
    );
  });

  test('advice from real figures, and the places it marks', () {
    final w = ready();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    // An idle cart.
    expect(
      w.advice.where((a) => a.kind == MagAdviceKind.idleVehicle).single.vehicle,
      w.vehicles.keys.single,
    );
    // An own plant with no grain, bought long ago.
    w.buyIndustry(plant.id);
    w.step(MagRules.ticksPerDay * 12);
    final kinds = w.advice.map((a) => a.kind).toSet();
    expect(kinds, contains(MagAdviceKind.noInput));
    expect(kinds, contains(MagAdviceKind.lossBusiness));
    final loss = w.advice.firstWhere(
      (a) => a.kind == MagAdviceKind.lossBusiness,
    );
    expect(loss.detail, contains('нет сырья'));
    expect(w.problemPlaces, contains(plant.id));
    // A full store on a line.
    connect(w, farm, plant);
    w.createRoute([farm.id, plant.id]);
    give(w, farm.stock, MagCargo.grain, w.outputCapOf(farm));
    expect(w.advice.map((a) => a.kind), contains(MagAdviceKind.stockFull));
    // A losing line.
    final r = w.routes.values.single..costs = 5000;
    expect(
      w.advice.where((a) => a.kind == MagAdviceKind.lossRoute).single.route,
      r.id,
    );
    // Losses come before chances.
    final weights = w.advice.map((a) => a.weight).toList();
    expect(weights, orderedEquals([...weights]..sort((a, b) => b - a)));
  });

  test('a city demand worth serving is advised, never marked as a problem', () {
    final w = ready();
    final v = village(w);
    v.town!.level = 5;
    final demand = w.weeklyDemand(v)!;
    final source = w.map.industries.firstWhere(
      (s) => s.town == null && !s.spec.stores && s.supplies.contains(demand),
    );
    give(w, source.stock, demand, 30);
    connect(w, source, v);
    final a = w.advice.where((a) => a.kind == MagAdviceKind.cityDemand);
    expect(a.map((e) => e.place), contains(v.id));
    expect(w.problemPlaces, isNot(contains(v.id)));
  });

  test('older saves load: no centres, lines start at zero', () {
    final w = magWorldFromJson(
      jsonDecode(
            File(
              'test/fixtures/magistrali_save_v5_map2.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    expect(w.centers, isEmpty);
    for (final r in w.routes.values) {
      expect((r.costs, r.cells), (0, 0));
    }
    w.step(MagRules.ticksPerDay * 2);
    expectBalanced(w);
  });
}
