import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage S8, railways: technology (TECH-03, RAIL-04), track (RAIL-01),
/// stations by a place (RAIL-02), steam and diesel engines (RAIL-03,
/// RAIL-04), wagons and train make-up (RAIL-05, RAIL-06), trains that
/// never share a cell and give way head to head (RAIL-07), upgrades
/// (RAIL-09) — one economy with trucks; saves.
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

  MagWorld railWorld() => MagWorld.start()
    ..money = 1000000
    ..xp = MagWorldProgress.xpFor(8)
    ..techs.addAll(['stud', 'steam', 'combustion']);

  /// A free cell next to a place for a station.
  int stationSpot(MagWorld w, MagIndustry i, {int? avoid}) {
    for (var r = 1; r <= MagRules.stationReach; r++) {
      for (var y = i.top - r; y <= i.bottom + r; y++) {
        for (var x = i.left - r; x <= i.right + r; x++) {
          if (!w.map.roadable(x, y) || w.map.industryAt(x, y) != null) continue;
          if (w.hasRoad(x, y)) continue;
          final c = w.cellOf(x, y);
          if (c == avoid) continue;
          return c;
        }
      }
    }
    fail('no station spot by ${i.name}');
  }

  /// Track from a station by [a] to a station by [b].
  (int, int) line(MagWorld w, MagIndustry a, MagIndustry b) {
    final sa = stationSpot(w, a), sb = stationSpot(w, b);
    final plan = w.planRail(w.cx(sa), w.cy(sa), w.cx(sb), w.cy(sb));
    expect(plan.error, isNull);
    expect(w.buildRail(plan), isNull);
    expect(w.buildStation(sa, a.id), isNull);
    expect(w.buildStation(sb, b.id), isNull);
    return (sa, sb);
  }

  test('railways open with steam; diesel later', () {
    final w = MagWorld.start()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(8);
    expect(w.planRail(10, 10, 14, 10).error, contains('Паровая тяга'));
    expect(w.buyTruck('steam'), contains('Паровая тяга'));
    final steam = MagTechTree.byId('steam')!;
    expect(steam.effects[MagBonus.rails], 1);
    expect(MagTechTree.byId('dieseltrain')!.requires, ['steam', 'combustion']);
    w.techs.addAll(['stud', 'steam']);
    expect(w.buyTruck('steam'), isNull);
    final t = w.vehicles.values.last;
    expect((t.spec.rail, t.wagons), (true, 1));
    expect(w.capacityOf(t), t.spec.wagonCapacity);
    w.xp = MagWorldProgress.xpFor(12);
    expect(w.buyTruck('diesel'), contains('Тепловозная'));
    w.techs.add('dieseltrain');
    expect(w.buyTruck('diesel'), isNull);
    // Trains run routes only.
    w.techs.add('dispatch');
    expect(w.setAuto(t.id, true), 'Поезда ходят только по маршрутам');
  });

  test('track and stations: where they may go, cost, crossings, removal', () {
    final w = railWorld();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    final money = w.money;
    final (sa, sb) = line(w, farm, plant);
    expect(w.money, lessThan(money - 2 * MagRules.stationPrice));
    expect(w.stationCells(farm), [sa]);
    expect(w.stationTargets(sb).first, plant);
    // Not on a place; a station only on track and by its place.
    expect(w.planRail(farm.x, farm.y, farm.x + 4, farm.y).error, isNotNull);
    final bare = w.cellOf(w.cx(sa), w.cy(sa) + 6);
    expect(w.stationBlocker(bare, farm.id), isNotNull);
    // A road may cross the track (a level crossing).
    final mid = w.railPath([sa], plant)!;
    final cross = mid[mid.length ~/ 2];
    final x = w.cx(cross), y = w.cy(cross);
    final road = w.planRoad(x, y - 2, x, y + 2, MagRoad.dirt);
    if (road.error == null) {
      expect(w.buildRoad(road), isNull);
      expect(w.rails[cross], 1);
    }
    // Nothing is built on track; a settlement does not grow onto it.
    expect(
      w.buildBlocker(MagIndustryKind.mill, w.cx(cross), w.cy(cross)),
      isNotNull,
    );
    // Taking track away takes its station too.
    expect(w.removeRail([sa]), isNull);
    expect(w.stationCells(farm), isEmpty);
  });

  test('a steam train carries grain: one economy with trucks', () {
    final w = railWorld();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    line(w, farm, plant);
    w.createRoute([farm.id, plant.id]);
    final r = w.routes.values.single;
    expect(w.buyTruck('steam'), isNull);
    final t = w.vehicles.values.last;
    expect(w.setWagons(t.id, 3), isNull);
    expect(w.capacityOf(t), 3 * t.spec.wagonCapacity);
    expect(w.speedOf(t), lessThan(t.spec.speed));
    expect(w.assign(t.id, r.id), isNull);
    give(w, farm.stock, MagCargo.grain, 60);
    w.step(MagRules.ticksPerDay * 8);
    expect(t.trips, greaterThan(0));
    expect(t.income, greaterThan(0));
    expect(r.income, t.income);
    expect(w.delivered[MagCargo.grain] ?? 0, greaterThan(0));
    expect(
      w.journal.entries.where(
        (e) => e.category == 'delivery' && e.sourceId == t.id,
      ),
      isNotEmpty,
    );
    // Per unit and cell it is cheaper to run than a lorry.
    final lorry = MagRules.truck('lorry')!;
    expect(
      w.runningCostOf(t) / w.capacityOf(t),
      lessThan(lorry.runningCost / lorry.capacity),
    );
    // Upgrades work for trains too (RAIL-09).
    final c0 = w.capacityOf(t);
    expect(w.upgrade(t.id, MagUpgrade.body), isNull);
    expect(w.capacityOf(t), greaterThan(c0));
    // Wagons can be taken off (half back), not below one or with cargo
    // that would not fit.
    expect(w.setWagons(t.id, 0), contains('от 1'));
    expect(w.setWagons(t.id, 9), contains('до 4'));
    expectBalanced(w);
    // A route without stations is refused for a train.
    final v = w.settlements.firstWhere((i) => i.name == 'Луговое');
    w.createRoute([plant.id, v.id]);
    expect(w.assign(t.id, w.routes.keys.last), contains('нет станции'));
  });

  test('two trains on one track never meet in a cell and both deliver', () {
    final w = railWorld();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    final (sa, sb) = line(w, farm, plant);
    // A second track beside the first, joined to it all along (a double
    // line with crossovers), and a second platform at each end.
    final first = w.railPath([sa], plant)!;
    final second = <int>[];
    for (final c in first) {
      for (final d in [2, 1]) {
        final x = w.cx(c) + MagDir.dx[d], y = w.cy(c) + MagDir.dy[d];
        if (w.map.roadable(x, y) &&
            w.map.industryAt(x, y) == null &&
            w.rails[w.cellOf(x, y)] == 0) {
          second.add(w.cellOf(x, y));
        }
      }
    }
    for (final c in second) {
      w.rails[c] = 1;
    }
    w.roadVersion++;
    // A second platform at each end.
    for (final (cell, place) in [(sa, farm), (sb, plant)]) {
      final x = w.cx(cell), y = w.cy(cell);
      for (var d = 0; d < 4; d++) {
        final n = w.cellOf(x + MagDir.dx[d], y + MagDir.dy[d]);
        if (w.rails[n] != 0 &&
            !w.stations.containsKey(n) &&
            w.stationBlocker(n, place.id) == null) {
          w.buildStation(n, place.id);
          break;
        }
      }
    }
    w.createRoute([farm.id, plant.id]);
    final r = w.routes.values.single;
    give(w, farm.stock, MagCargo.grain, 80);
    w.buyTruck('steam');
    final a = w.vehicles.values.last;
    w.assign(a.id, r.id);
    w.step(MagRules.ticksPerDay);
    w.buyTruck('steam');
    final b = w.vehicles.values.last;
    w.assign(b.id, r.id);
    for (var k = 0; k < MagRules.ticksPerDay * 30; k++) {
      w.step();
      if (a.onMap && b.onMap) {
        expect(a.cell, isNot(b.cell), reason: 'tick ${w.tick}');
      }
    }
    expect(a.trips, greaterThan(1));
    expect(b.trips, greaterThan(1));
    expectBalanced(w);
  });

  test('one track, two trains: they give way and never stand for ever', () {
    final w = railWorld();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    line(w, farm, plant);
    w.createRoute([farm.id, plant.id]);
    final r = w.routes.values.single;
    w.buyTruck('steam');
    final a = w.vehicles.values.last;
    w.assign(a.id, r.id);
    w.step(MagRules.ticksPerDay);
    w.buyTruck('steam');
    final b = w.vehicles.values.last;
    w.assign(b.id, r.id);
    final seen = <(int, int)>{};
    for (var k = 0; k < MagRules.ticksPerDay * 20; k++) {
      w.step();
      if (a.onMap && b.onMap) expect(a.cell, isNot(b.cell));
      seen.add((a.cell, b.cell));
    }
    // They keep moving (no dead lock), and the yielding is counted.
    expect(seen.length, greaterThan(20));
    expect(a.yields + b.yields, greaterThan(0));
    expect(w.advice.map((x) => x.kind), contains(MagAdviceKind.trainsBlocked));
  });

  test('saved and loaded: track, stations, wagons, a train mid-way', () {
    final w = railWorld();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    line(w, farm, plant);
    w.createRoute([farm.id, plant.id]);
    w.buyTruck('steam');
    final t = w.vehicles.values.last;
    w.setWagons(t.id, 2);
    w.assign(t.id, w.routes.keys.single);
    give(w, farm.stock, MagCargo.grain, 40);
    w.step(MagRules.ticksPerDay * 2 + 7);
    final b = magWorldFromJson(
      jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
    );
    expect(b.rails, w.rails);
    expect(b.stations, w.stations);
    final tb = b.vehicles[t.id]!;
    expect((tb.wagons, tb.cell, tb.load), (2, t.cell, t.load));
    w.step(400);
    b.step(400);
    expect(jsonEncode(b.toJson()), jsonEncode(w.toJson()));
    // An older save has no railways and loads as before.
    final old = magWorldFromJson(
      jsonDecode(
            File(
              'test/fixtures/magistrali_save_v5_map2.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    expect(old.rails.every((r) => r == 0), isTrue);
    expect(old.stations, isEmpty);
  });
}
