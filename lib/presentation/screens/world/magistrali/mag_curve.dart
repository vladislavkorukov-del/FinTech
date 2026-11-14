import 'dart:math' as math;
import 'dart:ui';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_iso.dart';

/// Smooth ways (stage S10 visuals): a road, track or a vehicle's way runs
/// from the middle of one cell edge to the next, bending through the cell
/// centre — so a corner is a curve and a staircase of cells reads as a
/// smooth diagonal. Vehicles ride the very same curves.

/// A piece of a way inside one cell: a straight line or a curve bending
/// through [c] (ground coordinates, a cell is 1×1).
class WaySeg {
  const WaySeg(this.a, this.b, [this.c]);
  final Offset a, b;
  final Offset? c;

  void addTo(Path p) {
    p.moveTo(a.dx, a.dy);
    final k = c;
    if (k == null) {
      p.lineTo(b.dx, b.dy);
    } else {
      p.quadraticBezierTo(k.dx, k.dy, b.dx, b.dy);
    }
  }

  /// The same piece moved sideways by [d] (to the left of its way).
  WaySeg offset(double d) {
    Offset n(Offset from, Offset to) {
      final v = to - from;
      final l = v.distance;
      return l == 0 ? Offset.zero : Offset(-v.dy / l, v.dx / l) * d;
    }

    final k = c;
    if (k == null) {
      final o = n(a, b);
      return WaySeg(a + o, b + o);
    }
    final na = n(a, k), nb = n(k, b);
    return WaySeg(a + na, b + nb, k + (na + nb));
  }
}

/// The pieces of a way in cell (x, y) joining the neighbours in [mask]
/// (a bit per MagDir).
List<WaySeg> cellWay(int x, int y, int mask) {
  final ctr = Offset(x + .5, y + .5);
  Offset edge(int d) => ctr + Offset(MagDir.dx[d] * .5, MagDir.dy[d] * .5);
  final arms = [
    for (var d = 0; d < 4; d++)
      if (mask & (1 << d) != 0) d,
  ];
  if (arms.isEmpty) {
    return [WaySeg(ctr - const Offset(.2, 0), ctr + const Offset(.2, 0))];
  }
  if (arms.length == 1) return [WaySeg(ctr, edge(arms[0]))];
  if (arms.length == 2) {
    final (p, q) = (arms[0], arms[1]);
    if ((p - q).abs() == 2) return [WaySeg(edge(p), edge(q))];
    return [WaySeg(edge(p), edge(q), ctr)];
  }
  return [for (final d in arms) WaySeg(ctr, edge(d))];
}

Path _path(List<WaySeg> segs) {
  final p = Path();
  for (final s in segs) {
    s.addTo(p);
  }
  return p;
}

/// A dashed copy of [src].
Path dashed(Path src, double dash, double gap) {
  final out = Path();
  for (final m in src.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      out.addPath(m.extractPath(d, math.min(d + dash, m.length)), Offset.zero);
      d += dash + gap;
    }
  }
  return out;
}

/// A road cell, curved (under the ground transform).
void paintRoadCurved(Canvas c, MagRoad r, int mask, int x, int y, bool bridge) {
  final w = switch (r) {
    MagRoad.dirt => .4,
    MagRoad.asphalt => .46,
    MagRoad.highway => .56,
    MagRoad.motorway => .66,
    MagRoad.none => 0.0,
  };
  final base = switch (r) {
    MagRoad.dirt => const Color(0xFFC8A06A),
    MagRoad.asphalt => const Color(0xFF5E666C),
    MagRoad.highway => const Color(0xFF545B61),
    MagRoad.motorway => const Color(0xFF4A5056),
    MagRoad.none => const Color(0x00000000),
  };
  final edge = switch (r) {
    MagRoad.dirt => const Color(0xFFA9824F),
    MagRoad.highway => const Color(0xFFE9C64B),
    _ => const Color(0xFFC9CFD2),
  };
  final path = _path(cellWay(x, y, mask));
  Paint stroke(Color col, double width, {StrokeCap cap = StrokeCap.round}) =>
      Paint()
        ..style = PaintingStyle.stroke
        ..color = col
        ..strokeWidth = width
        ..strokeCap = cap
        ..strokeJoin = StrokeJoin.round;
  if (bridge) c.drawPath(path, stroke(const Color(0xFFE6E0D2), w + .2));
  c.drawPath(path, stroke(edge, w + .07));
  c.drawPath(path, stroke(base, w));
  if (r == MagRoad.dirt) {
    // Wheel ruts.
    for (final s in cellWay(x, y, mask)) {
      for (final d in [-.09, .09]) {
        final p = Path();
        s.offset(d).addTo(p);
        c.drawPath(p, stroke(const Color(0x22000000), .025));
      }
    }
  } else {
    c.drawPath(
      dashed(path, .12, .12),
      stroke(const Color(0xCCFFFFFF), .03, cap: StrokeCap.butt),
    );
  }
}

/// A cell of track, curved: ballast, sleepers across, two steel rails
/// (under the ground transform). A station cell gets a platform.
void paintRailCurved(Canvas c, int mask, int x, int y, {bool station = false}) {
  if (station) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + .04, y + .04, .92, .92),
        const Radius.circular(.08),
      ),
      Paint()..color = const Color(0xFFD9D4C7),
    );
  }
  final segs = cellWay(x, y, mask == 0 ? 0xA : mask);
  final path = _path(segs);
  Paint stroke(Color col, double width, {StrokeCap cap = StrokeCap.round}) =>
      Paint()
        ..style = PaintingStyle.stroke
        ..color = col
        ..strokeWidth = width
        ..strokeCap = cap;
  c.drawPath(path, stroke(const Color(0xFF9C9488), .4));
  c.drawPath(
    dashed(path, .06, .1),
    stroke(const Color(0xFF6E4E35), .34, cap: StrokeCap.butt),
  );
  for (final s in segs) {
    for (final d in [-.1, .1]) {
      final p = Path();
      s.offset(d).addTo(p);
      c.drawPath(p, stroke(const Color(0xFF59606A), .045));
    }
  }
}

/// The middle of the edge between two cells (or the cell centre when there
/// is no other cell), in cell coordinates.
Offset _mid(MagWorld w, int? a, int b) {
  final bx = w.cx(b) + .5, by = w.cy(b) + .5;
  if (a == null) return Offset(bx, by);
  return Offset((w.cx(a) + .5 + bx) / 2, (w.cy(a) + .5 + by) / 2);
}

/// A point on a vehicle's way at [s] (cell index along [path] plus the
/// part of the way to the next cell), and the heading there.
(Offset, Offset) poseAlong(MagWorld w, List<int> path, double s) {
  if (path.isEmpty) return (Offset.zero, const Offset(1, 0));
  s = s.clamp(0, (path.length - 1).toDouble());
  var i = s.floor();
  var f = s - i;
  if (i >= path.length - 1) {
    i = path.length - 1;
    f = 0;
  }
  // The curve of cell k runs from mid(k-1,k) through the centre of k to
  // mid(k,k+1); f < .5 is the second half of cell i, the rest the first
  // half of cell i+1.
  final k = f < .5 ? i : i + 1;
  final t = f < .5 ? .5 + f : f - .5;
  final prev = k > 0 ? path[k - 1] : null;
  final next = k + 1 < path.length ? path[k + 1] : null;
  final a = _mid(w, prev, path[k]);
  final b = next == null
      ? Offset(w.cx(path[k]) + .5, w.cy(path[k]) + .5)
      : _mid(w, next, path[k]);
  final ctr = Offset(w.cx(path[k]) + .5, w.cy(path[k]) + .5);
  final u = 1 - t;
  final p = a * (u * u) + ctr * (2 * u * t) + b * (t * t);
  var d = (ctr - a) * (2 * u) + (b - ctr) * (2 * t);
  if (d.distance < 1e-6) d = b - a;
  if (d.distance < 1e-6) d = const Offset(1, 0);
  return (p, d / d.distance);
}

/// Where a vehicle is drawn, on the curve of its way, and its heading.
(Offset, Offset) vehiclePose(MagWorld w, MagVehicle v, {double back = 0}) {
  final driving =
      v.state == MagVehicleState.driving && v.pathIndex + 1 < v.path.length;
  if (!driving) {
    final (x, y) = w.positionOf(v);
    final d = Offset(MagDir.dx[v.dir].toDouble(), MagDir.dy[v.dir].toDouble());
    return (Offset(x, y) - d * back, d);
  }
  return poseAlong(w, v.path, v.pathIndex + v.progress - back);
}

/// The four-way direction nearest to [d] (for sprites and boxes).
int dirOf(Offset d) =>
    d.dx.abs() > d.dy.abs() ? (d.dx > 0 ? 1 : 3) : (d.dy > 0 ? 2 : 0);

/// A dashed line along a vehicle's way ahead (screen coordinates through
/// [MagIso.project]); [from] is where along the path it starts.
Path wayAhead(MagWorld w, List<int> path, double from) {
  final p = Path();
  if (path.length < 2) return p;
  var first = true;
  for (var s = from; s <= path.length - 1 + 1e-6; s += .25) {
    final (pt, _) = poseAlong(w, path, s);
    final q = MagIso.project(pt.dx, pt.dy);
    if (first) {
      p.moveTo(q.dx, q.dy);
      first = false;
    } else {
      p.lineTo(q.dx, q.dy);
    }
  }
  return p;
}
