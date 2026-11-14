import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S13 (1.85): workers at businesses (PASS-05), road capacity and
/// load (ROAD-08, ROAD-10), long lines with orders at each stop; saves.
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

  /// The start line by road, and the plant's entrance on to the nearest
  /// village; returns the village.
  MagIndustry lineToVillage(MagWorld w) {
    final f = w.map.startFarm, p = w.map.startPlant;
    expect(
      w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt)),
      isNull,
    );
    final v =
        (w.settlements.toList()
              ..sort((a, b) => a.distanceTo(p).compareTo(b.distanceTo(p))))
            .first;
    final e = w.entranceOf(p)!;
    for (var y = v.top - 1; y <= v.bottom + 1; y++) {
      for (var x = v.left - 1; x <= v.right + 1; x++) {
        if (w.connected(p, v)) return v;
        final plan = w.planRoad(w.cx(e), w.cy(e), x, y, MagRoad.dirt);
        if (plan.error == null) w.buildRoad(plan);
      }
    }
    expect(w.connected(p, v), isTrue);
    return v;
  }

  test('workers: from settlements, to businesses; output rises, fades', () {
    final w = motorStart()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(5);
    final v = lineToVillage(w);
    final plant = w.map.startPlant;
    w.step(MagRules.ticksPerDay * 5);
    final daily = (v.town!.population ~/ MagRules.peoplePerWorker).clamp(
      1,
      1 << 20,
    );
    expect(v.stock[MagCargo.workers], daily * MagRules.workerDays);
    expect(plant.accepts, contains(MagCargo.workers));
    expect(v.accepts, isNot(contains(MagCargo.workers)));
    // Never in contracts or city orders.
    expect(w.contracts.any((c) => c.cargo.people), isFalse);
    // A bus takes them to the plant; a lorry never does.
    w.createRoute([v.id, plant.id]);
    final r = w.routes.values.last;
    w.setStopOrder(r.id, 0, pick: MagCargo.workers);
    expect(w.buyTruck('bus'), isNull);
    final bus = w.vehicles.values.last;
    expect(w.canCarry(bus, MagCargo.workers), isTrue);
    expect(w.canCarry(w.vehicles.values.first, MagCargo.workers), isFalse);
    w.assign(bus.id, r.id);
    final before = w.outputFactor(plant);
    for (var k = 0; k < MagRules.ticksPerDay * 20 && plant.staff == 0; k++) {
      w.step();
    }
    expect(plant.staff, greaterThan(0));
    expect(w.outputFactor(plant), greaterThan(before));
    expect(w.delivered[MagCargo.workers], greaterThan(0));
    expect(bus.income, greaterThan(0));
    // Saved; and without new shifts the staff fades away.
    expect(reload(w).map.industry(plant.id)!.staff, plant.staff);
    w.deleteRoute(r.id);
    w.step(MagRules.ticksPerDay * 30);
    expect(plant.staff, 0);
    expectBalanced(w);
  });

  test('roads: traffic counts, capacity, slow when full; saved', () {
    final w = motorStart()..money = 1000000;
    final f = w.map.startFarm, p = w.map.startPlant;
    final plan = w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt);
    w.buildRoad(plan);
    w.createRoute([f.id, p.id]);
    w.assign(w.vehicles.values.single.id, w.routes.keys.single);
    w.step(MagRules.ticksPerDay * 3);
    final mid = plan.cells[plan.cells.length ~/ 2];
    expect(w.trafficOf(mid), greaterThan(0));
    expect(w.loadOf(mid), w.trafficOf(mid) / 24);
    expect(w.congestionOf(mid), 1);
    // A crowded cell: three times its capacity — half speed.
    w.traffic[mid] = 24 * 3;
    expect(w.congestionOf(mid), closeTo(.5, 1e-9));
    w.traffic[mid] = 36;
    expect(w.congestionOf(mid), closeTo(1 / 1.25, 1e-9));
    expect(MagRules.roads[MagRoad.motorway]!.capacity, 192);
    final b = reload(w);
    expect(b.trafficOf(mid), 36);
    expect(b.trafficToday, w.trafficToday);
  });

  test('a long line: grain to the plant, its food on to the village', () {
    final w = motorStart()..money = 1000000;
    final v = lineToVillage(w);
    final f = w.map.startFarm, p = w.map.startPlant;
    expect(w.createRoute([f.id, p.id, v.id]), isNull);
    final r = w.routes.values.last;
    w.assign(w.vehicles.values.single.id, r.id);
    for (var k = 0; k < MagRules.ticksPerDay * 30; k++) {
      w.step();
      if ((w.delivered[MagCargo.food] ?? 0) > 0) break;
    }
    expect(w.delivered[MagCargo.grain], greaterThan(0));
    expect(w.delivered[MagCargo.food], greaterThan(0));
    expectBalanced(w);
  });

  test('orders at a stop: only this cargo, nothing, keep the load', () {
    final w = motorStart()..money = 1000000;
    final f = w.map.startFarm, p = w.map.startPlant;
    w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt));
    w.createRoute([f.id, p.id]);
    final r = w.routes.values.single;
    expect(
      w.setStopOrder(r.id, 0, pick: MagCargo.steel),
      contains('не отдаёт'),
    );
    expect(w.setStopOrder(r.id, 9), isNotNull);
    // Keep the load at the plant: nothing is ever delivered.
    expect(w.setStopOrder(r.id, 1, noDrop: true), isNull);
    final truck = w.vehicles.values.single;
    w.assign(truck.id, r.id);
    w.step(MagRules.ticksPerDay * 8);
    expect(w.delivered[MagCargo.grain], isNull);
    // Saved with the line.
    final b = reload(w);
    expect(b.routes[r.id]!.noDrop, {1});
    // Load nothing at the farm: the truck runs empty.
    w.setStopOrder(r.id, 1);
    w.setStopOrder(r.id, 0, noPick: true);
    truck
      ..load = 0
      ..cargo = null;
    w.created[MagCargo.grain] = w.totalCargo()[MagCargo.grain] ?? 0;
    w.destroyed[MagCargo.grain] = 0;
    w.step(MagRules.ticksPerDay * 4);
    expect(truck.load, 0);
    // Back to automatic: grain flows.
    w.setStopOrder(r.id, 0);
    for (var k = 0; k < MagRules.ticksPerDay * 10; k++) {
      w.step();
      if ((w.delivered[MagCargo.grain] ?? 0) > 0) break;
    }
    expect(w.delivered[MagCargo.grain], greaterThan(0));
  });
}
