part of 'world.dart';

/// Stage S28: bridges over lakes and overpasses (BRG-01), interchanges of
/// every kind (JCT-02: overpass, cloverleaf, roundabout), removing a whole
/// curve (VIS-07), street trams (TRAM-02).
///
/// A way may pass over cells: a lake, or — built as an overpass — roads
/// and track it crosses. Those cells are not part of it; vehicles cross
/// them by a link from the cell before to the cell after, and side-by-side
/// steps between the way and the cells under it are cut, so an overpass
/// never joins the road beneath.
extension MagWorldSpans on MagWorld {
  /// What a way over [cells] passes over (null: a span too long). Ends
  /// are never passed over.
  Set<int>? spansOf(List<int> cells, {required bool rail, bool over = false}) {
    final out = <int>{};
    var run = 0;
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      final inner = i > 0 && i < cells.length - 1;
      final lake = map.at(cx(c), cy(c)) == MagTerrain.lake;
      final crossing =
          over &&
          (roads[c] != 0 || rails[c] != 0) &&
          map.industryAt(cx(c), cy(c)) == null;
      if (inner && (lake || crossing)) {
        out.add(c);
        if (++run > MagRules.maxSpan) return null;
      } else {
        run = 0;
      }
    }
    return out;
  }

  /// A cell of a bridge or an overpass.
  int spanCost(int cell) =>
      (MagRules.spanCost * factor(MagBonus.roadCost) * factor(MagBonus.bridge))
          .round();

  /// Links over bridges and overpasses.
  Map<int, List<int>>? spanLinks({bool rail = false}) {
    if (ways.isEmpty) return null;
    final l = rail ? wayIndex.railLinks : wayIndex.roadLinks;
    return l.isEmpty ? null : l;
  }

  Set<int>? spanCuts({bool rail = false}) {
    if (ways.isEmpty) return null;
    final c = rail ? wayIndex.railCuts : wayIndex.roadCuts;
    return c.isEmpty ? null : c;
  }

  Set<int> _cutsOf(List<MagSpanRun> runs, {required bool rail}) {
    final n = size * size;
    final out = <int>{};
    for (final r in runs) {
      if (r.way.rail != rail) continue;
      for (final s in r.cells) {
        for (var d = 0; d < 4; d++) {
          final x = cx(s) + MagDir.dx[d], y = cy(s) + MagDir.dy[d];
          if (!map.inside(x, y)) continue;
          final o = cellOf(x, y);
          if (!r.foot.contains(o) || r.way.spans.contains(o)) continue;
          out
            ..add(o * n + s)
            ..add(s * n + o);
        }
      }
    }
    return out;
  }

  /// How many cells a step covers (a link over a bridge: its length).
  double _hop(int a, int b) {
    final d = (cx(a) - cx(b)).abs() + (cy(a) - cy(b)).abs();
    return d <= 1 ? 1 : d.toDouble();
  }

  /// The points of the curve between [a] and [b] over a bridge (empty: no
  /// bridge there).
  List<MagPt> spanPoints(int a, int b) {
    if (ways.isEmpty) return const [];
    for (final r in wayIndex.runs) {
      if (r.a == a && r.b == b) return r.pts.sublist(1, r.pts.length - 1);
      if (r.a == b && r.b == a) {
        return r.pts.sublist(1, r.pts.length - 1).reversed.toList();
      }
    }
    return const [];
  }

  /// Builds a plan that passes over cells (only its own cells are laid).
  String? _buildSpanned(MagRoadPlan plan, {required bool rail}) {
    final spans = plan.spans!;
    if (plan.error != null) return plan.error;
    if (plan.cost > money) return 'Не хватает кредитов: нужно ${plan.cost}';
    final own = [
      for (final c in plan.cells)
        if (!spans.contains(c)) c,
    ];
    for (final c in own) {
      final ok = rail
          ? _railable(cx(c), cy(c))
          : map.roadable(cx(c), cy(c)) && regionOpen(cx(c), cy(c));
      if (!ok) {
        return rail ? 'Здесь нельзя класть путь' : 'Здесь нельзя строить';
      }
    }
    for (final c in own) {
      if (rail) {
        rails[c] = 1;
      } else if (roads[c] < plan.type.index) {
        roads[c] = plan.type.index;
      }
    }
    if (!rail) _noteEntrances(own);
    _keepWay(plan, rail: rail);
    _spend(plan.cost, rail ? 'rails' : 'roads');
    roadVersion++;
    _say(
      spans.any((c) => map.at(cx(c), cy(c)) == MagTerrain.lake)
          ? 'Мост через озеро построен'
          : 'Эстакада построена: проходит над дорогой без съезда',
    );
    return null;
  }

  /// The way by road from one road cell to another, over bridges and
  /// overpasses as vehicles go (null: not joined).
  List<int>? roadPathCells(int from, int to) {
    if (!roadOpen(from) || !roadOpen(to)) return null;
    final tx = cx(to), ty = cy(to);
    return magAStar(
      width: size,
      height: size,
      start: from,
      isGoal: (c) => c == to,
      step: (a, b) => roadOpen(b) ? 1 : null,
      heuristic: (c) => ((cx(c) - tx).abs() + (cy(c) - ty).abs()) * .5,
      links: spanLinks(),
      cuts: spanCuts(),
    );
  }

  // ---- VIS-07: a whole curve ----

  /// The free way through [cell] (null: none).
  MagWay? wayAt(int cell, {bool rail = false}) {
    if (ways.isEmpty) return null;
    final idx = wayIndex;
    for (var k = 0; k < idx.ways.length; k++) {
      final w = idx.ways[k];
      if (w.rail != rail || w.spans.contains(cell)) continue;
      if (idx.lays[k].cells.contains(cell)) return w;
    }
    return null;
  }

  /// Takes a whole curve away (its own cells that no other curve needs).
  String? removeWayAt(int cell, {bool rail = false}) {
    final w = wayAt(cell, rail: rail);
    if (w == null) return 'Здесь нет кривой';
    final idx = wayIndex;
    final k = idx.ways.indexOf(w);
    final others = <int>{};
    for (var o = 0; o < idx.ways.length; o++) {
      if (o == k || idx.ways[o].rail != rail) continue;
      others.addAll(idx.lays[o].cells);
    }
    final cells = [
      for (final c in idx.lays[k].cells)
        if (!w.spans.contains(c) && !others.contains(c)) c,
    ];
    final why = rail ? removeRail(cells) : removeRoad(cells);
    if (why != null) return why;
    ways.remove(w);
    _wayIndex = null;
    roadVersion++;
    return null;
  }

  // ---- JCT-02: interchanges ----

  bool _arms(int cell, [int reach = 2]) {
    final x = cx(cell), y = cy(cell);
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      for (var k = 1; k <= reach; k++) {
        if (!hasRoad(x + dx * k, y + dy * k)) return false;
      }
    }
    return roads[cell] != 0;
  }

  /// Why an interchange of [kind] cannot be built at [cell] (null: it can).
  String? junctionBlocker(int cell, MagJunction kind) {
    if (!interchangesUnlocked) return 'Развязки откроет технология «Развязки»';
    final reach = kind.big ? 4 : 2;
    if (!_arms(cell, reach)) {
      return 'Нужен перекрёсток: дороги на $reach клетки во все четыре стороны';
    }
    if (ways.isNotEmpty &&
        wayIndex.runs.any((r) => r.cells.contains(cell) && !r.way.rail)) {
      return 'Здесь уже эстакада';
    }
    if (money < junctionPrice(kind)) {
      return 'Не хватает кредитов: нужно ${junctionPrice(kind)}';
    }
    return null;
  }

  int junctionPrice(MagJunction kind) => switch (kind) {
    MagJunction.overpass => MagRules.overpassPrice,
    MagJunction.clover => MagRules.cloverPrice,
    MagJunction.turbine => MagRules.turbinePrice,
    MagJunction.stack => MagRules.stackPrice,
    MagJunction.roundabout => MagRules.roundaboutPrice,
  };

  /// Builds an interchange at a crossing: an overpass (one road over the
  /// other), a cloverleaf (an overpass and four ramps between them) or a
  /// roundabout (a ring round an island).
  String? buildJunction(int cell, MagJunction kind) {
    final why = junctionBlocker(cell, kind);
    if (why != null) return why;
    final x = cx(cell), y = cy(cell);
    final mx = x + .5, my = y + .5;
    // The better road goes over.
    final ew = math.max(roads[cellOf(x - 1, y)], roads[cellOf(x + 1, y)]);
    final ns = math.max(roads[cellOf(x, y - 1)], roads[cellOf(x, y + 1)]);
    final alongX = ew >= ns;
    final top = MagRoad.values[math.max(ew, ns)];
    // Pieces are laid at their own prices (in the journal as roads); the
    // interchange's own price is paid at the end.
    money += 1 << 30;
    String? fail;
    void lay(
      List<MagPt> pts,
      MagRoad r, {
      bool over = false,
      bool rail = false,
    }) {
      if (fail != null) return;
      final plan = planWay(pts, road: r, over: over, thin: false);
      if (plan.error != null) {
        fail = plan.error;
        return;
      }
      final spans = plan.spans;
      final built = spans != null && spans.isNotEmpty
          ? _buildSpanned(plan, rail: false)
          : plan.cost == 0
          ? (() {
              _keepWay(plan, rail: false);
              roadVersion++;
              return null;
            })()
          : buildRoad(plan);
      if (built != null) fail = built;
    }

    switch (kind) {
      case MagJunction.overpass:
      case MagJunction.clover:
      case MagJunction.turbine:
      case MagJunction.stack:
        _dropWaysAt(cell);
        // The upper road: over the crossing only.
        final a = alongX ? (mx - 2, my) : (mx, my - 2);
        final b = alongX ? (mx + 2, my) : (mx, my + 2);
        final l = layCurve(wayCurve([a, b]));
        fail = _buildSpanned(
          MagRoadPlan(l.cells, 0, top, null, [a, b], {cell}),
          rail: false,
        );
        _ramps(
          kind,
          mx,
          my,
          MagRoad.values[math.max(1, math.min(ew, ns))],
          lay,
        );
      case MagJunction.roundabout:
        _dropWaysAt(cell);
        // The island: the crossing and the cells round it.
        for (final (dx, dy) in const [
          (0, 0),
          (1, 0),
          (-1, 0),
          (0, 1),
          (0, -1),
        ]) {
          roads[cellOf(x + dx, y + dy)] = 0;
        }
        roadVersion++;
        final ring = [
          for (var k = 0; k <= 12; k++)
            (
              mx + 1.6 * math.cos(k * math.pi / 6),
              my + 1.6 * math.sin(k * math.pi / 6),
            ),
        ];
        lay(ring, top);
    }
    money -= 1 << 30;
    roadVersion++;
    if (fail != null) return fail;
    _spend(junctionPrice(kind), 'roads');
    _say(switch (kind) {
      MagJunction.overpass => 'Эстакада: дороги разведены по уровням',
      MagJunction.clover => 'Клеверная развязка построена: четыре петли',
      MagJunction.turbine => 'Развязка «турбина» построена',
      MagJunction.stack => 'Трёхуровневая развязка построена',
      MagJunction.roundabout => 'Кольцевая развязка построена',
    });
    return null;
  }

  /// The ramps of an interchange (S29), in each quarter between arms at
  /// angles θ and θ + 90°:
  /// * clover — a real loop: off one road, round 270° and onto the other;
  /// * turbine — a sweeping blade that dips towards the centre;
  /// * stack — a flyover that passes over the crossing itself, above the
  ///   overpass: the third level.
  void _ramps(
    MagJunction kind,
    double mx,
    double my,
    MagRoad r,
    void Function(List<MagPt>, MagRoad, {bool over, bool rail}) lay,
  ) {
    if (!kind.big) return;
    MagPt polar(double deg, double rad) => (
      mx + rad * math.cos(deg * math.pi / 180),
      my + rad * math.sin(deg * math.pi / 180),
    );
    for (var q = 0; q < 4; q++) {
      final t = q * 90.0;
      switch (kind) {
        case MagJunction.clover:
          // The loop's centre sits in the quarter, clear of both roads.
          final c = polar(t + 45, 4.1);
          final start = polar(t, 4.4), end = polar(t + 90, 4.4);
          final a0 = math.atan2(start.$2 - c.$2, start.$1 - c.$1);
          final pts = <MagPt>[start];
          for (var k = 1; k < 9; k++) {
            // From the start side round 270°, the long way, to the end.
            final a = a0 + math.pi / 4 - k * (1.5 * math.pi) / 9;
            pts.add((c.$1 + 1.35 * math.cos(a), c.$2 + 1.35 * math.sin(a)));
          }
          pts.add(end);
          lay(pts, r);
        case MagJunction.turbine:
          lay([
            polar(t, 4.4),
            polar(t + 30, 3.2),
            polar(t + 55, 2.5),
            polar(t + 78, 3.0),
            polar(t + 90, 4.4),
          ], r);
        case MagJunction.stack:
          lay(
            [
              polar(t, 4.4),
              polar(t + 20, 2.4),
              polar(t + 45, .45),
              polar(t + 70, 2.4),
              polar(t + 90, 4.4),
            ],
            r,
            over: true,
          );
        case MagJunction.overpass:
        case MagJunction.roundabout:
          break;
      }
    }
  }

  /// Curves through [cell] give way to an interchange's new shape (their
  /// cells stay, drawn as before).
  void _dropWaysAt(int cell) {
    if (ways.isEmpty) return;
    final idx = wayIndex;
    final drop = <MagWay>{
      for (var k = 0; k < idx.ways.length; k++)
        if (!idx.ways[k].rail && idx.lays[k].cells.contains(cell)) idx.ways[k],
    };
    ways.removeWhere(drop.contains);
    _wayIndex = null;
  }

  // ---- TRAM-02 ----

  /// Streets the trams run along: the roads of their routes (between
  /// settlements), worked out from the routes.
  Set<int> tramStreets() {
    final out = <int>{};
    for (final v in vehicles.values) {
      if (v.spec.body != 'tram') continue;
      final r = routes[v.routeId];
      if (r == null || r.stops.length < 2) continue;
      for (var i = 0; i < r.stops.length; i++) {
        final a = map.industry(r.stops[i]);
        final b = map.industry(r.stops[(i + 1) % r.stops.length]);
        if (a == null || b == null) continue;
        out.addAll(roadPath(accessCells(a), b) ?? const []);
      }
    }
    return out;
  }

  /// Trams between big settlements earn more (street lines).
  double tramFactor(MagVehicle v) {
    if (v.spec.body != 'tram') return 1;
    final r = routes[v.routeId];
    if (r == null) return 1;
    final big = r.stops.every(
      (id) => (map.industry(id)?.town?.level ?? 0) >= MagRules.tramTownLevel,
    );
    return big ? MagRules.tramStreetPay : 1;
  }
}

/// Kinds of interchange (JCT-02, S29: turbine and stack).
enum MagJunction {
  overpass,
  clover,
  turbine,
  stack,
  roundabout;

  /// Needs long arms (ramps reach four cells out).
  bool get big => this == clover || this == turbine || this == stack;
}
