import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage S28 (2.0): bridges over lakes, overpasses that never join the
/// road beneath, interchanges (overpass, cloverleaf, roundabout), removing
/// a whole curve, street trams; saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  MagWorld rich() => MagWorld.start()
    ..money = 50000000
    ..xp = MagWorldProgress.xpFor(24)
    ..regionsLocked = false;

  /// A straight run of free land across a lake: (start, end) points.
  (MagPt, MagPt)? acrossLake(MagWorld w) {
    final n = w.size;
    for (var y = 2; y < n - 2; y++) {
      for (var x = 2; x < n - 20; x++) {
        if (!w.map.roadable(x, y) || w.map.at(x + 1, y) != MagTerrain.lake) {
          continue;
        }
        var e = x + 1;
        while (e < n - 1 && w.map.at(e, y) == MagTerrain.lake) {
          e++;
        }
        if (e - x - 1 > MagRules.maxSpan || !w.map.roadable(e, y)) continue;
        if (!w.map.roadable(e + 1, y) || !w.map.roadable(x - 1, y)) continue;
        return ((x - .5, y + .5), (e + 1.5, y + .5));
      }
    }
    return null;
  }

  test('a bridge over a lake: built, crossed by a link, saved', () {
    final w = rich();
    final ends = acrossLake(w);
    expect(ends, isNotNull, reason: 'no lake to bridge on this map');
    final (a, b) = ends!;
    final plan = w.planWay([a, b], road: MagRoad.dirt);
    expect(plan.error, isNull);
    expect(plan.spans, isNotEmpty);
    for (final c in plan.spans!) {
      expect(w.map.at(w.cx(c), w.cy(c)), MagTerrain.lake);
    }
    expect(w.buildRoad(plan), isNull);
    // The lake stays water; the road on both shores is joined by a link.
    for (final c in plan.spans!) {
      expect(w.roads[c], 0);
    }
    final links = w.spanLinks()!;
    expect(links, isNotEmpty);
    final from = plan.cells.first, to = plan.cells.last;
    final path = w.roadPathCells(from, to);
    expect(path, isNotNull);
    expect(path!.last, to);
    expect(reload(w).ways.single.spans, plan.spans);
  });

  test('an overpass passes over a road without joining it', () {
    final w = rich();
    w.techs.add('interchanges');
    final f = w.map.startFarm;
    final y0 = f.bottom + 4, x0 = f.right + 6;
    // A road down (north–south)…
    final down = w.planWay([
      (x0 + .5, y0 - 4.5),
      (x0 + .5, y0 + 4.5),
    ], road: MagRoad.asphalt);
    expect(down.error, isNull);
    expect(w.buildRoad(down), isNull);
    // …and an overpass across it.
    final over = w.planWay(
      [(x0 - 4.5, y0 + .5), (x0 + 5.5, y0 + .5)],
      road: MagRoad.asphalt,
      over: true,
    );
    expect(over.error, isNull);
    expect(over.spans, contains(w.cellOf(x0, y0)));
    expect(w.buildRoad(over), isNull);
    // Across: yes (over the link). From the overpass onto the road below:
    // no — no junction.
    final west = w.cellOf(x0 - 4, y0), east = w.cellOf(x0 + 5, y0);
    final north = w.cellOf(x0, y0 - 4);
    expect(w.roadPathCells(west, east), isNotNull);
    expect(w.roadPathCells(west, north), isNull);
    expect(w.roadPathCells(north, w.cellOf(x0, y0 + 4)), isNotNull);
  });

  test('interchanges: overpass, cloverleaf and roundabout at a crossing', () {
    for (final kind in [MagJunction.overpass, MagJunction.roundabout]) {
      final w = rich();
      final f = w.map.startFarm;
      final y0 = f.bottom + 6, x0 = f.right + 8;
      w.buildRoad(
        w.planWay([
          (x0 + .5, y0 - 4.5),
          (x0 + .5, y0 + 4.5),
        ], road: MagRoad.asphalt),
      );
      w.buildRoad(
        w.planWay([
          (x0 - 4.5, y0 + .5),
          (x0 + 5.5, y0 + .5),
        ], road: MagRoad.asphalt),
      );
      final x = w.cellOf(x0, y0);
      expect(w.junctionBlocker(x, kind), contains('Развязки'));
      w.techs.add('interchanges');
      expect(
        w.junctionBlocker(w.cellOf(x0 + 3, y0 + 3), kind),
        contains('перекрёсток'),
      );
      final money = w.money;
      expect(w.buildJunction(x, kind), isNull, reason: '$kind');
      expect(w.money, lessThanOrEqualTo(money - w.junctionPrice(kind)));
      final west = w.cellOf(x0 - 4, y0), east = w.cellOf(x0 + 5, y0);
      final north = w.cellOf(x0, y0 - 4), south = w.cellOf(x0, y0 + 4);
      expect(w.roadPathCells(west, east), isNotNull, reason: '$kind');
      expect(w.roadPathCells(north, south), isNotNull, reason: '$kind');
      switch (kind) {
        case MagJunction.overpass:
          expect(w.roadPathCells(west, north), isNull);
        case MagJunction.clover:
        case MagJunction.turbine:
        case MagJunction.stack:
        case MagJunction.roundabout:
          expect(w.roadPathCells(west, north), isNotNull, reason: '$kind');
      }
      if (kind == MagJunction.roundabout) expect(w.roads[x], 0); // the island
      final back = reload(w);
      expect(back.ways.length, w.ways.length);
    }
  });

  test('a whole curve comes off with one tap', () {
    final w = rich();
    final f = w.map.startFarm;
    final a = (f.right + 3.5, f.bottom + 3.5);
    final plan = w.planWay([
      a,
      (a.$1 + 4.2, a.$2 + 3.3),
      (a.$1 + 9.1, a.$2 + 1.2),
    ], road: MagRoad.dirt);
    expect(plan.error, isNull);
    expect(w.buildRoad(plan), isNull);
    final mid = plan.cells[plan.cells.length ~/ 2];
    expect(w.wayAt(mid), isNotNull);
    final money = w.money;
    expect(w.removeWayAt(mid), isNull);
    expect(w.ways, isEmpty);
    for (final c in plan.cells) {
      expect(w.roads[c], 0);
    }
    expect(w.money, greaterThan(money)); // part of the price back
    expect(w.removeWayAt(mid), contains('нет кривой'));
  });

  test('street trams: their streets and better pay between big towns', () {
    final w = rich();
    w.techs.addAll(['combustion', 'electrotransport']);
    final towns = w.settlements.take(2).toList();
    for (final t in towns) {
      t.town!.level = MagRules.tramTownLevel;
    }
    final a = towns[0], b = towns[1];
    final plan = w.planRoad(
      w.cx(
        w.accessCells(a).isEmpty
            ? w.cellOf(a.right + 1, a.y)
            : w.accessCells(a).first,
      ),
      a.y,
      b.left - 1,
      b.y,
      MagRoad.dirt,
    );
    if (plan.error == null) w.buildRoad(plan);
    expect(w.createRoute([a.id, b.id]), isNull);
    expect(w.buyTruck('tram'), isNull);
    final tram = w.vehicles.values.last..routeId = w.routes.keys.last;
    expect(w.tramFactor(tram), MagRules.tramStreetPay);
    expect(
      w.cargoPayFactor(tram, MagCargo.passengers),
      closeTo(tram.spec.comfort * MagRules.tramStreetPay, 1e-9),
    );
    if (w.connected(a, b)) expect(w.tramStreets(), isNotEmpty);
    tram.routeId = null;
  });
}
