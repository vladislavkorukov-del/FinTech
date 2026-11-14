import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:finora/services/magistrali_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage 1 of automation: logistics orders. Reservations, the rules that
/// guard them, the full life of an order on real roads, cancelling,
/// failing, living beside route trucks, and saves old and new.
void main() {
  /// The start line built; the starting pickup still in the garage.
  MagWorld world() {
    final w = motorStart();
    final f = w.map.startFarm, p = w.map.startPlant;
    expect(
      w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt)),
      isNull,
    );
    w.money = 100000;
    return w;
  }

  void expectBalanced(MagWorld w) {
    final total = w.totalCargo();
    for (final c in MagCargo.values) {
      expect(
        total[c] ?? 0,
        (w.created[c] ?? 0) - (w.destroyed[c] ?? 0),
        reason: '$c at tick ${w.tick}',
      );
    }
    // Orders never hold more than the stock.
    for (final i in w.map.industries) {
      for (final c in MagCargo.values) {
        expect(
          w.orders.reservedOut(i.id, c),
          lessThanOrEqualTo(i.stock[c] ?? 0),
        );
      }
    }
  }

  MagOrder order(MagWorld w, {int amount = 8, int priority = 1, String? tag}) {
    final err = w.createOrder(
      cargo: MagCargo.grain,
      from: w.map.startFarm.id,
      to: w.map.startPlant.id,
      amount: amount,
      priority: priority,
      tag: tag,
    );
    expect(err, isNull);
    return w.orders.orders.last;
  }

  test('creating reserves cargo and room; the rules refuse bad orders', () {
    final w = world();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    final stock = farm.stock[MagCargo.grain]!;
    final o = order(w, amount: 5);
    expect(o.status, MagOrderStatus.pending);
    expect(o.reserved, 5);
    expect(o.createdTick, w.tick);
    expect(w.availableOf(farm, MagCargo.grain), stock - 5);
    expect(farm.stock[MagCargo.grain], stock); // nothing moved yet
    expect(w.roomOf(plant, MagCargo.grain), MagRules.inputCap - 5);
    // No more than the supplier has free.
    expect(
      w.createOrder(
        cargo: MagCargo.grain,
        from: farm.id,
        to: plant.id,
        amount: stock - 4,
      ),
      contains('свободно'),
    );
    // Wrong cargo, wrong receiver, same place, bad amount and priority.
    expect(
      w.createOrder(
        cargo: MagCargo.wood,
        from: farm.id,
        to: plant.id,
        amount: 1,
      ),
      contains('не отгружает'),
    );
    final village = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.village,
    );
    final factory = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.factory,
    );
    expect(
      w.createOrder(
        cargo: MagCargo.grain,
        from: farm.id,
        to: factory.id,
        amount: 1,
      ),
      contains('не принимает'),
    );
    expect(
      w.createOrder(
        cargo: MagCargo.grain,
        from: farm.id,
        to: farm.id,
        amount: 1,
      ),
      isNotNull,
    );
    expect(
      w.createOrder(
        cargo: MagCargo.grain,
        from: farm.id,
        to: plant.id,
        amount: 0,
      ),
      isNotNull,
    );
    expect(
      w.createOrder(
        cargo: MagCargo.grain,
        from: farm.id,
        to: plant.id,
        amount: 1,
        priority: 5,
      ),
      isNotNull,
    );
    // A full receiver takes no more.
    plant.input[MagCargo.grain] = MagRules.inputCap - 5;
    w.created[MagCargo.grain] =
        w.created[MagCargo.grain]! + MagRules.inputCap - 5;
    expect(w.roomOf(plant, MagCargo.grain), 0);
    expect(
      w.createOrder(
        cargo: MagCargo.grain,
        from: farm.id,
        to: plant.id,
        amount: 1,
      ),
      contains('места'),
    );
    plant.input.clear();
    w.created[MagCargo.grain] =
        w.created[MagCargo.grain]! - MagRules.inputCap + 5;
    // Towns use up what they get: they never fill.
    farm.stock[MagCargo.grain] = stock;
    expect(w.roomOf(village, MagCargo.food), greaterThan(1 << 20));
    // The same rule cannot order the same thing twice at once.
    order(w, amount: 1, tag: 'auto');
    expect(
      w.createOrder(
        cargo: MagCargo.grain,
        from: farm.id,
        to: plant.id,
        amount: 1,
        tag: 'auto',
      ),
      contains('уже есть'),
    );
    expectBalanced(w);
  });

  test('a truck takes one order at a time, if it is free and big enough', () {
    final w = world();
    final truck = w.vehicles.values.first;
    final a = order(w, amount: 4), b = order(w, amount: 4);
    expect(w.assignOrder(a.id, truck.id), isNull);
    expect(a.status, MagOrderStatus.assigned);
    expect(a.vehicle, truck.id);
    expect(truck.orderId, a.id);
    expect(w.assignOrder(b.id, truck.id), contains('занят'));
    expect(w.assignOrder(a.id, truck.id), contains('в работе'));
    // A truck on a route is not free.
    w.createRoute([w.map.startFarm.id, w.map.startPlant.id]);
    w.buyTruck('pickup');
    final routed = w.vehicles.values.last;
    w.assign(routed.id, w.routes.keys.first);
    expect(w.assignOrder(b.id, routed.id), contains('занят'));
    // Too much for a pickup.
    w.buyTruck('pickup');
    final small = w.vehicles.values.last;
    // Give the farm enough grain (recorded in the ledger).
    final farm = w.map.startFarm;
    farm.stock[MagCargo.grain] = farm.stock[MagCargo.grain]! + 30;
    w.created[MagCargo.grain] = w.created[MagCargo.grain]! + 30;
    final big = order(w, amount: 20);
    expect(w.assignOrder(big.id, small.id), contains('возьмёт только'));
  });

  test('the full life of an order on real roads, paid only on delivery', () {
    final w = world();
    final truck = w.vehicles.values.first;
    final farm = w.map.startFarm, plant = w.map.startPlant;
    // First order: the truck starts from the garage at the farm.
    final first = order(w, amount: 8);
    w.assignOrder(first.id, truck.id);
    final seen = <MagOrderStatus>[];
    for (var t = 0; t < 3000 && first.status.active; t++) {
      w.step();
      if (seen.isEmpty || seen.last != first.status) seen.add(first.status);
      expectBalanced(w);
      if (truck.onMap) expect(w.roads[truck.cell], isNot(0));
      if (first.status.index < MagOrderStatus.unloading.index) {
        expect(w.month.income['delivery'], isNull, reason: 'paid early');
      }
      if (first.status == MagOrderStatus.inTransit) {
        expect(truck.load, 8);
        expect(truck.cargo, MagCargo.grain);
        expect(w.orders.reservedOut(farm.id, MagCargo.grain), 0);
        expect(w.orders.reservedIn(plant.id, MagCargo.grain), 8);
      }
    }
    expect(seen, [
      MagOrderStatus.loading,
      MagOrderStatus.inTransit,
      MagOrderStatus.unloading,
      MagOrderStatus.done,
    ]);
    expect(first.income, greaterThan(0));
    expect(w.month.income['delivery'], first.income);
    expect(plant.input[MagCargo.grain], 8);
    expect(w.orders.reservedIn(plant.id, MagCargo.grain), 0);
    expect(truck.state, MagVehicleState.idle);
    expect(truck.orderId, isNull);
    expect(truck.onMap, isTrue);
    expect(w.deliveries, 1);
    // Second order: the idle truck at the plant drives to the farm first.
    w.step(MagRules.ticksPerDay); // the farm makes more
    final second = order(w, amount: 8, priority: 2);
    expect(w.assignOrder(second.id, truck.id), isNull);
    seen.clear();
    for (var t = 0; t < 4000 && second.status.active; t++) {
      w.step();
      if (seen.isEmpty || seen.last != second.status) seen.add(second.status);
      expectBalanced(w);
    }
    expect(seen.first, MagOrderStatus.toPickup);
    expect(seen.last, MagOrderStatus.done);
    expect(w.deliveries, 2);
  });

  test('route trucks never take cargo that an order holds', () {
    final w = world();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    final all = w.availableOf(farm, MagCargo.grain);
    order(w, amount: all);
    w.createRoute([farm.id, plant.id]);
    final truck = w.vehicles.values.first;
    w.assign(truck.id, w.routes.keys.first);
    // Before the farm makes more, the route truck loads nothing.
    for (var t = 0; t < MagRules.ticksPerDay - 2; t++) {
      w.step();
      expect(truck.load, 0);
      expect(farm.stock[MagCargo.grain], all);
    }
    // New grain is free to take.
    w.step(30);
    expect(truck.load, greaterThan(0));
    expect(w.orders.reservedOut(farm.id, MagCargo.grain), all);
    expect(farm.stock[MagCargo.grain], greaterThanOrEqualTo(all));
    expectBalanced(w);
  });

  test('cancelling releases everything; cargo on board goes back', () {
    final w = world();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    final truck = w.vehicles.values.first;
    // Before pickup.
    final a = order(w, amount: 6);
    final free = w.availableOf(farm, MagCargo.grain);
    expect(w.cancelOrder(a.id), isNull);
    expect(a.status, MagOrderStatus.cancelled);
    expect(w.availableOf(farm, MagCargo.grain), free + 6);
    expect(w.roomOf(plant, MagCargo.grain), MagRules.inputCap);
    expect(w.cancelOrder(a.id), contains('закрыта'));
    // On the way: the load returns to the farm, the truck stops.
    final b = order(w, amount: 6);
    w.assignOrder(b.id, truck.id);
    while (b.status != MagOrderStatus.inTransit) {
      w.step();
    }
    w.step(5);
    final stock = farm.stock[MagCargo.grain]!;
    expect(w.cancelOrder(b.id), isNull);
    expect(farm.stock[MagCargo.grain], stock + 6);
    expect(truck.load, 0);
    expect(truck.state, MagVehicleState.idle);
    expect(w.orders.reservedIn(plant.id, MagCargo.grain), 0);
    expect(w.month.income['delivery'], isNull);
    expectBalanced(w);
    // Selling a truck in the middle of an order cancels it the same way.
    final c = order(w, amount: 6);
    w.assignOrder(c.id, truck.id);
    while (c.status != MagOrderStatus.inTransit) {
      w.step();
    }
    expect(w.sellTruck(truck.id), isNull);
    expect(c.status, MagOrderStatus.cancelled);
    expectBalanced(w);
  });

  test('without a road an order fails after a while and frees its hold', () {
    final w = motorStart()..money = 100000;
    final truck = w.vehicles.values.first;
    final o = order(w, amount: 5);
    w.assignOrder(o.id, truck.id);
    w.step(MagRules.orderNoRoadDays * MagRules.ticksPerDay + 60);
    expect(o.status, MagOrderStatus.failed);
    expect(o.error, 'Нет дороги');
    expect(o.reserved, 0);
    expect(truck.orderId, isNull);
    expect(truck.state, MagVehicleState.garage);
    expectBalanced(w);
  });

  test('saved in the middle of an order, it goes on exactly the same', () {
    final a = world();
    final truck = a.vehicles.values.first;
    final o = order(a, amount: 8);
    a.assignOrder(o.id, truck.id);
    a.step(97);
    expect(o.status.active, isTrue);
    final saved = jsonEncode(a.toJson());
    final b = magWorldFromJson(jsonDecode(saved) as Map<String, dynamic>);
    expect(jsonEncode(b.toJson()), saved);
    a.step(2000);
    b.step(2000);
    expect(jsonEncode(b.toJson()), jsonEncode(a.toJson()));
    expect(b.orders.orders.first.status, MagOrderStatus.done);
    // A truck pointing at a missing order is refused.
    final bad = jsonDecode(saved) as Map<String, dynamic>;
    (bad['orders'] as List).clear();
    expect(() => magWorldFromJson(bad), throwsFormatException);
    // An order holding more than the stock is refused.
    final greedy = jsonDecode(saved) as Map<String, dynamic>;
    (greedy['orders'] as List).add({
      'id': 9999,
      'cargo': 'grain',
      'amount': 5000,
      'from': a.map.startFarm.id,
      'to': a.map.startPlant.id,
      'status': 'pending',
    });
    greedy['nextId'] = 10000;
    expect(() => magWorldFromJson(greedy), throwsFormatException);
  });

  test('a 1.68.0 save (format 1) loads with everything kept', () {
    final raw =
        jsonDecode(
              File('test/fixtures/magistrali_save_v1.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(raw['version'], 1);
    final w = magWorldFromJson(raw);
    expect(w.money, raw['money']);
    expect(w.xp, raw['xp']);
    expect(w.tick, raw['tick']);
    expect(w.vehicles.length, (raw['vehicles'] as List).length);
    expect(w.routes.length, 1);
    expect(w.vehicles.values.first.level(MagUpgrade.engine), 1);
    expect(base64Encode(w.roads), raw['roads']);
    expect(w.orders.orders, isEmpty);
    // Old trucks stay on their routes, under manual control.
    expect(w.vehicles.values.every((v) => v.orderId == null), isTrue);
    expect(w.vehicles.values.where((v) => v.routeId != null), isNotEmpty);
    final deliveries = w.deliveries;
    w.step(2500);
    expect(w.deliveries, greaterThan(deliveries));
    expect(w.toJson()['version'], MagWorldSave.version);
    // Unknown future formats are refused, not guessed.
    expect(
      () => magWorldFromJson({...raw, 'version': 99}),
      throwsFormatException,
    );
  });

  test(
    'the store keeps the old file before the new format replaces it',
    () async {
      final dir = await Directory.systemTemp.createTemp('mag-store-');
      try {
        final store = MagistraliStore(root: dir);
        final file = File('${dir.path}/magistrali/world.json');
        await file.parent.create(recursive: true);
        final old = File(
          'test/fixtures/magistrali_save_v1.json',
        ).readAsStringSync();
        await file.writeAsString(old);
        final w = (await store.load())!;
        final keep = File('${dir.path}/magistrali/world.v1.json');
        expect(keep.readAsStringSync(), old);
        await store.save(w);
        final now = jsonDecode(file.readAsStringSync()) as Map;
        expect(now['version'], MagWorldSave.version);
        expect(keep.readAsStringSync(), old); // untouched
        expect((await store.load())!.money, w.money);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
