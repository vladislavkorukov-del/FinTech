import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage S26 (1.98): free-form roads, metro, marshalling yards, freight
/// hubs, cargo futures, excursions; saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  MagWorld rich() => MagWorld.start()
    ..money = 5000000
    ..xp = MagWorldProgress.xpFor(20);

  test('a road follows a straight line at any angle, or a traced curve', () {
    final w = rich();
    final line = w.lineCells(10, 10, 16, 13);
    expect(line.first, w.cellOf(10, 10));
    expect(line.last, w.cellOf(16, 13));
    expect(line.length, 6 + 3 + 1);
    // Side to side: every step one cell across or down.
    for (var i = 1; i < line.length; i++) {
      final d =
          (w.cx(line[i]) - w.cx(line[i - 1])).abs() +
          (w.cy(line[i]) - w.cy(line[i - 1])).abs();
      expect(d, 1);
    }
    // Close to the true line: never more than a cell off.
    for (final c in line) {
      final t = (w.cx(c) - 10) / 6;
      expect((w.cy(c) - (10 + 3 * t)).abs(), lessThanOrEqualTo(1));
    }
    final f = w.map.startFarm, p = w.map.startPlant;
    final plan = w.planRoadLine(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt);
    expect(plan.error, isNull);
    expect(plan.cells.first, w.cellOf(f.x + f.size, f.y));
    expect(plan.cells.last, w.cellOf(p.x - 1, p.y));
    // A finger's trace: through its points, in order.
    final a = plan.cells.first, b = plan.cells.last;
    final midX = (w.cx(a) + w.cx(b)) ~/ 2;
    final trace = [
      a,
      w.cellOf(midX, w.cy(a) + 2),
      w.cellOf(midX + 1, w.cy(a) + 3),
      b,
    ];
    final traced = w.planTrace(trace, road: MagRoad.dirt);
    if (traced.error == null) {
      expect(traced.cells.first, a);
      expect(traced.cells.last, b);
      expect(w.buildRoad(traced), isNull);
      expect(w.connected(f, p), isTrue);
    }
    expect(w.planTrace([a], road: MagRoad.dirt).error, isNotNull);
  });

  test('metro: in big cities, more travellers, faster growth, fares', () {
    final w = rich();
    final town = w.map.industries.firstWhere((i) => i.town != null);
    expect(w.metroBlocker(town), contains('Метрополитен'));
    w.techs.add('metro');
    expect(w.metroBlocker(town), contains('Региональный'));
    town.town!.level = MagRules.metroLevel;
    final money = w.money;
    expect(w.buildMetro(town.id), isNull);
    expect(w.money, money - MagRules.metroPrice);
    expect(w.metroFactor(town), MagRules.metroPassengers);
    expect(w.metroGrowth(town), MagRules.metroGrowth);
    expect(w.buildMetro(town.id), contains('уже'));
    expect(reload(w).metros, contains(town.id));
    w.step(MagRules.ticksPerDay * 2);
    final fares =
        w.months.fold(0, (s, m) => s + (m.income['metro_fares'] ?? 0)) +
        (w.month.income['metro_fares'] ?? 0);
    expect(fares, greaterThan(0));
  });

  test('a freight hub: more room and faster loading', () {
    final w = rich();
    w.techs.add('storage');
    final f = w.map.startFarm;
    String? why;
    MagIndustry? store;
    for (var d = 3; d < 12 && store == null; d++) {
      why = w.buildWarehouse(f.right + d, f.bottom + 2);
      if (why == null) store = w.warehouses.last;
    }
    expect(store, isNotNull, reason: why);
    final room = w.warehouseCapacityOf(store!);
    expect(w.buildHub(store.id), contains('Грузовые хабы'));
    w.techs.add('hubs');
    expect(w.buildHub(f.id), contains('складе'));
    expect(w.buildHub(store.id), isNull);
    expect(w.warehouseCapacityOf(store), (room * MagRules.hubRoom).round());
    expect(reload(w).hubs, contains(store.id));
  });

  test('a marshalling yard at a station: trains load twice as fast', () {
    final w = rich();
    w.techs.addAll(['stud', 'steam']);
    final a = w.map.startFarm;
    int? st;
    for (var r = 1; r <= MagRules.stationReach && st == null; r++) {
      for (var x = a.left - r; x <= a.right + r && st == null; x++) {
        final y = a.bottom + r;
        if (!w.map.roadable(x, y) || w.map.industryAt(x, y) != null) continue;
        final plan = w.planRail(x, y, x + 1, y);
        if (plan.error != null || w.buildRail(plan) != null) continue;
        if (w.buildStation(w.cellOf(x, y), a.id) == null) st = w.cellOf(x, y);
      }
    }
    expect(st, isNotNull);
    expect(w.buildYard(st!), contains('Сортировочные'));
    w.techs.addAll(['signalling', 'yards']);
    expect(w.buildYard(st), isNull);
    expect(w.buyTruck('steam'), isNull);
    final t = w.vehicles.values.last..cell = st;
    expect(w.handleAt(t), (w.handleRate * MagRules.yardHandling).round());
    t.cell = -1;
    expect(reload(w).yards, contains(st));
  });

  test('futures: a margin now, a premium if delivered in time', () {
    final w = rich();
    final c = MagCargo.values.firstWhere(
      (c) => !c.people && w.cargoAvailable(c),
    );
    w.xp = MagWorldProgress.xpFor(5);
    expect(w.buyFuture(c, 50), contains('уровня'));
    w.xp = MagWorldProgress.xpFor(20);
    final money = w.money;
    expect(w.buyFuture(c, 50), isNull);
    final f = w.futures.single;
    expect(w.money, money - f.margin);
    expect(f.payout, greaterThan(f.margin));
    expect(reload(w).futures.single.units, 50);
    // Missed: the margin is lost.
    w.step(MagRules.ticksPerDay * (MagRules.futureDays + 2));
    expect(w.futures, isEmpty);
    for (var k = 0; k < MagRules.futuresMax; k++) {
      expect(w.buyFuture(c, 50), isNull);
    }
    expect(w.buyFuture(c, 50), contains('Не больше'));
  });

  test('an excursion: a route through a resort, tourists pay more', () {
    final w = rich();
    w.regionsLocked = false;
    w.techs.addAll(['combustion', 'tourism']);
    final towns = w.settlements.take(2).toList();
    MagIndustry? resort;
    final t0 = towns.first;
    outer:
    for (var d = 3; d < 30; d++) {
      for (var y = t0.y - d; y <= t0.y + d; y++) {
        for (var x = t0.x - d; x <= t0.x + d; x++) {
          if (!w.map.inside(x, y)) continue;
          for (final k in [
            MagIndustryKind.lakeResort,
            MagIndustryKind.skiResort,
          ]) {
            if (w.buildIndustry(k, x, y) == null) {
              resort = w.map.industries.last;
              break outer;
            }
          }
        }
      }
    }
    expect(resort, isNotNull);
    expect(w.createRoute([towns[0].id, towns[1].id]), isNull);
    final short = w.routes.keys.last;
    expect(w.setExcursion(short, true), contains('трёх'));
    expect(w.createRoute([towns[0].id, resort!.id, towns[1].id]), isNull);
    final r = w.routes.keys.last;
    expect(w.setExcursion(r, true), isNull);
    expect(w.buyTruck('bus'), isNull);
    final bus = w.vehicles.values.last..routeId = r;
    expect(
      w.cargoPayFactor(bus, MagCargo.passengers),
      closeTo(bus.spec.comfort * MagRules.excursionPay, 1e-9),
    );
    bus.routeId = null;
    expect(reload(w).excursions, contains(r));
    expect(w.setExcursion(r, false), isNull);
    expect(w.excursions, isEmpty);
  });
}
