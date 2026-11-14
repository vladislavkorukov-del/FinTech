part of 'world.dart';

/// Railways (stage S8: TECH-03, RAIL-01, RAIL-02, RAIL-07). Track is its own
/// layer of cells; it may cross a road (a level crossing) but never a place.
/// A station is a track cell next to a place (within [MagRules.stationReach]
/// cells) and serves that place: a train standing there loads from and
/// unloads into the place exactly as a truck does at its gate, so the
/// economy, routes, journal and finances are the same for both. Trains never
/// share a cell: one waits for the track ahead to clear and, after a while,
/// looks for another way round.
extension MagWorldRails on MagWorld {
  bool get railsUnlocked => bonus(MagBonus.rails) > 0;
  bool get dieselUnlocked => bonus(MagBonus.diesel) > 0;

  bool hasRail(int x, int y) => map.inside(x, y) && rails[cellOf(x, y)] != 0;

  /// Can track lie here (roads allowed: a crossing)?
  bool _railable(int x, int y) =>
      map.roadable(x, y) && map.industryAt(x, y) == null;

  /// Cost of a cell of track (0 where track already is).
  int railCellCost(int cell) {
    if (rails[cell] != 0) return 0;
    final t = map.at(cx(cell), cy(cell));
    final k = MagRules.terrainCost(t)!;
    final tech =
        factor(MagBonus.roadCost) *
        (t == MagTerrain.river ? factor(MagBonus.bridge) : 1);
    return (MagRules.railCost * k * tech).round();
  }

  /// Plans track between two cells along the cheapest way, reusing track
  /// already laid.
  MagRoadPlan planRail(int sx, int sy, int ex, int ey) {
    if (!railsUnlocked) {
      return const MagRoadPlan(
        [],
        0,
        MagRoad.none,
        'Железные дороги откроет технология «Паровая тяга»',
      );
    }
    if (!_railable(sx, sy) || !_railable(ex, ey)) {
      return const MagRoadPlan([], 0, MagRoad.none, 'Здесь нельзя класть путь');
    }
    final goal = cellOf(ex, ey);
    final path = magAStar(
      width: size,
      height: size,
      start: cellOf(sx, sy),
      isGoal: (c) => c == goal,
      step: (a, b) {
        if (!_railable(cx(b), cy(b))) return null;
        final c = railCellCost(b);
        return c == 0 ? .2 : c / MagRules.railCost;
      },
      heuristic: (c) => ((cx(c) - ex).abs() + (cy(c) - ey).abs()) * .2,
      maxNodes: 20000,
    );
    if (path == null) {
      return const MagRoadPlan([], 0, MagRoad.none, 'Сюда не проложить путь');
    }
    return MagRoadPlan(
      path,
      path.fold(0, (s, c) => s + railCellCost(c)),
      MagRoad.none,
    );
  }

  String? buildRail(MagRoadPlan plan) {
    if (plan.error != null) return plan.error;
    if (plan.cells.isEmpty) return 'Нечего строить';
    final cost = plan.cells.fold(0, (s, c) => s + railCellCost(c));
    if (cost == 0) return 'Здесь путь уже есть';
    if (cost > money) return 'Не хватает кредитов: нужно $cost';
    for (final c in plan.cells) {
      if (!_railable(cx(c), cy(c))) return 'Здесь нельзя класть путь';
    }
    for (final c in plan.cells) {
      rails[c] = 1;
    }
    _spend(cost, 'rails');
    roadVersion++;
    return null;
  }

  /// Takes track away (free), with the stations on it. Not under a train.
  String? removeRail(Iterable<int> cells) {
    final list = cells.where((c) => rails[c] != 0).toList();
    if (list.isEmpty) return 'Здесь нет пути';
    final busy = occupied;
    if (list.any(busy.contains)) return 'Здесь сейчас стоит поезд';
    for (final c in list) {
      rails[c] = 0;
      stations.remove(c);
    }
    roadVersion++;
    return null;
  }

  /// Places a station at [cell] could serve (nearest first).
  List<MagIndustry> stationTargets(int cell) {
    final x = cx(cell), y = cy(cell);
    const r = MagRules.stationReach;
    final out = <MagIndustry>{};
    for (var yy = y - r; yy <= y + r; yy++) {
      for (var xx = x - r; xx <= x + r; xx++) {
        final i = map.industryAt(xx, yy);
        if (i != null && i.kind != MagIndustryKind.logisticsCenter) out.add(i);
      }
    }
    return out.toList()..sort(
      (a, b) => ((a.centerX - x).abs() + (a.centerY - y).abs()).compareTo(
        (b.centerX - x).abs() + (b.centerY - y).abs(),
      ),
    );
  }

  String? stationBlocker(int cell, int placeId) {
    if (!railsUnlocked) {
      return 'Станции откроет технология «Паровая тяга»';
    }
    if (rails[cell] == 0) return 'Станция ставится на путь';
    if (stations.containsKey(cell)) return 'Здесь уже станция';
    if (!stationTargets(cell).any((i) => i.id == placeId)) {
      return 'Станция должна быть в 2 клетках от предприятия';
    }
    return null;
  }

  String? buildStation(int cell, int placeId) {
    final why = stationBlocker(cell, placeId);
    if (why != null) return why;
    if (money < MagRules.stationPrice) {
      return 'Не хватает кредитов: нужно ${MagRules.stationPrice}';
    }
    _spend(
      MagRules.stationPrice,
      'stations',
      source: 'industry',
      sourceId: placeId,
    );
    stations[cell] = placeId;
    roadVersion++;
    _say('Станция у «${map.industry(placeId)?.name}» построена');
    return null;
  }

  String? removeStation(int cell) {
    if (!stations.containsKey(cell)) return 'Здесь нет станции';
    if (occupied.contains(cell)) return 'На станции стоит поезд';
    stations.remove(cell);
    roadVersion++;
    return null;
  }

  /// Station cells serving [i].
  List<int> stationCells(MagIndustry i) => [
    for (final e in stations.entries)
      if (e.value == i.id) e.key,
  ]..sort();

  /// Cells other trains stand on or are about to enter.
  Set<int> _trainCells(MagVehicle except) => {
    for (final t in vehicles.values)
      if (t != except && t.spec.rail && t.onMap) ...{
        t.cell,
        if (t.state == MagVehicleState.driving &&
            t.pathIndex + 1 < t.path.length)
          t.path[t.pathIndex + 1],
      },
  };

  /// The quickest way by rail from any of [from] to a station of [to],
  /// round the cells in [avoid].
  List<int>? railPath(
    List<int> from,
    MagIndustry to, {
    Set<int> avoid = const {},
  }) {
    from = [
      for (final c in from)
        if (rails[c] != 0) c,
    ];
    final goals = stationCells(to).where((c) => !avoid.contains(c)).toSet();
    if (from.isEmpty || goals.isEmpty) return null;
    final gx = cx(goals.first), gy = cy(goals.first);
    return magAStar(
      width: size,
      height: size,
      starts: from,
      isGoal: goals.contains,
      step: (a, b) => rails[b] == 0 || avoid.contains(b) ? null : 1,
      heuristic: (c) => ((cx(c) - gx).abs() + (cy(c) - gy).abs()).toDouble(),
    );
  }

  /// Are two places joined by rail (station to station)?
  bool railConnected(MagIndustry a, MagIndustry b) =>
      railPath(stationCells(a), b) != null;

  // ---- What the simulation asks, for trucks and trains alike ----

  /// Where a vehicle stops at a place: its gate for trucks, its stations
  /// for trains.
  List<int> _stopCells(MagVehicle v, MagIndustry i) =>
      v.spec.rail ? stationCells(i) : accessCells(i);

  /// Is [cell] a stop of [i] for this vehicle?
  bool _atPlace(MagVehicle v, int cell, MagIndustry i) =>
      v.spec.rail ? stations[cell] == i.id : _touches(cell, i);

  List<int>? _pathFor(MagVehicle v, List<int> from, MagIndustry to) =>
      v.spec.rail
      ? railPath(from, to, avoid: v.blocked > 0 ? _trainCells(v) : const {})
      : roadPath(from, to);

  /// Trains: may it enter [next] now? (Another train there: it waits, and
  /// after a while plans round it.)
  bool _trackClear(MagVehicle v, int next) {
    if (!v.spec.rail) return true;
    if (!_trainCells(v).contains(next)) {
      v.blocked = 0;
      return true;
    }
    v.blocked++;
    if (v.blocked % MagRules.trainWaitTicks != 0) return false;
    // First a way round the trains in the way, if the track has one
    // (a second track, a passing place, another platform).
    final target = _target(v);
    if (target != null) {
      final round = railPath([v.cell], target, avoid: _trainCells(v));
      if (round != null && round.length > 1) {
        v
          ..path = round
          ..pathIndex = 0
          ..progress = 0;
        return false;
      }
    }
    final other = vehicles.values
        .where((t) => t != v && t.spec.rail && t.onMap && t.cell == next)
        .firstOrNull;
    // Head to head on one track with no way round (the other wants this
    // cell): the train away from a station — or, both away, the newer one
    // — gives way. It goes back to its previous stop, so nothing stands
    // still for ever; a second track lets both work.
    final facing =
        other != null && other.path.indexOf(v.cell) > other.pathIndex;
    if (facing &&
        v.routeId != null &&
        !stations.containsKey(v.cell) &&
        (stations.containsKey(other.cell) || v.id > other.id)) {
      final n = routes[v.routeId]!.stops.length;
      v
        ..stop = (v.stop - 1 + n) % n
        ..blocked = 0
        ..yields += 1;
      _say('${v.name} уступает путь ${other.name}');
      _plan(v);
    }
    return false;
  }

  /// Why a train cannot run [routeId] (null: it can).
  String? railRouteBlocker(int routeId) {
    final r = routes[routeId];
    if (r == null) return null;
    for (final id in r.stops) {
      final i = map.industry(id);
      if (i == null || stationCells(i).isEmpty) {
        return 'У «${i?.name ?? '—'}» нет станции';
      }
    }
    return null;
  }
}
