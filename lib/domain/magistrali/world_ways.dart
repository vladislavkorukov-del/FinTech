part of 'world.dart';

/// A point of the free map (cell units, fractions allowed).
typedef MagPt = (double, double);

/// A road or a track laid along a free curve (S27, VIS-05): the points the
/// player drew. The map draws it and vehicles ride it exactly as drawn;
/// underneath, the cells it passes are its footprint, so every rule that
/// asks about roads (entrances, routes, prices, depots, stations) still
/// works the same.
class MagWay {
  MagWay(this.pts, this.road, {this.rail = false, Set<int>? spans})
    : spans = spans ?? {};
  final List<MagPt> pts;
  MagRoad road;
  final bool rail;

  /// S28: cells it passes over (a lake, another road or track) — not
  /// part of its footprint; vehicles cross them by a link.
  final Set<int> spans;
}

/// A way's footprint and the point of the curve in each of its cells.
class MagWayLay {
  MagWayLay(this.curve, this.cells, this.anchors);
  final List<MagPt> curve;
  final List<int> cells;
  final Map<int, MagPt> anchors;
}

/// The live ways, their footprints and the anchors of every cell (worked
/// out again only when the network changes).
class MagWayIndex {
  MagWayIndex(this.ways, this.lays, this.anchors, this.covered);
  final List<MagWay> ways;
  final List<MagWayLay> lays;
  final Map<int, MagPt> anchors;

  /// Cells under a way (road ways and track ways apart).
  final Set<int> covered;

  /// S28: links over bridges and overpasses, and the runs they cross.
  Map<int, List<int>> roadLinks = const {}, railLinks = const {};
  List<MagSpanRun> runs = const [];
  Set<int> roadCuts = const {}, railCuts = const {};
}

/// A bridge or an overpass: from cell [a] over [cells] to cell [b], along
/// the points of its curve.
class MagSpanRun {
  MagSpanRun(this.way, this.a, this.b, this.foot, this.pts, this.cells);
  final MagWay way;
  final int a, b;

  /// The way's whole footprint.
  final Set<int> foot;
  final List<MagPt> pts;
  final List<int> cells;
}

extension MagWorldWays on MagWorld {
  /// A smooth curve through [pts] (Catmull–Rom), sampled finely.
  List<MagPt> wayCurve(List<MagPt> pts) {
    if (pts.length < 2) return pts;
    if (pts.length == 2) {
      final (ax, ay) = pts[0];
      final (bx, by) = pts[1];
      final n = math.max(
        2,
        (math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)) * 8).ceil(),
      );
      return [
        for (var i = 0; i <= n; i++)
          (ax + (bx - ax) * i / n, ay + (by - ay) * i / n),
      ];
    }
    final out = <MagPt>[];
    for (var i = 0; i + 1 < pts.length; i++) {
      final p0 = pts[math.max(0, i - 1)], p1 = pts[i];
      final p2 = pts[i + 1], p3 = pts[math.min(pts.length - 1, i + 2)];
      final len = math.sqrt(
        (p2.$1 - p1.$1) * (p2.$1 - p1.$1) + (p2.$2 - p1.$2) * (p2.$2 - p1.$2),
      );
      final n = math.max(2, (len * 8).ceil());
      for (var k = 0; k < n; k++) {
        final t = k / n, t2 = t * t, t3 = t2 * t;
        double f(double a, double b, double c, double d) =>
            .5 *
            (2 * b +
                (-a + c) * t +
                (2 * a - 5 * b + 4 * c - d) * t2 +
                (-a + 3 * b - 3 * c + d) * t3);
        out.add((f(p0.$1, p1.$1, p2.$1, p3.$1), f(p0.$2, p1.$2, p2.$2, p3.$2)));
      }
    }
    out.add(pts.last);
    return out;
  }

  /// The cells a curve passes, joined side to side (where it cuts a corner
  /// the nearer of the two side cells joins them), and the point of the
  /// curve nearest each cell's centre.
  MagWayLay layCurve(List<MagPt> curve) {
    final cells = <int>[];
    final seen = <int>{};
    final anchors = <int, MagPt>{};
    final best = <int, double>{};
    void note(int x, int y, MagPt p) {
      if (!map.inside(x, y)) return;
      final c = cellOf(x, y);
      if (seen.add(c)) cells.add(c);
      final d =
          (p.$1 - x - .5) * (p.$1 - x - .5) + (p.$2 - y - .5) * (p.$2 - y - .5);
      if (d < (best[c] ?? double.infinity)) {
        best[c] = d;
        anchors[c] = p;
      }
    }

    int? lx, ly;
    for (final p in curve) {
      final x = p.$1.floor(), y = p.$2.floor();
      if (lx != null && ly != null && x != lx && y != ly) {
        // A corner cut: step through the side cell nearer the curve.
        final ax = x + .5 - p.$1, ay = ly + .5 - p.$2;
        final bx = lx + .5 - p.$1, by = y + .5 - p.$2;
        if (ax * ax + ay * ay <= bx * bx + by * by) {
          note(x, ly, p);
        } else {
          note(lx, y, p);
        }
      }
      note(x, y, p);
      lx = x;
      ly = y;
    }
    return MagWayLay(curve, cells, anchors);
  }

  /// Ends that fall near the network snap onto it, so ways join cleanly.
  MagPt _snap(MagPt p, bool rail) {
    final x0 = p.$1.floor(), y0 = p.$2.floor();
    MagPt? best;
    var bestD = 1.1 * 1.1;
    for (var y = y0 - 1; y <= y0 + 1; y++) {
      for (var x = x0 - 1; x <= x0 + 1; x++) {
        if (!map.inside(x, y)) continue;
        final c = cellOf(x, y);
        if (rail ? rails[c] == 0 : roads[c] == 0) continue;
        final q = wayIndex.anchors[c] ?? (x + .5, y + .5);
        final d = (q.$1 - p.$1) * (q.$1 - p.$1) + (q.$2 - p.$2) * (q.$2 - p.$2);
        if (d < bestD) {
          bestD = d;
          best = q;
        }
      }
    }
    return best ?? p;
  }

  /// A way along the points the player drew (a finger's trace or two
  /// taps), as a plan: its footprint and price. [road] null: track.
  MagRoadPlan planWay(List<MagPt> drawn, {MagRoad? road, bool over = false}) {
    final rail = road == null;
    final type = road ?? MagRoad.none;
    if (rail ? !railsUnlocked : !roadUnlocked(type)) {
      return MagRoadPlan(
        const [],
        0,
        type,
        rail
            ? 'Железные дороги откроет технология «Паровая тяга»'
            : 'Покрытие откроется позже',
      );
    }
    // Thin the trace: a point every cell and a half keeps its shape.
    final pts = <MagPt>[];
    for (final p in drawn) {
      if (pts.isEmpty) {
        pts.add(p);
        continue;
      }
      final l = pts.last;
      final d = math.sqrt(
        (p.$1 - l.$1) * (p.$1 - l.$1) + (p.$2 - l.$2) * (p.$2 - l.$2),
      );
      if (d >= 1.5) pts.add(p);
    }
    if (drawn.isNotEmpty && pts.last != drawn.last) {
      final l = pts.last, e = drawn.last;
      if ((e.$1 - l.$1).abs() + (e.$2 - l.$2).abs() > .6) {
        pts.add(e);
      } else if (pts.length > 1) {
        pts[pts.length - 1] = e;
      }
    }
    if (pts.length < 2) {
      return MagRoadPlan(
        pts.isEmpty ? const [] : [_cellOfPt(pts.first)],
        0,
        type,
        'Проведите подальше',
      );
    }
    pts[0] = _snap(pts.first, rail);
    pts[pts.length - 1] = _snap(pts.last, rail);
    final lay = layCurve(wayCurve(pts));
    // S28: what it passes over — a lake (a bridge), and, built as an
    // overpass, roads and track it crosses (no junction with them).
    final spans = spansOf(lay.cells, rail: rail, over: over);
    if (spans == null) {
      return MagRoadPlan(
        lay.cells,
        0,
        type,
        'Пролёт моста длиннее ${MagRules.maxSpan} клеток',
        pts,
      );
    }
    for (final c in lay.cells) {
      if (spans.contains(c)) continue;
      final ok = rail
          ? _railable(cx(c), cy(c))
          : map.roadable(cx(c), cy(c)) && regionOpen(cx(c), cy(c));
      if (!ok) {
        // Two taps across an obstacle: round it by the usual planner and
        // smooth that way into a curve (or keep it as cells).
        if (drawn.length == 2) return _roundObstacle(pts.first, pts.last, road);
        return MagRoadPlan(
          lay.cells,
          0,
          type,
          'Трасса задевает воду, предприятие или закрытый регион',
          pts,
        );
      }
    }
    final cost = lay.cells.fold(
      0,
      (s, c) =>
          s +
          (spans.contains(c)
              ? spanCost(c)
              : rail
              ? railCellCost(c)
              : cellCost(c, type)),
    );
    return MagRoadPlan(
      lay.cells,
      cost,
      type,
      null,
      pts,
      spans.isEmpty ? null : spans,
    );
  }

  MagRoadPlan _roundObstacle(MagPt a, MagPt b, MagRoad? road) {
    final ac = _cellOfPt(a), bc = _cellOfPt(b);
    final base = road == null
        ? planRail(cx(ac), cy(ac), cx(bc), cy(bc))
        : planRoad(cx(ac), cy(ac), cx(bc), cy(bc), road);
    if (base.error != null || base.cells.length < 2) return base;
    // The cells' line, straightened (within ¾ of a cell) into few points.
    final pts = [for (final c in base.cells) (cx(c) + .5, cy(c) + .5)];
    final keep = List<bool>.filled(pts.length, false)
      ..[0] = true
      ..[pts.length - 1] = true;
    void simplify(int i, int j) {
      if (j - i < 2) return;
      final (px, py) = pts[i];
      final (qx, qy) = pts[j];
      final dx = qx - px, dy = qy - py;
      final len = math.sqrt(dx * dx + dy * dy);
      var far = -1.0, at = -1;
      for (var k = i + 1; k < j; k++) {
        final (rx, ry) = pts[k];
        final d = ((rx - px) * dy - (ry - py) * dx).abs() / len;
        if (d > far) {
          far = d;
          at = k;
        }
      }
      if (far > .75) {
        keep[at] = true;
        simplify(i, at);
        simplify(at, j);
      }
    }

    simplify(0, pts.length - 1);
    final shape = [
      for (var k = 0; k < pts.length; k++)
        if (keep[k]) pts[k],
    ];
    final lay = layCurve(wayCurve(shape));
    final clear = lay.cells.every(
      (c) => road == null
          ? _railable(cx(c), cy(c))
          : map.roadable(cx(c), cy(c)) && regionOpen(cx(c), cy(c)),
    );
    if (!clear) return base;
    final cost = lay.cells.fold(
      0,
      (s, c) => s + (road == null ? railCellCost(c) : cellCost(c, road)),
    );
    return MagRoadPlan(lay.cells, cost, base.type, null, shape);
  }

  int _cellOfPt(MagPt p) =>
      cellOf(p.$1.floor().clamp(0, size - 1), p.$2.floor().clamp(0, size - 1));

  /// After a plan with a shape is built: the way is kept.
  void _keepWay(MagRoadPlan plan, {required bool rail}) {
    final s = plan.shape;
    if (s == null || s.length < 2) return;
    ways.add(
      MagWay(List.of(s), plan.type, rail: rail, spans: {...?plan.spans}),
    );
    _wayIndex = null;
  }

  /// The live ways: a way whose footprint lost a cell (removed) is gone;
  /// a road way takes the surface most of its cells have.
  MagWayIndex get wayIndex {
    final key = roadVersion * 31 + ways.length;
    final cached = _wayIndex;
    if (cached != null && _wayKey == key) return cached;
    final lays = <MagWayLay>[];
    final live = <MagWay>[];
    final anchors = <int, MagPt>{};
    final covered = <int>{};
    final roadLinks = <int, List<int>>{}, railLinks = <int, List<int>>{};
    final runs = <MagSpanRun>[];
    for (final w in ways) {
      final lay = layCurve(wayCurve(w.pts));
      final whole = lay.cells.every(
        (c) => w.spans.contains(c) || (w.rail ? rails[c] != 0 : roads[c] != 0),
      );
      if (!whole || lay.cells.isEmpty) continue;
      if (!w.rail) {
        final count = <int, int>{};
        for (final c in lay.cells) {
          if (w.spans.contains(c)) continue;
          count[roads[c]] = (count[roads[c]] ?? 0) + 1;
        }
        final top = count.entries.reduce((a, b) => a.value >= b.value ? a : b);
        w.road = MagRoad.values[top.key];
      }
      live.add(w);
      lays.add(lay);
      for (final e in lay.anchors.entries) {
        if (w.spans.contains(e.key)) continue;
        anchors.putIfAbsent(e.key, () => e.value);
      }
      covered.addAll([
        for (final c in lay.cells)
          if (!w.spans.contains(c)) w.rail ? -1 - c : c,
      ]);
      // Links over each run of passed-over cells.
      final links = w.rail ? railLinks : roadLinks;
      for (var i = 0; i < lay.cells.length; i++) {
        if (!w.spans.contains(lay.cells[i]) || i == 0) continue;
        var j = i;
        while (j < lay.cells.length && w.spans.contains(lay.cells[j])) {
          j++;
        }
        if (j >= lay.cells.length) break;
        final a = lay.cells[i - 1], b = lay.cells[j];
        (links[a] ??= []).add(b);
        (links[b] ??= []).add(a);
        runs.add(
          MagSpanRun(w, a, b, lay.cells.toSet(), [
            lay.anchors[a]!,
            for (var k = i; k < j; k++) lay.anchors[lay.cells[k]]!,
            lay.anchors[b]!,
          ], lay.cells.sublist(i, j)),
        );
        i = j;
      }
    }
    if (live.length != ways.length) {
      ways
        ..clear()
        ..addAll(live);
    }
    _wayKey = roadVersion * 31 + ways.length;
    return _wayIndex = MagWayIndex(live, lays, anchors, covered)
      ..roadLinks = roadLinks
      ..railLinks = railLinks
      ..runs = runs
      ..roadCuts = _cutsOf(runs, rail: false)
      ..railCuts = _cutsOf(runs, rail: true);
  }

  /// Is the road (or, with [rail], the track) in [cell] part of a free way?
  bool onWay(int cell, {bool rail = false}) =>
      ways.isNotEmpty && wayIndex.covered.contains(rail ? -1 - cell : cell);

  /// Where a vehicle passing [cell] is: on the curve of its way, or the
  /// cell's centre.
  MagPt wayPoint(int cell) =>
      (ways.isEmpty ? null : wayIndex.anchors[cell]) ??
      (cx(cell) + .5, cy(cell) + .5);

  // ---- Saves ----

  Map<String, Object> _saveWays() => {
    if (ways.any((w) => w.spans.isNotEmpty))
      'wayspans': [for (final w in ways) w.spans.toList()..sort()],
    if (ways.isNotEmpty)
      'ways': [
        for (final w in ways)
          [
            if (w.rail) 1 else 0,
            w.road.index,
            for (final p in w.pts) ...[
              (p.$1 * 100).round() / 100,
              (p.$2 * 100).round() / 100,
            ],
          ],
      ],
  };

  void loadWays(Map<String, dynamic> j) {
    for (final raw in j['ways'] as List? ?? const []) {
      final l = raw as List;
      if (l.length < 6) continue;
      final pts = <MagPt>[
        for (var i = 2; i + 1 < l.length; i += 2)
          ((l[i] as num).toDouble(), (l[i + 1] as num).toDouble()),
      ];
      final r = (l[1] as int).clamp(0, MagRoad.values.length - 1);
      ways.add(MagWay(pts, MagRoad.values[r], rail: l[0] == 1));
    }
    final spans = j['wayspans'] as List? ?? const [];
    for (var k = 0; k < spans.length && k < ways.length; k++) {
      ways[k].spans.addAll([for (final c in spans[k] as List) c as int]);
    }
    _wayIndex = null;
  }
}
