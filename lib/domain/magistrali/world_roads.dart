part of 'world.dart';

/// Working with roads already on the map: the stretch under a finger,
/// a better surface for it, and a drawn road carried on from its end.
extension MagWorldRoads on MagWorld {
  /// Road cells next to [c].
  List<int> roadNeighbours(int c) {
    final x = cx(c), y = cy(c);
    return [
      for (var d = 0; d < 4; d++)
        if (map.inside(x + MagDir.dx[d], y + MagDir.dy[d]) &&
            roads[cellOf(x + MagDir.dx[d], y + MagDir.dy[d])] != 0)
          cellOf(x + MagDir.dx[d], y + MagDir.dy[d]),
    ];
  }

  /// The stretch of road through [cell]: cells of the same surface joined
  /// in a line, up to the nearest crossroads (a crossroads cell belongs to
  /// the stretch it is tapped on, not to the others). At most [limit]
  /// cells.
  List<int> roadSegment(int cell, {int limit = 120}) {
    if (roads[cell] == 0) return const [];
    final type = roads[cell];
    final seen = <int>{cell};
    final out = <int>[cell];
    final queue = <int>[];
    if (roadNeighbours(cell).length <= 2) queue.add(cell);
    // A crossroads tapped on its own stays a stretch of one cell.
    while (queue.isNotEmpty && out.length < limit) {
      final c = queue.removeLast();
      for (final n in roadNeighbours(c)) {
        if (seen.contains(n) || roads[n] != type) continue;
        seen.add(n);
        out.add(n);
        // A crossroads ends the stretch (it is included, not passed).
        if (roadNeighbours(n).length <= 2) queue.add(n);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// The next surface after [r] (null at the best one).
  MagRoad? nextRoad(MagRoad r) =>
      r.index + 1 < MagRoad.values.length ? MagRoad.values[r.index + 1] : null;

  /// A plan that lays the next surface over [cells] (all of one surface).
  MagRoadPlan upgradePlan(List<int> cells) {
    if (cells.isEmpty) {
      return const MagRoadPlan([], 0, MagRoad.dirt, 'Здесь нет дороги');
    }
    final now = MagRoad.values[roads[cells.first]];
    final next = nextRoad(now);
    if (next == null) {
      return MagRoadPlan(cells, 0, now, 'Это уже лучшее покрытие');
    }
    if (!roadUnlocked(next)) {
      return MagRoadPlan(
        cells,
        0,
        next,
        'Покрытие откроется на ${MagRules.roads[next]!.level} уровне',
      );
    }
    final cost = cells.fold(0, (s, c) => s + cellCost(c, next));
    return MagRoadPlan(cells, cost, next);
  }

  /// A drawn road carried on: [more] starts where [first] ends; the cells
  /// are joined without repeats and priced again.
  MagRoadPlan joinPlans(MagRoadPlan first, MagRoadPlan more) {
    if (more.error != null) return more;
    final seen = <int>{};
    final cells = [
      for (final c in [...first.cells, ...more.cells])
        if (seen.add(c)) c,
    ];
    final cost = cells.fold(0, (s, c) => s + cellCost(c, first.type));
    return MagRoadPlan(cells, cost, first.type, first.error);
  }
}
