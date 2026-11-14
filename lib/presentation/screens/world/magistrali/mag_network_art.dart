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
  late final List<Offset> points;
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
    ch.points = smoothLine(pts);
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

/// A road chain on the ground (under the ground transform): a soft shoulder
/// and the surface; only highways and motorways carry a centre line.
void paintRoadChain(Canvas c, NetChain ch) {
  final w = roadWidth(ch.road);
  final path = _line(ch.points);
  final (shoulder, surface) = switch (ch.road) {
    MagRoad.dirt => (const Color(0xFFB08C5C), const Color(0xFFCDA772)),
    MagRoad.asphalt => (const Color(0xFF4C5358), const Color(0xFF666E74)),
    MagRoad.highway => (const Color(0xFF454B50), const Color(0xFF5A6268)),
    _ => (const Color(0xFF3E4448), const Color(0xFF51585E)),
  };
  c.drawPath(path, _stroke(shoulder, w + .06));
  c.drawPath(path, _stroke(surface, w));
  if (ch.road == MagRoad.highway || ch.road == MagRoad.motorway) {
    c.drawPath(
      dashed(path, .2, .2),
      _stroke(const Color(0x99F3E9C6), .025, cap: StrokeCap.butt),
    );
  }
}

/// A short piece of road from a cell's centre to a place it serves.
void paintRoadStub(Canvas c, MagRoad r, int x, int y, int dir) {
  final a = Offset(x + .5, y + .5);
  final b = a + Offset(MagDir.dx[dir] * .5, MagDir.dy[dir] * .5);
  final p = Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy);
  final w = roadWidth(r);
  c.drawPath(p, _stroke(const Color(0xFF8E8A80), w + .06));
  c.drawPath(
    p,
    _stroke(
      r == MagRoad.dirt ? const Color(0xFFCDA772) : const Color(0xFF666E74),
      w,
    ),
  );
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

/// A tunnel portal where a way goes into the hills (in iso space): a dark
/// mouth in a stone frame, facing the way out.
void paintPortal(Canvas c, MagWorld w, int cell, int outDir) {
  final x = w.cx(cell) + .5 + MagDir.dx[outDir] * .38;
  final y = w.cy(cell) + .5 + MagDir.dy[outDir] * .38;
  final base = MagIso.project(x, y);
  final across = outDir == 1 || outDir == 3
      ? MagIso.project(0, .3) - MagIso.project(0, 0)
      : MagIso.project(.3, 0) - MagIso.project(0, 0);
  final l = base - across, r = base + across;
  final frame = Path()
    ..moveTo(l.dx, l.dy)
    ..lineTo(l.dx, l.dy - 12)
    ..quadraticBezierTo(base.dx, base.dy - 24, r.dx, r.dy - 12)
    ..lineTo(r.dx, r.dy)
    ..close();
  c.drawPath(frame, Paint()..color = const Color(0xFF8F8D86));
  final mouth = Path()
    ..moveTo(l.dx * .8 + base.dx * .2, l.dy * .8 + base.dy * .2)
    ..lineTo(l.dx * .8 + base.dx * .2, l.dy * .8 + base.dy * .2 - 9)
    ..quadraticBezierTo(
      base.dx,
      base.dy - 19,
      r.dx * .8 + base.dx * .2,
      r.dy * .8 + base.dy * .2 - 9,
    )
    ..lineTo(r.dx * .8 + base.dx * .2, r.dy * .8 + base.dy * .2)
    ..close();
  c.drawPath(mouth, Paint()..color = const Color(0xFF1F2326));
}
