import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage S27 (1.99): free ways — roads and track along any curve, their
/// footprint, vehicles on the curve, joins, removal; saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  MagWorld rich() => MagWorld.start()
    ..money = 5000000
    ..xp = MagWorldProgress.xpFor(20)
    ..regionsLocked = false;

  void sideBySide(MagWorld w, List<int> cells) {
    for (var i = 1; i < cells.length; i++) {
      final d =
          (w.cx(cells[i]) - w.cx(cells[i - 1])).abs() +
          (w.cy(cells[i]) - w.cy(cells[i - 1])).abs();
      expect(d, 1, reason: 'cells $i-1 and $i must touch side by side');
    }
  }

  test('a curve lays a footprint of cells joined side by side', () {
    final w = rich();
    final curve = w.wayCurve([(10.5, 10.5), (14.2, 12.7), (18.9, 11.1)]);
    expect(curve.first, (10.5, 10.5));
    expect(curve.last, (18.9, 11.1));
    final lay = w.layCurve(curve);
    expect(lay.cells.first, w.cellOf(10, 10));
    expect(lay.cells.last, w.cellOf(18, 11));
    sideBySide(w, lay.cells);
    // Every cell has the point of the curve in it.
    for (final c in lay.cells) {
      final (x, y) = lay.anchors[c]!;
      expect((x - w.cx(c) - .5).abs(), lessThanOrEqualTo(1.0));
      expect((y - w.cy(c) - .5).abs(), lessThanOrEqualTo(1.0));
    }
  });

  test('a free road: built along the curve, vehicles ride it, saved', () {
    final w = rich();
    final f = w.map.startFarm, p = w.map.startPlant;
    final a = (f.x + f.size + .5, f.y + .5), b = (p.x - .5, p.y + .5);
    final mid = ((a.$1 + b.$1) / 2, (a.$2 + b.$2) / 2 + 2.3);
    final plan = w.planWay([a, mid, b], road: MagRoad.dirt);
    expect(plan.error, isNull);
    expect(plan.shape, isNotNull);
    expect(plan.cost, greaterThan(0));
    expect(w.buildRoad(plan), isNull);
    expect(w.ways.single.road, MagRoad.dirt);
    expect(w.connected(f, p), isTrue);
    final c = plan.cells[plan.cells.length ~/ 2];
    expect(w.onWay(c), isTrue);
    final (x, y) = w.wayPoint(c);
    expect(
      (x - w.cx(c) - .5).abs() <= 1 && (y - w.cy(c) - .5).abs() <= 1,
      isTrue,
    );
    // Saved and read back with its curve.
    final back = reload(w);
    expect(back.ways.single.pts.length, w.ways.single.pts.length);
    expect(back.onWay(c), isTrue);
    // Upgraded cell by cell, the way follows the surface most cells have.
    for (final k in plan.cells) {
      w.roads[k] = MagRoad.asphalt.index;
    }
    w.roadVersion++;
    w.wayIndex;
    expect(w.ways.single.road, MagRoad.asphalt);
  });

  test('ends snap onto the network; a removed cell ends the way', () {
    final w = rich();
    final f = w.map.startFarm;
    final a = (f.x + f.size + .5, f.y + .5);
    final b = (a.$1 + 8.2, a.$2 + 3.4);
    final first = w.planWay([a, b], road: MagRoad.dirt);
    expect(first.error, isNull);
    expect(w.buildRoad(first), isNull);
    // A second way starting a little off the first one's end starts on it.
    final second = w.planWay([
      (b.$1 + .3, b.$2 - .2),
      (b.$1 + 4.1, b.$2 + 5.3),
    ], road: MagRoad.dirt);
    final (sx, sy) = second.shape!.first;
    // It starts on the network (a point of a way's curve or a road cell).
    expect(w.roads[w.cellOf(sx.floor(), sy.floor())], isNot(0));
    expect((sx, sy), isNot((b.$1 + .3, b.$2 - .2)));
    expect(w.buildRoad(second), isNull);
    expect(w.ways.length, 2);
    // Removing a cell of the first way: the way is gone, the rest of the
    // road stays (drawn as cells).
    final cut = first.cells[first.cells.length ~/ 2];
    expect(w.removeRoad([cut]), isNull);
    expect(w.wayIndex.ways.length, 1);
    expect(w.roads[first.cells.first], isNot(0));
  });

  test('free track; a blocked curve is refused', () {
    final w = rich();
    w.techs.addAll(['stud', 'steam']);
    final f = w.map.startFarm;
    final a = (f.right + 3.5, f.bottom + 3.5);
    final plan = w.planWay([
      a,
      (a.$1 + 6.3, a.$2 + 2.1),
      (a.$1 + 11.7, a.$2 - 1.8),
    ]);
    if (plan.error == null) {
      expect(w.buildRail(plan), isNull);
      expect(w.ways.single.rail, isTrue);
      expect(w.onWay(plan.cells[1], rail: true), isTrue);
      expect(w.onWay(plan.cells[1]), isFalse);
    }
    // Through a place: refused.
    final p = w.map.startPlant;
    // A drawn curve through a place is refused; two taps go round it.
    final through = w.planWay([
      (p.left - 2.5, p.centerY),
      (p.centerX, p.centerY),
      (p.right + 2.5, p.centerY),
    ], road: MagRoad.dirt);
    expect(through.error, contains('Трасса'));
    final round = w.planWay([
      (p.left - 2.5, p.centerY),
      (p.right + 2.5, p.centerY),
    ], road: MagRoad.dirt);
    if (round.error == null) {
      for (final c in round.cells) {
        expect(w.map.industryAt(w.cx(c), w.cy(c)), isNull);
      }
    }
    expect(w.planWay([a], road: MagRoad.dirt).error, isNotNull);
  });
}
