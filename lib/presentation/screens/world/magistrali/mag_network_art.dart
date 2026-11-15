import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_curve.dart';
import 'mag_iso.dart';
import 'mag_shapes.dart';

/// Roads and track drawn as whole smooth lines (stage S11 visuals): the
/// network is cut into chains between junctions (and where the surface
/// changes), each chain is a polyline through the cell centres, smoothed by
/// corner cutting and stroked once — no bumps where cells meet. Over rivers
/// a chain becomes a bridge, through hills a tunnel with portals.

/// One chain of a network: its cells in order and, for roads, the surface.
class NetChain {
  NetChain(this.cells, this.road);
  final List<int> cells;
  final MagRoad road;
  late List<Offset> points;
  Rect? _bounds;

  /// S28: square ends (where it tapers into a road of another kind).
  bool butt = false;

  /// The cells it covers, worked out once (S20: no scan every frame).
  Rect bounds(int size) => _bounds ??= () {
    var x0 = size, y0 = size, x1 = 0, y1 = 0;
    for (final c in cells) {
      final x = c % size, y = c ~/ size;
      if (x < x0) x0 = x;
      if (y < y0) y0 = y;
      if (x > x1) x1 = x;
      if (y > y1) y1 = y;
    }
    return Rect.fromLTRB(x0.toDouble(), y0.toDouble(), x1 + 1.0, y1 + 1.0);
  }();
}

/// The chains of a network. [type] gives a cell's kind (0: none); a chain
/// ends at a junction, a dead end or where the kind changes.
List<NetChain> netChains(MagWorld w, int Function(int cell) type) {
  final n = w.size;
  int deg(int c) {
    var d = 0;
    for (var k = 0; k < 4; k++) {
      final x = w.cx(c) + MagDir.dx[k], y = w.cy(c) + MagDir.dy[k];
      if (x >= 0 && y >= 0 && x < n && y < n && type(w.cellOf(x, y)) != 0) d++;
    }
    return d;
  }

  List<int> around(int c) => [
    for (var k = 0; k < 4; k++)
      if (w.map.inside(w.cx(c) + MagDir.dx[k], w.cy(c) + MagDir.dy[k]) &&
          type(w.cellOf(w.cx(c) + MagDir.dx[k], w.cy(c) + MagDir.dy[k])) != 0)
        w.cellOf(w.cx(c) + MagDir.dx[k], w.cy(c) + MagDir.dy[k]),
  ];

  bool node(int c) {
    final nb = around(c);
    if (nb.length != 2) return true;
    return nb.any((o) => type(o) != type(c));
  }

  final seen = <int>{};
  int key(int a, int b) => a < b ? a * 65536 + b : b * 65536 + a;
  final out = <NetChain>[];
  void walk(int from, int next) {
    if (!seen.add(key(from, next))) return;
    final cells = [from, next];
    var prev = from, cur = next;
    while (!node(cur) && type(cur) == type(prev)) {
      final nx = around(cur).firstWhere((o) => o != prev);
      if (!seen.add(key(cur, nx))) break;
      cells.add(nx);
      prev = cur;
      cur = nx;
    }
    final kind = type(cells[cells.length ~/ 2]);
    out.add(NetChain(cells, MagRoad.values[kind.clamp(0, 4)]));
  }

  for (var c = 0; c < n * n; c++) {
    if (type(c) == 0) continue;
    if (deg(c) == 0) {
      out.add(NetChain([c], MagRoad.values[type(c).clamp(0, 4)]));
      continue;
    }
    if (!node(c)) continue;
    for (final o in around(c)) {
      walk(c, o);
    }
  }
  // Loops with no junction at all.
  for (var c = 0; c < n * n; c++) {
    if (type(c) == 0) continue;
    for (final o in around(c)) {
      walk(c, o);
    }
  }
  for (final ch in out) {
    final pts = [for (final c in ch.cells) Offset(w.cx(c) + .5, w.cy(c) + .5)];
    // Where the surface changes, meet half way.
    ch.points = wayLine(pts); // S26: free-form lines
  }
  return out;
}

Path _line(List<Offset> pts) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final q in pts.skip(1)) {
    p.lineTo(q.dx, q.dy);
  }
  if (pts.length == 1) p.lineTo(pts.first.dx + .001, pts.first.dy);
  return p;
}

Paint _stroke(Color c, double w, {StrokeCap cap = StrokeCap.round}) => Paint()
  ..style = PaintingStyle.stroke
  ..color = c
  ..strokeWidth = w
  ..strokeCap = cap
  ..strokeJoin = StrokeJoin.round;

double roadWidth(MagRoad r) => switch (r) {
  MagRoad.dirt => .38,
  MagRoad.asphalt => .44,
  MagRoad.highway => .54,
  MagRoad.motorway => .64,
  MagRoad.none => 0,
};

(Color, Color) roadColors(MagRoad r) => switch (r) {
  MagRoad.dirt => (const Color(0xFFB08C5C), const Color(0xFFCDA772)),
  MagRoad.asphalt => (const Color(0xFF4C5358), const Color(0xFF666E74)),
  MagRoad.highway => (const Color(0xFF454B50), const Color(0xFF5A6268)),
  _ => (const Color(0xFF3E4448), const Color(0xFF51585E)),
};

/// A road chain on the ground (under the ground transform): a soft shoulder,
/// the surface and its marking (S12) — wheel ruts on a dirt road, a dashed
/// centre line on asphalt, edge lines and a dashed centre on a highway,
/// edge lines, a double centre line and lane dashes on a motorway. Edge
/// lines stop short of the chain's ends, so junctions stay clean.
///
/// Drawn in three passes over all chains (0: shoulders, 1: surfaces,
/// 2: marking), so where chains meet no shoulder lies over a surface.
void paintRoadChain(Canvas c, NetChain ch, [int pass = -1]) {
  final w = roadWidth(ch.road);
  final path = _line(ch.points);
  final (shoulder, surface) = roadColors(ch.road);
  final cap = ch.butt ? StrokeCap.butt : StrokeCap.round;
  if (pass < 0 || pass == 0) {
    c.drawPath(path, _stroke(shoulder, w + .06, cap: cap));
  }
  if (pass < 0 || pass == 1) c.drawPath(path, _stroke(surface, w, cap: cap));
  if (pass >= 0 && pass != 2) return;
  const paint = Color(0xE6F4F1E6);
  Paint line(double width, [Color color = paint]) =>
      _stroke(color, width, cap: StrokeCap.butt);
  void along(double d, Paint p, {double? dash, bool trim = false}) {
    var pts = _offset(ch.points, d);
    if (trim) pts = _trim(pts, .42);
    if (pts.length < 2) return;
    final path = _line(pts);
    c.drawPath(dash == null ? path : dashed(path, dash, dash * .9), p);
  }

  switch (ch.road) {
    case MagRoad.dirt:
      for (final d in [-.085, .085]) {
        along(d, line(.04, const Color(0x40765A38)));
      }
    case MagRoad.asphalt:
      along(0, line(.026), dash: .17);
    case MagRoad.highway:
      for (final d in [-w / 2 + .05, w / 2 - .05]) {
        along(d, line(.022), trim: true);
      }
      along(0, line(.026), dash: .2);
    case MagRoad.motorway:
      for (final d in [-w / 2 + .05, w / 2 - .05]) {
        along(d, line(.022), trim: true);
      }
      for (final d in [-.022, .022]) {
        along(d, line(.018), trim: true);
      }
      for (final d in [-w / 4, w / 4]) {
        along(d, line(.018), dash: .16);
      }
    case MagRoad.none:
      break;
  }
}

/// A polyline with [d] of length cut from both ends.
List<Offset> _trim(List<Offset> pts, double d) {
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += (pts[i] - pts[i - 1]).distance;
  }
  if (total <= d * 2) return const [];
  final out = <Offset>[];
  var run = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final l = (b - a).distance;
    if (l == 0) continue;
    final s = ((d - run) / l).clamp(0.0, 1.0);
    final e = ((total - d - run) / l).clamp(0.0, 1.0);
    if (s < e) {
      if (out.isEmpty) out.add(Offset.lerp(a, b, s)!);
      out.add(Offset.lerp(a, b, e)!);
    }
    run += l;
  }
  return out;
}

/// A short piece of road from a cell's centre into a place: the entrance
/// of a business, or a way into a settlement.
void paintRoadStub(Canvas c, MagRoad r, int x, int y, int dir) {
  final a = Offset(x + .5, y + .5);
  final b = a + Offset(MagDir.dx[dir] * .5, MagDir.dy[dir] * .5);
  final p = Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy);
  // A driveway: the road's own colours, a little narrower.
  final w = roadWidth(r) * .8;
  final (shoulder, surface) = roadColors(r);
  c.drawPath(p, _stroke(shoulder, w + .06, cap: StrokeCap.butt));
  c.drawPath(p, _stroke(surface, w, cap: StrokeCap.butt));
}

/// A track chain on the ground: ballast, sleepers across, two rails.
void paintRailChain(Canvas c, NetChain ch) {
  final path = _line(ch.points);
  c.drawPath(path, _stroke(const Color(0xFF9C9488), .4));
  c.drawPath(
    dashed(path, .06, .1),
    _stroke(const Color(0xFF6E4E35), .34, cap: StrokeCap.butt),
  );
  for (final d in [-.1, .1]) {
    c.drawPath(
      _line(_offset(ch.points, d)),
      _stroke(const Color(0xFF59606A), .045),
    );
  }
}

/// A polyline moved sideways by [d].
List<Offset> _offset(List<Offset> pts, double d) {
  if (pts.length < 2) return pts;
  return [
    for (var i = 0; i < pts.length; i++)
      () {
        final a = pts[math.max(0, i - 1)],
            b = pts[math.min(pts.length - 1, i + 1)];
        final v = b - a;
        final l = v.distance;
        return l == 0 ? pts[i] : pts[i] + Offset(-v.dy / l, v.dx / l) * d;
      }(),
  ];
}

/// The direction of a way across cell [cell] (horizontal or vertical,
/// along its neighbours of the same network).
bool _alongX(MagWorld w, int cell, bool Function(int) has) {
  final x = w.cx(cell), y = w.cy(cell);
  final ex =
      w.map.inside(x + 1, y) && has(w.cellOf(x + 1, y)) ||
      w.map.inside(x - 1, y) && has(w.cellOf(x - 1, y));
  final ey =
      w.map.inside(x, y + 1) && has(w.cellOf(x, y + 1)) ||
      w.map.inside(x, y - 1) && has(w.cellOf(x, y - 1));
  return ex || !ey;
}

/// A bridge over a river cell (in iso space, with the objects): a deck on
/// piers with railings; a railway bridge is a steel truss.
void paintBridge(Canvas c, MagWorld w, int cell, {required bool rail}) {
  final x = w.cx(cell) + .5, y = w.cy(cell) + .5;
  final along = _alongX(
    w,
    cell,
    rail ? (k) => w.rails[k] != 0 : (k) => w.roads[k] != 0,
  );
  final len = 1.02, wid = rail ? .5 : .62;
  final l = along ? len : wid, wd = along ? wid : len;
  // Piers down into the water.
  for (final t in [-.32, .32]) {
    MagShapes.box(
      c,
      x: x + (along ? t : 0),
      y: y + (along ? 0 : t),
      length: .14,
      width: .14,
      h: 6,
      color: const Color(0xFFA7A9AC),
    );
  }
  // The deck.
  MagShapes.box(
    c,
    x: x,
    y: y,
    length: l,
    width: wd,
    z0: 6,
    h: 2.5,
    color: rail ? const Color(0xFF6E6A62) : const Color(0xFF8E8A80),
    top: rail ? const Color(0xFF8C8478) : const Color(0xFF6A7177),
  );
  // Railings (road) or a truss (rail) on both sides.
  for (final s in [-1, 1]) {
    MagShapes.box(
      c,
      x: x + (along ? 0 : s * wd / 2),
      y: y + (along ? s * wd / 2 : 0),
      length: along ? l : .04,
      width: along ? .04 : l,
      z0: 8.5,
      h: rail ? 9 : 3,
      color: rail ? const Color(0xFF4A6FD8) : const Color(0xFFE9EEF0),
      outline: false,
    );
  }
  // Water shading under it.
  final p = MagIso.project(x, y);
  c.drawOval(
    Rect.fromCenter(center: p + const Offset(4, 3), width: 40, height: 14),
    Paint()..color = const Color(0x22183040),
  );
}

/// Road load over the roads (ROAD-10, under the ground transform): each
/// road cell is tinted green, yellow or red by yesterday's vehicles against
/// its capacity; empty roads stay as they are.
void paintTraffic(Canvas c, MagWorld w, int x0, int y0, int x1, int y1) {
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final cell = w.cellOf(x, y);
      if (w.roads[cell] == 0 || w.trafficOf(cell) == 0) continue;
      final l = w.loadOf(cell);
      final color = l > 1
          ? const Color(0xCCE0453C)
          : l > .6
          ? const Color(0xCCF0B43C)
          : const Color(0xCC3CB878);
      final p = _stroke(color, roadWidth(MagRoad.values[w.roads[cell]]) * .45);
      final a = Offset(x + .5, y + .5);
      var linked = false;
      for (var d = 0; d < 4; d++) {
        final nx = x + MagDir.dx[d], ny = y + MagDir.dy[d];
        if (!w.map.inside(nx, ny) || w.roads[w.cellOf(nx, ny)] == 0) continue;
        linked = true;
        c.drawLine(a, a + Offset(MagDir.dx[d] * .5, MagDir.dy[d] * .5), p);
      }
      if (!linked) c.drawCircle(a, .15, Paint()..color = color);
    }
  }
}
