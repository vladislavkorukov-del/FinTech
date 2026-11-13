import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage 2: smart warehouses and the technology tree. Building and rules,
/// storing without pay, refilling and sending on by writing orders, never
/// an endless stream of requests, technologies changing real numbers, and
/// saves of formats 1, 2 and 3.
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
    for (final i in w.map.industries) {
      for (final c in MagCargo.values) {
        expect(
          w.orders.reservedOut(i.id, c),
          lessThanOrEqualTo(i.stock[c] ?? 0),
        );
      }
    }
    for (final wh in w.warehouses) {
      var inbound = 0;
      for (final c in MagCargo.values) {
        inbound += w.orders.reservedIn(wh.id, c);
      }
      expect(w.storedIn(wh) + inbound, lessThanOrEqualTo(w.warehouseCapacity));
    }
  }

  /// Start line built, rich, level 10, the storage technologies learned.
  MagWorld world({List<String> techs = const ['storage', 'autosupply']}) {
    final w = MagWorld.start();
    final f = w.map.startFarm, p = w.map.startPlant;
    expect(
      w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt)),
      isNull,
    );
    w
      ..money = 500000
      ..xp = MagWorldProgress.xpFor(10)
      ..techs.addAll(techs);
    return w;
  }

  /// Builds a warehouse near [near] and joins it to [joinTo] by road.
  MagIndustry warehouseNear(MagWorld w, MagIndustry near, MagIndustry joinTo) {
    for (var r = 3; r < 12; r++) {
      for (final (dx, dy) in [
        (0, r),
        (r, 0),
        (0, -r),
        (-r, 0),
        (r, r),
        (-r, r),
      ]) {
        final x = near.x + dx, y = near.y + dy;
        if (w.warehouseBlocker(x, y) != null) continue;
        // A road from its top side to a stop cell of [joinTo].
        final stop = w.accessCells(joinTo).first;
        final plan = w.planRoad(x, y - 1, w.cx(stop), w.cy(stop), MagRoad.dirt);
        if (plan.error != null) continue;
        expect(w.buildWarehouse(x, y), isNull);
        expect(w.buildRoad(plan), isNull);
        final wh = w.warehouses.last;
        expect(w.connected(wh, joinTo), isTrue);
        return wh;
      }
    }
    fail('no room for a warehouse');
  }

  test('the technology tree is whole and sound', () {
    final ids = MagTechTree.all.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.length, greaterThanOrEqualTo(30));
    for (final b in MagBranch.values) {
      expect(MagTechTree.of(b).length, greaterThanOrEqualTo(6));
    }
    for (final t in MagTechTree.all) {
      expect(t.lore, isNotEmpty);
      expect(t.effect, isNotEmpty);
      expect(t.effects, isNotEmpty);
      for (final r in t.requires) {
        final before = MagTechTree.byId(r);
        expect(before, isNotNull, reason: '${t.id} needs $r');
        // A requirement never asks for a higher level: no dead ends.
        expect(before!.level, lessThanOrEqualTo(t.level));
      }
    }
    // No cycles: every node is reachable by learning in some order.
    final learned = <String>{};
    var progress = true;
    while (progress) {
      progress = false;
      for (final t in MagTechTree.all) {
        if (!learned.contains(t.id) && t.requires.every(learned.contains)) {
          learned.add(t.id);
          progress = true;
        }
      }
    }
    expect(learned.length, ids.length);
  });

  test('research: level, earlier nodes, deliveries, money; real effects', () {
    final w = MagWorld.start()..money = 1000000;
    final truck = w.vehicles.values.first;
    expect(w.research('turbo'), contains('уровень'));
    w.xp = MagWorldProgress.xpFor(30);
    expect(w.research('injector'), contains('Турбонаддув'));
    final speed = w.speedOf(truck), cap = w.capacityOf(truck);
    final money = w.money;
    expect(w.research('turbo'), isNull);
    expect(w.money, money - MagTechTree.byId('turbo')!.cost);
    expect(w.month.expense['research'], MagTechTree.byId('turbo')!.cost);
    expect(w.speedOf(truck), closeTo(speed * 1.05, 1e-9));
    expect(w.research('turbo'), contains('Уже'));
    expect(w.research('trailer'), contains('Наращённые'));
    w.research('sides');
    expect(w.research('trailer'), contains('доставок'));
    w.deliveries = 60;
    expect(w.research('trailer'), isNull);
    expect(w.capacityOf(truck), greaterThan(cap));
    // Roads get cheaper, payments grow.
    final f = w.map.startFarm, p = w.map.startPlant;
    final before = w
        .planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt)
        .cost;
    w.research('survey');
    final after = w
        .planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt)
        .cost;
    expect(after, lessThan(before));
    w.research('marketing');
    expect(w.factor(MagBonus.pay), closeTo(1.04, 1e-9));
    w.money = 0;
    expect(w.research('sales'), contains('кредит'));
  });

  test('warehouses: technology, slots, placement, price, removal', () {
    final w = world(techs: const []);
    final plant = w.map.startPlant;
    expect(w.warehouseBlocker(plant.x, plant.y + 4), contains('Складское'));
    w.techs.add('storage');
    expect(w.warehouseSlots, 1);
    // Not on a place, not on a road.
    expect(w.buildWarehouse(plant.x, plant.y), isNotNull);
    final wh = warehouseNear(w, plant, plant);
    expect(wh.kind, MagIndustryKind.warehouse);
    expect(wh.supplies, containsAll(MagCargo.values));
    expect(w.month.expense['warehouses'], MagRules.warehousePrice);
    // One slot only, until more technologies.
    expect(w.warehouseBlocker(2, 2), contains('технологии'));
    w.techs.add('racks');
    w.techs.add('network');
    expect(w.warehouseSlots, 2);
    expect(w.warehouseCapacity, MagRules.warehouseBase + 100);
    // An empty one comes down; one with cargo does not.
    wh.stock[MagCargo.grain] = 5;
    w.created[MagCargo.grain] = (w.created[MagCargo.grain] ?? 0) + 5;
    expect(w.removeWarehouse(wh.id), contains('вывезите'));
    wh.stock.clear();
    w.created[MagCargo.grain] = w.created[MagCargo.grain]! - 5;
    expect(w.removeWarehouse(wh.id), isNull);
    expect(w.warehouses, isEmpty);
  });

  test('a route through a warehouse: stored free, paid from there on', () {
    final w = world();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    final wh = warehouseNear(w, plant, plant);
    w.createRoute([farm.id, wh.id]);
    final truck = w.vehicles.values.first;
    w.assign(truck.id, w.routes.keys.first);
    for (var t = 0; t < 3000 && (wh.stock[MagCargo.grain] ?? 0) == 0; t++) {
      w.step();
      expectBalanced(w);
    }
    expect(wh.stock[MagCargo.grain], greaterThan(0));
    expect(w.month.income['delivery'], isNull); // internal transfer
    expect(w.deliveries, 0);
    // From the warehouse to the plant it pays, by the warehouse's distance.
    w.createRoute([wh.id, plant.id]);
    w.buyTruck('pickup');
    final second = w.vehicles.values.last;
    w.assign(second.id, w.routes.keys.last);
    for (var t = 0; t < 3000 && w.deliveries == 0; t++) {
      w.step();
      expectBalanced(w);
    }
    expect(w.deliveries, greaterThan(0));
    expect(w.month.income['delivery'], greaterThan(0));
  });

  test('a full warehouse takes only what fits from route trucks', () {
    final w = world();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    final wh = warehouseNear(w, plant, plant);
    expect(w.setRule(wh.id, MagCargo.grain, MagStockRule(max: 4)), isNull);
    w.createRoute([farm.id, wh.id]);
    final truck = w.vehicles.values.first;
    w.assign(truck.id, w.routes.keys.first);
    w.step(2500);
    expect(wh.stock[MagCargo.grain], 4);
    expect(truck.load, greaterThan(0)); // the rest stays on board
    expectBalanced(w);
  });

  test('rules: checked, and modes open with technologies', () {
    final w = world(techs: const ['storage']);
    final wh = warehouseNear(w, w.map.startPlant, w.map.startPlant);
    expect(
      w.setRule(
        wh.id,
        MagCargo.grain,
        MagStockRule(mode: MagStockMode.autoSupply),
      ),
      contains('технология'),
    );
    w.techs.add('autosupply');
    expect(
      w.setRule(
        wh.id,
        MagCargo.grain,
        MagStockRule(mode: MagStockMode.autoSupply, min: 30, target: 20),
      ),
      contains('минимум'),
    );
    expect(
      w.setRule(wh.id, MagCargo.grain, MagStockRule(max: 9999)),
      isNotNull,
    );
    expect(
      w.setRule(
        wh.id,
        MagCargo.grain,
        MagStockRule(mode: MagStockMode.distribute),
      ),
      contains('технология'),
    );
    expect(
      w.setRule(w.map.startFarm.id, MagCargo.grain, MagStockRule()),
      contains('не склад'),
    );
  });

  test('auto-refill writes the orders it needs, never endless ones', () {
    final w = world();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    final wh = warehouseNear(w, plant, farm);
    expect(
      w.setRule(
        wh.id,
        MagCargo.grain,
        MagStockRule(mode: MagStockMode.autoSupply, min: 20, target: 40),
      ),
      isNull,
    );
    w.step(MagRules.planEveryTicks);
    final mine = w.orders.active.where((o) => o.receiver == wh.id).toList();
    expect(mine, isNotEmpty);
    expect(mine.every((o) => o.supplier == farm.id), isTrue);
    expect(mine.every((o) => o.tag == 'wh:${wh.id}:grain'), isTrue);
    // Never more open than the limit, and never above the target in total.
    for (var t = 0; t < 400; t++) {
      w.step();
      final open = w.orders.active.where((o) => o.receiver == wh.id);
      expect(open.length, lessThanOrEqualTo(MagRules.autoOrdersPerRule));
      expect(w.projectedStock(wh, MagCargo.grain), lessThanOrEqualTo(40));
      expectBalanced(w);
    }
    // Nobody carries them yet; giving the free trucks out does.
    w.money = 500000;
    w.buyTruck('pickup');
    w.buyTruck('pickup');
    expect(w.assignFreeTrucks(), greaterThan(0));
    var created = 0;
    for (var t = 0; t < 12000; t++) {
      w.step();
      if (t % 200 == 0) w.assignFreeTrucks();
      created = w.orders.orders.length;
      expectBalanced(w);
    }
    final stock = wh.stock[MagCargo.grain] ?? 0;
    expect(stock, greaterThanOrEqualTo(20));
    expect(stock, lessThanOrEqualTo(40));
    // At the target nothing more is ordered.
    final done = w.orders.orders.where(
      (o) => o.status == MagOrderStatus.done && o.receiver == wh.id,
    );
    expect(done, isNotEmpty);
    expect(created, lessThan(80));
  });

  test('distribution sends extra on to users, never to warehouses', () {
    final w = world(
      techs: const [
        'storage',
        'autosupply',
        'distribution',
        'network',
        'racks',
      ],
    );
    final farm = w.map.startFarm, plant = w.map.startPlant;
    final hub = warehouseNear(w, plant, plant);
    hub.stock[MagCargo.grain] = 60;
    w.created[MagCargo.grain] = w.created[MagCargo.grain]! + 60;
    expect(
      w.setRule(
        hub.id,
        MagCargo.grain,
        MagStockRule(mode: MagStockMode.distribute, target: 15),
      ),
      isNull,
    );
    // A second warehouse pulls from the hub only what is above 15.
    final other = warehouseNear(w, farm, plant);
    expect(
      w.setRule(
        other.id,
        MagCargo.grain,
        MagStockRule(mode: MagStockMode.autoSupply, min: 10, target: 30),
      ),
      isNull,
    );
    w.step(MagRules.planEveryTicks);
    final fromHub = w.orders.active.where((o) => o.supplier == hub.id).toList();
    expect(fromHub, isNotEmpty);
    // The hub itself never sends to a warehouse.
    expect(
      fromHub
          .where((o) => o.tag == 'wh:${hub.id}:grain')
          .every((o) => !w.map.industry(o.receiver)!.spec.stores),
      isTrue,
    );
    // It keeps its target: orders take only what is above it.
    expect(
      w.orders.reservedOut(hub.id, MagCargo.grain),
      lessThanOrEqualTo(60 - 15),
    );
    expectBalanced(w);
  });

  test('saves: format 3 round trip; formats 1 and 2 migrate', () {
    final w = world();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    final wh = warehouseNear(w, plant, farm);
    w.setRule(
      wh.id,
      MagCargo.grain,
      MagStockRule(
        mode: MagStockMode.autoSupply,
        min: 10,
        target: 30,
        priority: 2,
      ),
    );
    w.step(MagRules.planEveryTicks);
    w.assignFreeTrucks();
    w.step(77);
    final saved = jsonEncode(w.toJson());
    final b = magWorldFromJson(jsonDecode(saved) as Map<String, dynamic>);
    expect(jsonEncode(b.toJson()), saved);
    expect(b.techs, containsAll(['storage', 'autosupply']));
    expect(b.warehouses.single.rules[MagCargo.grain]!.target, 30);
    w.step(3000);
    b.step(3000);
    expect(jsonEncode(b.toJson()), jsonEncode(w.toJson()));
    // A warehouse on a road is refused.
    final bad = jsonDecode(saved) as Map<String, dynamic>;
    final roads = base64Decode(bad['roads'] as String);
    roads[wh.y * 64 + wh.x] = 1;
    bad['roads'] = base64Encode(roads);
    expect(() => magWorldFromJson(bad), throwsFormatException);
    // Older formats come up to 3, keeping their orders.
    for (final f in ['v1', 'v2']) {
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/magistrali_save_$f.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final old = magWorldFromJson(raw);
      expect(old.techs, isEmpty);
      expect(old.warehouses, isEmpty);
      expect(old.money, raw['money']);
      if (f == 'v2') {
        expect(old.orders.orders.length, 2);
        expect(old.orders.orders.first.status, MagOrderStatus.inTransit);
      }
      old.step(1500);
      expect(old.toJson()['version'], 3);
      expectBalanced(old);
    }
  });
}
