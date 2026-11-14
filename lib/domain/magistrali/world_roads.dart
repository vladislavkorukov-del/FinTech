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
    // Track is planned with no road surface (MagRoad.none).
    final cost = cells.fold(
      0,
      (s, c) =>
          s +
          (first.type == MagRoad.none
              ? railCellCost(c)
              : cellCost(c, first.type)),
    );
    return MagRoadPlan(cells, cost, first.type, first.error);
  }

  int _dirTo(int from, int to) {
    final d = to - from;
    if (d == 1) return 1;
    if (d == -1) return 3;
    return d > 0 ? 2 : 0;
  }

  /// What the road on [cell] cost to build from bare land, at today's
  /// prices (terrain, bridges and technologies included).
  int roadValue(int cell) {
    final r = MagRoad.values[roads[cell]];
    if (r == MagRoad.none) return 0;
    final t = map.at(cx(cell), cy(cell));
    final tech =
        factor(MagBonus.roadCost) *
        (t == MagTerrain.river ? factor(MagBonus.bridge) : 1);
    return (MagRules.roads[r]!.cost * MagRules.terrainCost(t)! * tech).round();
  }

  /// Credits returned for taking away the road and track on [cells]
  /// (ROAD-05): a share of what they cost.
  int demolishRefund(Iterable<int> cells) {
    var sum = 0;
    for (final c in cells.toSet()) {
      sum += roadValue(c) + railValue(c);
    }
    return (sum * MagRules.demolishRefund).round();
  }

  /// Removes road cells and returns part of their price (ROAD-05).
  String? removeRoad(Iterable<int> cells) {
    final busy = occupied;
    final list = cells.where((c) => roads[c] != 0).toSet().toList();
    if (list.isEmpty) return 'Здесь нет дороги';
    if (list.any(busy.contains)) return 'Здесь сейчас едет грузовик';
    final refund =
        (list.fold(0, (s, c) => s + roadValue(c)) * MagRules.demolishRefund)
            .round();
    for (final c in list) {
      roads[c] = 0;
    }
    if (refund > 0) _assetSale(refund, 'demolition');
    roadVersion++;
    return null;
  }
}
