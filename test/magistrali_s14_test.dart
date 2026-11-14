import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S14 (1.86): copying lines (ROUTE-12), cargo priorities
/// (ROUTE-09), the investment planner (FIN-14); saves.
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

  test('a line is copied as it is, or the other way round', () {
    final w = line();
    final f = w.map.startFarm, p = w.map.startPlant;
    final v = w.settlements.first;
    w.createRoute([f.id, p.id, v.id]);
    final r = w.routes.values.last;
    w.setStopOrder(r.id, 0, pick: MagCargo.grain);
    w.setStopOrder(r.id, 2, noDrop: true);
    w.setPriority(r.id, [MagCargo.food]);
    expect(w.copyRoute(r.id), isNull);
    final c = w.routes.values.last;
    expect(c.stops, r.stops);
    expect(c.pickAt, {0: MagCargo.grain});
    expect(c.noDrop, {2});
    expect(c.priority, [MagCargo.food]);
    expect(c.name, contains('копия'));
    expect(w.copyRoute(r.id, reverse: true), isNull);
    final b = w.routes.values.last;
    expect(b.stops, r.stops.reversed.toList());
    expect(b.pickAt, {2: MagCargo.grain});
    expect(b.noDrop, {0});
    expect(w.copyRoute(999999), isNotNull);
    // Kept in the save, with the day it was made.
    final l = reload(w);
    expect(l.routes[b.id]!.pickAt, {2: MagCargo.grain});
    expect(l.routes[r.id]!.priority, [MagCargo.food]);
    expect(l.routes[r.id]!.since, r.since);
  });

  test('priority: a vehicle takes the priority cargo first', () {
    final w = line();
    final f = w.map.startFarm;
    final wh = w.map.industries.first;
    expect(wh, f);
    // A farm gives one cargo; give the route two places with goods to
    // choose from — a warehouse that holds both.
    w.techs.add('storage');
    var built = false;
    for (var r = 3; r < 15 && !built; r++) {
      for (var d = -r; d <= r && !built; d++) {
        built = w.buildWarehouse(f.x + d, f.y + r) == null;
      }
    }
    expect(built, isTrue);
    final store = w.warehouses.last;
    store.stock[MagCargo.grain] = 50;
    store.stock[MagCargo.wood] = 10;
    w.created[MagCargo.grain] = (w.created[MagCargo.grain] ?? 0) + 50;
    w.created[MagCargo.wood] = (w.created[MagCargo.wood] ?? 0) + 10;
    final saw = w.map.industries.firstWhere(
      (i) => i.accepts.contains(MagCargo.wood) && i.town == null,
    );
    w.createRoute([store.id, w.map.startPlant.id, saw.id]);
    final r = w.routes.values.last;
    final truck = w.vehicles.values.single;
    w.assign(truck.id, r.id);
    // Without a priority the bigger stock goes first.
    truck
      ..stop = 0
      ..state = MagVehicleState.atStop
      ..cell = w.entranceOf(store) ?? truck.cell;
    w.step();
    expect(truck.cargo, MagCargo.grain);
    truck
      ..load = 0
      ..cargo = null;
    store.stock[MagCargo.grain] = 50;
    w.setPriority(r.id, [MagCargo.wood]);
    w.step();
    expect(truck.cargo, MagCargo.wood);
  });

  test('the planner: another vehicle on a line that pays, quickest first', () {
    final w = line()..xp = MagWorldProgress.xpFor(5);
    final f = w.map.startFarm, p = w.map.startPlant;
    w.createRoute([f.id, p.id]);
    final r = w.routes.values.single;
    w.assign(w.vehicles.values.single.id, r.id);
    w.step(MagRules.ticksPerDay * 10);
    expect(r.profit, greaterThan(0));
    final ideas = w.investmentIdeas;
    final more = ideas.firstWhere((i) => i.kind == MagInvestmentKind.vehicle);
    expect(more.routeId, r.id);
    expect(more.cost, MagRules.truck('pickup')!.price);
    expect(more.paybackDays, isNotNull);
    expect(more.daily, greaterThan(0));
    // Sorted by payback (unknown last).
    final known = ideas.where((i) => i.paybackDays != null).toList();
    for (var k = 1; k < known.length; k++) {
      expect(
        known[k].paybackDays,
        greaterThanOrEqualTo(known[k - 1].paybackDays!),
      );
    }
    // Buying it puts it on the line.
    expect(w.buyForRoute(more.model!, r.id), isNull);
    expect(w.vehicles.values.where((v) => v.routeId == r.id).length, 2);
    // A jammed road is offered for an upgrade (no money estimate).
    final cell = w.entranceOf(p)!;
    w.traffic[cell] = 200;
    w.xp = MagWorldProgress.xpFor(5);
    final road = w.investmentIdeas.where(
      (i) => i.kind == MagInvestmentKind.road,
    );
    expect(road, isNotEmpty);
    expect(road.first.paybackDays, isNull);
  });
}
