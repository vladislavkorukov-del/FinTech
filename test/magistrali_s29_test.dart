import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage S29 (2.1): cloverleaf loops, turbine, stack (three levels), metro
/// lines; saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  MagWorld rich() => MagWorld.start()
    ..money = 90000000
    ..xp = MagWorldProgress.xpFor(30)
    ..regionsLocked = false;

  /// A crossing of two straight asphalt roads (arms of 6) on open land.
  (MagWorld, int, int)? crossing() {
    final w = rich();
    w.techs.add('interchanges');
    final n = w.size;
    for (var y0 = 9; y0 < n - 9; y0 += 3) {
      for (var x0 = 9; x0 < n - 9; x0 += 2) {
        final v = w.planWay([
          (x0 + .5, y0 - 6.5),
          (x0 + .5, y0 + 6.5),
        ], road: MagRoad.asphalt);
        final h = w.planWay([
          (x0 - 6.5, y0 + .5),
          (x0 + 6.5, y0 + .5),
        ], road: MagRoad.asphalt);
        if (v.error != null || h.error != null) continue;
        if (v.shape?.length != 2 || h.shape?.length != 2) continue;
        // Open land all round (room for the ramps).
        var open = true;
        for (var y = y0 - 6; y <= y0 + 6 && open; y++) {
          for (var x = x0 - 6; x <= x0 + 6 && open; x++) {
            open =
                w.map.roadable(x, y) &&
                !w.hasRoad(x, y) &&
                w.rails[w.cellOf(x, y)] == 0;
          }
        }
        if (!open) continue;
        w.buildRoad(v);
        w.buildRoad(h);
        return (w, x0, y0);
      }
    }
    return null;
  }

  for (final kind in [
    MagJunction.clover,
    MagJunction.turbine,
    MagJunction.stack,
  ]) {
    test('$kind: built at a crossing, every way through still works', () {
      final c = crossing();
      expect(c, isNotNull, reason: 'no open crossing on this map');
      final (w, x0, y0) = c!;
      final x = w.cellOf(x0, y0);
      final ways = w.ways.length;
      expect(w.buildJunction(x, kind), isNull, reason: '$kind');
      expect(w.ways.length, greaterThan(ways));
      final west = w.cellOf(x0 - 6, y0), east = w.cellOf(x0 + 6, y0);
      final north = w.cellOf(x0, y0 - 6), south = w.cellOf(x0, y0 + 6);
      expect(w.roadPathCells(west, east), isNotNull);
      expect(w.roadPathCells(north, south), isNotNull);
      // Turning from one road onto the other: by the ramps.
      expect(w.roadPathCells(west, north), isNotNull, reason: '$kind turn');
      expect(w.roadPathCells(east, south), isNotNull, reason: '$kind turn');
      expect(reload(w).ways.length, w.ways.length);
      if (kind == MagJunction.stack) {
        // Ramps pass over the crossing: more than one bridge there.
        expect(w.wayIndex.runs.length, greaterThan(1));
      }
    });
  }

  test('big interchanges need long arms', () {
    final w = rich();
    w.techs.add('interchanges');
    final f = w.map.startFarm;
    final x0 = f.right + 8, y0 = f.bottom + 6;
    w.buildRoad(
      w.planWay([
        (x0 + .5, y0 - 2.5),
        (x0 + .5, y0 + 2.5),
      ], road: MagRoad.asphalt),
    );
    w.buildRoad(
      w.planWay([
        (x0 - 2.5, y0 + .5),
        (x0 + 2.5, y0 + .5),
      ], road: MagRoad.asphalt),
    );
    final x = w.cellOf(x0, y0);
    if (w.junctionBlocker(x, MagJunction.overpass) != null) return;
    expect(w.junctionBlocker(x, MagJunction.clover), contains('4 клетки'));
  });

  test('metro lines join cities with a metro: fares, growth, saved', () {
    final w = rich();
    w.techs.add('metro');
    final towns = w.settlements.take(3).toList();
    final a = towns[0], b = towns[1];
    for (final t in [a, b]) {
      t.town!.level = MagRules.metroLevel;
    }
    expect(w.buildMetro(a.id), isNull);
    expect(w.metroLineBlocker(a.id, b.id), contains('уже есть метро'));
    expect(w.buildMetro(b.id), isNull);
    final growth = w.metroGrowth(a);
    final why = w.metroLineBlocker(a.id, b.id);
    if (why != null) {
      expect(why, contains('далеко'));
      return;
    }
    final money = w.money;
    expect(w.buildMetroLine(a.id, b.id), isNull);
    expect(w.money, money - w.metroLinePrice(a, b));
    expect(w.metroLineBlocker(b.id, a.id), contains('уже есть'));
    expect(w.metroGrowth(a), greaterThan(growth));
    expect(reload(w).metroLines.single, (a.id, b.id));
    w.step(MagRules.ticksPerDay * 2);
    final fares =
        w.months.fold(0, (s, m) => s + (m.income['metro_lines'] ?? 0)) +
        (w.month.income['metro_lines'] ?? 0);
    expect(fares, greaterThan(0));
  });
}
