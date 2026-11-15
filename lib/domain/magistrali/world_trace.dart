part of 'world.dart';

/// Stage S26: free-form building (VIS-04). Roads and track follow any line
/// the player draws — straight at any angle between two taps, or a curve
/// traced with a finger — instead of the cheapest blocky way. Underneath
/// they still lie on cells (vehicles, saves and every rule stay the same);
/// the map draws them as smooth lines.
extension MagWorldTrace on MagWorld {
  /// The cells a straight line from (sx, sy) to (ex, ey) passes, joined
  /// side to side (no diagonal gaps), as close to the line as cells go.
  List<int> lineCells(int sx, int sy, int ex, int ey) {
    final nx = (ex - sx).abs(), ny = (ey - sy).abs();
    final stepX = ex >= sx ? 1 : -1, stepY = ey >= sy ? 1 : -1;
    var x = sx, y = sy, ix = 0, iy = 0;
    final out = [cellOf(x, y)];
    while (ix < nx || iy < ny) {
      final tx = nx == 0 ? double.infinity : (.5 + ix) / nx;
      final ty = ny == 0 ? double.infinity : (.5 + iy) / ny;
      if (tx < ty) {
        x += stepX;
        ix++;
      } else {
        y += stepY;
        iy++;
      }
      out.add(cellOf(x, y));
    }
    return out;
  }

  /// A straight road at any angle; where the line is blocked (water
  /// without bridges, a place, a closed region) that piece goes round by
  /// the usual planner.
  MagRoadPlan planRoadLine(int sx, int sy, int ex, int ey, MagRoad type) {
    if (!roadUnlocked(type)) {
      return MagRoadPlan(const [], 0, type, 'Покрытие откроется позже');
    }
    final cells = lineCells(sx, sy, ex, ey);
    final free = cells.every(
      (c) => map.roadable(cx(c), cy(c)) && regionOpen(cx(c), cy(c)),
    );
    if (!free) return planRoad(sx, sy, ex, ey, type);
    return MagRoadPlan(
      cells,
      cells.fold(0, (s, c) => s + cellCost(c, type)),
      type,
    );
  }

  /// Straight track at any angle (round obstacles as usual).
  MagRoadPlan planRailLine(int sx, int sy, int ex, int ey) {
    if (!railsUnlocked) return planRail(sx, sy, ex, ey);
    final cells = lineCells(sx, sy, ex, ey);
    if (!cells.every((c) => _railable(cx(c), cy(c)))) {
      return planRail(sx, sy, ex, ey);
    }
    return MagRoadPlan(
      cells,
      cells.fold(0, (s, c) => s + railCellCost(c)),
      MagRoad.none,
    );
  }

  /// A way traced through [points] (cells under the finger, in order):
  /// straight pieces between them, joined into one plan.
  MagRoadPlan planTrace(List<int> points, {MagRoad? road}) {
    final pts = <int>[];
    for (final c in points) {
      if (pts.isEmpty || pts.last != c) pts.add(c);
    }
    if (pts.length < 2) {
      return MagRoadPlan(
        pts,
        0,
        road ?? MagRoad.none,
        'Проведите пальцем подальше',
      );
    }
    // Thin the finger's trace: a point every few cells is enough for the
    // shape, and the straight pieces between them keep it smooth.
    final keep = <int>[pts.first];
    for (final c in pts.skip(1)) {
      final l = keep.last;
      if ((cx(c) - cx(l)).abs() + (cy(c) - cy(l)).abs() >= 3) keep.add(c);
    }
    if (keep.last != pts.last) keep.add(pts.last);
    MagRoadPlan? plan;
    for (var i = 0; i + 1 < keep.length; i++) {
      final a = keep[i], b = keep[i + 1];
      final piece = road == null
          ? planRailLine(cx(a), cy(a), cx(b), cy(b))
          : planRoadLine(cx(a), cy(a), cx(b), cy(b), road);
      if (piece.error != null) return piece;
      plan = plan == null ? piece : joinPlans(plan, piece);
    }
    return plan!;
  }
}
