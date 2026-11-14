import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage S9, water: ports by a place (SEA-01), barges (SEA-02), cargo
/// ships (SEA-03), routes on rivers and lakes (SEA-04) — the same economy
/// as trucks and trains; a train and a truck meeting at a warehouse
/// (transfer, LOG-14); saves.
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

  void give(MagWorld w, Map<MagCargo, int> into, MagCargo c, int n) {
    into[c] = (into[c] ?? 0) + n;
    w.created[c] = (w.created[c] ?? 0) + n;
  }

  MagWorld waterWorld() => MagWorld.start()
    ..money = 2000000
    ..xp = MagWorldProgress.xpFor(15)
    ..techs.addAll(['stud', 'steam', 'shipping', 'combustion']);

  /// Water cells a port by [i] could stand on.
  List<int> berths(MagWorld w, MagIndustry i) => [
    for (
      var y = i.top - MagRules.portReach;
      y <= i.bottom + MagRules.portReach;
      y++
    )
      for (
        var x = i.left - MagRules.portReach;
        x <= i.right + MagRules.portReach;
        x++
      )
        if (w.map.inside(x, y) &&
            w.isWater(w.cellOf(x, y)) &&
            w.portTargets(w.cellOf(x, y)).contains(i))
          w.cellOf(x, y),
  ];

  /// A producer and a buyer of its cargo, both by water joined together.
  (MagIndustry, MagIndustry, MagCargo, int, int) waterPair(MagWorld w) {
    for (final a in w.map.industries) {
      if (a.town != null || a.spec.produces.isEmpty) continue;
      final ba = berths(w, a);
      if (ba.isEmpty) continue;
      for (final b in w.map.industries) {
        if (b == a) continue;
        final c = a.spec.produces.keys.first;
        if (!b.accepts.contains(c)) continue;
        for (final pb in berths(w, b)) {
          w.ports[pb] = b.id; // try
          final path = w.waterPath([ba.first], b);
          w.ports.remove(pb);
          if (path != null && path.length > 4) return (a, b, c, ba.first, pb);
        }
      }
    }
    fail('no two places joined by water on this map');
  }

  test('shipping opens ports and barges; the shipyard cargo ships', () {
    final w = MagWorld.start()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(15);
    expect(w.buyTruck('barge'), contains('Речное судоходство'));
    final water = w.waterMask;
    final cell = water.indexOf(1);
    expect(w.portBlocker(cell, 1), contains('Речное судоходство'));
    w.techs.addAll(['stud', 'steam', 'shipping']);
    expect(w.buyTruck('barge'), isNull);
    final barge = w.vehicles.values.last;
    expect((barge.spec.water, w.capacityOf(barge)), (true, 60));
    expect(w.buyTruck('freighter'), contains('Судоверфь'));
    w.techs.addAll(['combustion', 'shipyard']);
    expect(w.buyTruck('freighter'), isNull);
    expect(MagTechTree.byId('shipyard')!.requires, ['shipping', 'combustion']);
    // Vessels run routes only.
    w.techs.add('dispatch');
    expect(w.setAuto(barge.id, true), contains('только по маршрутам'));
    // A port only on water by its place.
    final land = w.cellOf(w.map.startFarm.x - 1, w.map.startFarm.y);
    expect(w.portBlocker(land, w.map.startFarm.id), isNotNull);
  });

  test('a barge carries cargo by water: one economy with trucks', () {
    final w = waterWorld();
    final (from, to, cargo, pa, pb) = waterPair(w);
    expect(w.buildPort(pa, from.id), isNull);
    expect(w.buildPort(pb, to.id), isNull);
    expect(w.waterConnected(from, to), isTrue);
    expect(w.journal.entries.where((e) => e.category == 'ports').length, 2);
    w.createRoute([from.id, to.id]);
    final r = w.routes.values.single;
    expect(w.buyTruck('barge'), isNull);
    final barge = w.vehicles.values.last;
    expect(w.assign(barge.id, r.id), isNull);
    give(w, from.stock, cargo, 60);
    for (var k = 0; k < MagRules.ticksPerDay * 30 && barge.trips == 0; k++) {
      w.step();
      if (barge.onMap) expect(w.isWater(barge.cell), isTrue);
    }
    expect(barge.trips, greaterThan(0));
    expect(barge.income, greaterThan(0));
    expect(r.income, barge.income);
    // Per unit and cell, cheaper than a lorry and a train.
    final lorry = MagRules.truck('lorry')!;
    expect(
      w.runningCostOf(barge) / w.capacityOf(barge),
      lessThan(lorry.runningCost / lorry.capacity),
    );
    // A route without ports is refused for a vessel.
    w.createRoute([w.map.startFarm.id, w.map.startPlant.id]);
    expect(w.assign(barge.id, w.routes.keys.last), contains('нет порта'));
    expectBalanced(w);
    // Saved and loaded mid-way, it goes on exactly.
    w.step(37);
    final b = magWorldFromJson(
      jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
    );
    expect(b.ports, w.ports);
    w.step(300);
    b.step(300);
    expect(jsonEncode(b.toJson()), jsonEncode(w.toJson()));
    // Taking a port away: refused under a vessel, allowed when free.
    for (final c in w.ports.keys.where((c) => c == barge.cell).toList()) {
      expect(w.removePort(c), 'У причала стоит судно');
    }
    final free = w.ports.keys.firstWhere((c) => c != barge.cell);
    expect(w.removePort(free), isNull);
    expect(w.ports.containsKey(free), isFalse);
  });

  test('a train and a truck meet at a warehouse (transfer, LOG-14)', () {
    final w = waterWorld()..techs.addAll(['storage']);
    final farm = w.map.startFarm, plant = w.map.startPlant;
    // A warehouse by the farm's side, a station by both.
    late MagIndustry wh;
    search:
    for (var r = 3; r < 14; r++) {
      for (var d = -r; d <= r; d++) {
        final x = plant.x + d, y = plant.y + r;
        if (w.warehouseBlocker(x, y) == null) {
          w.buildWarehouse(x, y);
          wh = w.warehouses.single;
          break search;
        }
      }
    }
    int spot(MagIndustry i) {
      for (var y = i.top - 1; y <= i.bottom + 1; y++) {
        for (var x = i.left - 1; x <= i.right + 1; x++) {
          if (w.map.roadable(x, y) &&
              w.map.industryAt(x, y) == null &&
              !w.hasRoad(x, y)) {
            return w.cellOf(x, y);
          }
        }
      }
      fail('no spot by ${i.name}');
    }

    final sa = spot(farm), sb = spot(wh);
    final plan = w.planRail(w.cx(sa), w.cy(sa), w.cx(sb), w.cy(sb));
    expect(w.buildRail(plan), isNull);
    w.buildStation(sa, farm.id);
    w.buildStation(sb, wh.id);
    w.createRoute([farm.id, wh.id]);
    w.buyTruck('steam');
    w.assign(w.vehicles.values.last.id, w.routes.keys.single);
    give(w, farm.stock, MagCargo.grain, 40);
    w.step(MagRules.ticksPerDay * 6);
    // The train put the grain into the warehouse (an internal move).
    expect(wh.stock[MagCargo.grain] ?? 0, greaterThan(0));
    expectBalanced(w);
  });

  test('older saves load without ports', () {
    final w = magWorldFromJson(
      jsonDecode(
            File(
              'test/fixtures/magistrali_save_v5_map2.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    expect(w.ports, isEmpty);
  });
}
