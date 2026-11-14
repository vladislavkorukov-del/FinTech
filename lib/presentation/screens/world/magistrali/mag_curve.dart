import 'dart:math' as math;
import 'dart:ui';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_iso.dart';

/// Smooth ways (stages S10–S11 visuals): a vehicle rides the same smoothed
/// line as the road under it, evenly along its length (no jerks at
/// corners); dashed lines for the route of the selected vehicle.

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

/// Corner cutting (Chaikin), the ends kept.
List<Offset> smoothLine(List<Offset> pts, {int rounds = 3}) {
  var p = pts;
  for (var r = 0; r < rounds && p.length > 2; r++) {
    final q = <Offset>[p.first];
    for (var i = 0; i + 1 < p.length; i++) {
      final a = p[i], b = p[i + 1];
      q
        ..add(Offset.lerp(a, b, .25)!)
        ..add(Offset.lerp(a, b, .75)!);
    }
    q.add(p.last);
    p = q;
  }
  return p;
}

/// A vehicle's way smoothed like the roads, measured along its length.
class _Smooth {
  _Smooth(this.pts) {
    var t = 0.0;
    acc.add(0);
    for (var i = 1; i < pts.length; i++) {
      t += (pts[i] - pts[i - 1]).distance;
      acc.add(t);
    }
    total = t;
  }
  final List<Offset> pts;
  final acc = <double>[];
  late final double total;
}

final _smooth = Expando<_Smooth>();

_Smooth _smoothOf(MagWorld w, List<int> path) => _smooth[path] ??= _Smooth(
  smoothLine([for (final c in path) Offset(w.cx(c) + .5, w.cy(c) + .5)]),
);

/// A point on a vehicle's way at [s] (cell index along [path] plus the
/// part of the way to the next cell), and the heading there. The way is
/// the smoothed line through the cells and [s] runs evenly along its
/// length, so a vehicle never jerks at a corner.
(Offset, Offset) poseAlong(MagWorld w, List<int> path, double s) {
  if (path.isEmpty) return (Offset.zero, const Offset(1, 0));
  if (path.length == 1) {
    return (Offset(w.cx(path[0]) + .5, w.cy(path[0]) + .5), const Offset(1, 0));
  }
  final sm = _smoothOf(w, path);
  final target = (s / (path.length - 1)).clamp(0.0, 1.0) * sm.total;
  var lo = 0, hi = sm.acc.length - 1;
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (sm.acc[mid] <= target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final a = sm.pts[lo], b = sm.pts[hi];
  final seg = sm.acc[hi] - sm.acc[lo];
  final t = seg <= 0 ? 0.0 : (target - sm.acc[lo]) / seg;
  var d = b - a;
  if (d.distance < 1e-9) d = const Offset(1, 0);
  return (Offset.lerp(a, b, t)!, d / d.distance);
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
