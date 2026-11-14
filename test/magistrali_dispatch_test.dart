import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage 3: the automatic dispatcher. Only fleet trucks, the score of each
/// mode, urgency, capacity, road reach, a fully automatic warehouse, and
/// saves of every earlier format.
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

  /// Start line built, rich, level 10, dispatcher learned.
  MagWorld world() {
    final w = motorStart();
    final f = w.map.startFarm, p = w.map.startPlant;
    expect(
      w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt)),
      isNull,
    );
    w
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(10)
      ..techs.addAll(['storage', 'autosupply', 'dispatch']);
    return w;
  }

  MagOrder order(MagWorld w, {int amount = 8, int priority = 1}) {
    expect(
      w.createOrder(
        cargo: MagCargo.grain,
        from: w.map.startFarm.id,
        to: w.map.startPlant.id,
        amount: amount,
        priority: priority,
      ),
      isNull,
    );
    return w.orders.orders.last;
  }

  /// More grain at the farm (recorded in the ledger).
  void grain(MagWorld w, int n) {
    final f = w.map.startFarm;
    f.stock[MagCargo.grain] = (f.stock[MagCargo.grain] ?? 0) + n;
    w.created[MagCargo.grain] = (w.created[MagCargo.grain] ?? 0) + n;
  }

  test('only the automatic fleet is dispatched, and only once learned', () {
    final w = world()..techs.remove('dispatch');
    final manual = w.vehicles.values.first;
    expect(w.setAuto(manual.id, true), contains('Диспетчерская'));
    w.techs.add('dispatch');
    final o = order(w);
    w.step(MagDispatch.everyTicks * 3);
    expect(o.status, MagOrderStatus.pending); // the manual truck stays put
    expect(manual.orderId, isNull);
    w.buyTruck('pickup');
    final fleet = w.vehicles.values.last;
    expect(w.setAuto(fleet.id, true), isNull);
    w.step(MagDispatch.everyTicks);
    expect(o.vehicle, fleet.id);
    expect(w.dispatchLog.single.order, o.id);
    expect(w.dispatchLog.single.reason, contains('кл.'));
    expect(manual.orderId, isNull);
  });

  test('a truck on a route joins the fleet by leaving its route', () {
    final w = world();
    w.createRoute([w.map.startFarm.id, w.map.startPlant.id]);
    final t = w.vehicles.values.first;
    w.assign(t.id, w.routes.keys.first);
    w.step(50);
    expect(w.setAuto(t.id, true), isNull);
    expect(t.routeId, isNull);
    expect(t.auto, isTrue);
    expectBalanced(w);
  });

  test('economy takes the cheap truck, fast takes the quick one', () {
    MagVehicle pick(MagDispatchMode mode) {
      final w = world()..dispatchMode = mode;
      grain(w, 40);
      w.vehicles.clear();
      w.buyTruck('pickup');
      w.buyTruck('tractor');
      for (final v in w.vehicles.values) {
        w.setAuto(v.id, true);
      }
      final o = order(w, amount: 8);
      w.dispatch();
      return w.vehicles[o.vehicle]!;
    }

    expect(pick(MagDispatchMode.economy).model, 'pickup');
    expect(pick(MagDispatchMode.fast).model, 'tractor');
  });

  test('the nearest free truck goes; urgent orders are served first', () {
    final w = world();
    grain(w, 40);
    w.vehicles.clear();
    w.buyTruck('pickup');
    w.buyTruck('pickup');
    final near = w.vehicles.values.first, far = w.vehicles.values.last;
    final f = w.map.startFarm, p = w.map.startPlant;
    // One stands at the farm, the other at the plant.
    near
      ..cell = w.accessCells(f).first
      ..state = MagVehicleState.idle;
    far
      ..cell = w.accessCells(p).first
      ..state = MagVehicleState.idle;
    w.setAuto(near.id, true);
    w.setAuto(far.id, true);
    w.dispatchMode = MagDispatchMode.balanced;
    final o = order(w);
    w.dispatch();
    expect(o.vehicle, near.id);
    // Two orders, one truck: the urgent one first.
    w.cancelOrder(o.id);
    w.setAuto(far.id, false);
    final low = order(w, priority: 0);
    final high = order(w, priority: 2);
    w.dispatch();
    expect(high.vehicle, near.id);
    expect(low.status, MagOrderStatus.pending);
  });

  test('capacity and road reach are respected', () {
    final w = world();
    grain(w, 60);
    w.vehicles.clear();
    w.buyTruck('pickup');
    final small = w.vehicles.values.single;
    w.setAuto(small.id, true);
    final big = order(w, amount: 30);
    w.dispatch();
    expect(big.status, MagOrderStatus.pending); // too much for a pickup
    w.cancelOrder(big.id);
    // A truck on a road island far away cannot reach the farm.
    final island = w.planRoad(2, 60, 6, 60, MagRoad.dirt);
    if (island.error == null) {
      w.buildRoad(island);
      small
        ..cell = island.cells.first
        ..state = MagVehicleState.idle;
      final o = order(w);
      w.dispatch();
      expect(o.status, MagOrderStatus.pending);
      expect(small.orderId, isNull);
    }
  });

  test('a warehouse and the fleet run on their own', () {
    final w = world();
    final f = w.map.startFarm, p = w.map.startPlant;
    late int wx, wy;
    search:
    for (var r = 2; r < 10; r++) {
      for (var dx = -r; dx <= r; dx++) {
        final x = p.x + dx, y = p.y + r;
        if (w.warehouseBlocker(x, y) == null &&
            w.planRoad(x, y - 1, p.x, p.y + p.size, MagRoad.dirt).error ==
                null) {
          wx = x;
          wy = y;
          break search;
        }
      }
    }
    expect(w.buildWarehouse(wx, wy), isNull);
    w.buildRoad(w.planRoad(wx, wy - 1, p.x, p.y + p.size, MagRoad.dirt));
    final wh = w.warehouses.single;
    expect(w.connected(f, wh), isTrue);
    w.setRule(
      wh.id,
      MagCargo.grain,
      MagStockRule(mode: MagStockMode.autoSupply, min: 20, target: 40),
    );
    w.buyTruck('pickup');
    for (final v in w.vehicles.values) {
      w.setAuto(v.id, true);
    }
    // No player action from here on.
    for (var t = 0; t < 10000; t++) {
      w.step();
      if (t % 100 == 0) expectBalanced(w);
    }
    final stock = wh.stock[MagCargo.grain] ?? 0;
    expect(stock, greaterThanOrEqualTo(20));
    expect(stock, lessThanOrEqualTo(40));
    expect(w.dispatchLog, isNotEmpty);
    expect(
      w.orders.orders.where(
        (o) => o.status == MagOrderStatus.done && o.receiver == wh.id,
      ),
      isNotEmpty,
    );
  });

  test('saves: format 4 round trip; formats 1–3 come up manual', () {
    final w = world()..dispatchMode = MagDispatchMode.fast;
    grain(w, 30);
    w.buyTruck('pickup');
    w.setAuto(w.vehicles.values.last.id, true);
    order(w);
    w.step(123);
    final saved = jsonEncode(w.toJson());
    final b = magWorldFromJson(jsonDecode(saved) as Map<String, dynamic>);
    expect(jsonEncode(b.toJson()), saved);
    expect(b.dispatchMode, MagDispatchMode.fast);
    expect(b.autoFleet.length, 1);
    w.step(2000);
    b.step(2000);
    expect(jsonEncode(b.toJson()), jsonEncode(w.toJson()));
    for (final f in ['v1', 'v2', 'v3']) {
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/magistrali_save_$f.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final old = magWorldFromJson(raw);
      expect(old.autoFleet, isEmpty, reason: f);
      expect(old.dispatchMode, MagDispatchMode.balanced);
      expect(old.money, raw['money']);
      old.step(1200);
      expect(old.toJson()['version'], MagWorldSave.version);
      expectBalanced(old);
    }
  });
}
