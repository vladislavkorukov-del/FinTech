import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_curve.dart';
import 'mag_iso.dart';
import 'mag_network_art.dart';
import 'mag_shapes.dart';

/// Stage S28 (BRG-01, VIS-08): bridges and overpasses that follow the
/// curve of their way — a deck that rises off the ground, runs over the
/// lake, river, road or track below on piers and comes down again, with
/// railings and the road's own surface or the track on top.

/// One deck to draw: its points (ground units), height and what is on it.
class MagDeck {
  MagDeck(this.pts, this.height, this.road, this.rail, this.depth);
  final List<Offset> pts;
  final double height;
  final MagRoad road;
  final bool rail;
  final double depth;
}

/// Decks of the free ways: spans (over a lake: low; over a road or
/// track: high) and their own cells over a river (low).
List<MagDeck> magDecks(MagWorld w) {
  if (w.ways.isEmpty) return const [];
  final idx = w.wayIndex;
  final out = <MagDeck>[];
  Offset at(MagPt p) => Offset(p.$1, p.$2);
  double depthOf(Iterable<int> cells) =>
      cells.map((c) => w.cx(c) + w.cy(c) + .0).reduce(math.max) + .9;
  final levels = deckLevels(w);
  for (var i = 0; i < idx.runs.length; i++) {
    final r = idx.runs[i];
    final over = r.cells.any((c) => w.roads[c] != 0 || w.rails[c] != 0);
    // The deck follows the way's own smooth curve (not the cells' points),
    // and starts and ends well before and after the span: gentle ramps.
    final curve = idx.lays[idx.ways.indexOf(r.way)].curve;
    out.add(
      MagDeck(
        _piece(curve, at(r.pts.first), at(r.pts.last), over ? 1.6 : .7),
        over ? 12.0 + 12.0 * (levels[i] - 1) : 7,
        r.way.road,
        r.way.rail,
        depthOf([r.a, r.b, ...r.cells]),
      ),
    );
  }
  // Own cells over a river: a low bridge along the curve.
  for (var k = 0; k < idx.ways.length; k++) {
    final way = idx.ways[k], lay = idx.lays[k];
    var i = 0;
    while (i < lay.cells.length) {
      final c = lay.cells[i];
      if (way.spans.contains(c) ||
          w.map.at(w.cx(c), w.cy(c)) != MagTerrain.river) {
        i++;
        continue;
      }
      var j = i;
      while (j < lay.cells.length &&
          !way.spans.contains(lay.cells[j]) &&
          w.map.at(w.cx(lay.cells[j]), w.cy(lay.cells[j])) ==
              MagTerrain.river) {
        j++;
      }
      final from = math.max(0, i - 1), to = math.min(lay.cells.length - 1, j);
      final cells = lay.cells.sublist(from, to + 1);
      out.add(
        MagDeck(
          _piece(
            lay.curve,
            at(lay.anchors[cells.first]!),
            at(lay.anchors[cells.last]!),
            .3,
          ),
          6,
          way.road,
          way.rail,
          depthOf(cells),
        ),
      );
      i = j;
    }
  }
  return out;
}

/// The piece of [curve] from the sample nearest [from] to the one nearest
/// [to], carried on by [extend] cells at both ends.
List<Offset> _piece(List<MagPt> curve, Offset from, Offset to, double extend) {
  int nearest(Offset p) {
    var best = 0;
    var d = double.infinity;
    for (var i = 0; i < curve.length; i++) {
      final dx = curve[i].$1 - p.dx, dy = curve[i].$2 - p.dy;
      final e = dx * dx + dy * dy;
      if (e < d) {
        d = e;
        best = i;
      }
    }
    return best;
  }

  var a = nearest(from), b = nearest(to);
  if (a > b) (a, b) = (b, a);
  double step(int i) {
    final dx = curve[i].$1 - curve[i - 1].$1;
    final dy = curve[i].$2 - curve[i - 1].$2;
    return math.sqrt(dx * dx + dy * dy);
  }

  for (var run = 0.0; a > 0 && run < extend; a--) {
    run += step(a);
  }
  for (var run = 0.0; b < curve.length - 1 && run < extend; b++) {
    run += step(b + 1);
  }
  return [for (var i = a; i <= b; i++) Offset(curve[i].$1, curve[i].$2)];
}

/// The level of each bridge (S29): 1 over the ground; a bridge passing
/// over another bridge (or its ends) one level higher — up to three.
List<int> deckLevels(MagWorld w) {
  final runs = w.wayIndex.runs;
  final cached = _levels[runs];
  if (cached != null) return cached;
  final out = <int>[];
  for (var i = 0; i < runs.length; i++) {
    var level = 1;
    final mine = runs[i].cells.toSet();
    for (var j = 0; j < i; j++) {
      final o = runs[j];
      if (mine.contains(o.a) ||
          mine.contains(o.b) ||
          o.cells.any(mine.contains)) {
        level = math.max(level, out[j] + 1);
      }
    }
    out.add(math.min(3, level));
  }
  return _levels[runs] = out;
}

final _levels = Expando<List<int>>();

/// Cells of the free ways that a deck covers (not drawn on the ground).
Set<int> magDeckCells(MagWorld w, {required bool rail}) {
  if (w.ways.isEmpty) return const {};
  final idx = w.wayIndex;
  final out = <int>{};
  for (var k = 0; k < idx.ways.length; k++) {
    final way = idx.ways[k];
    if (way.rail != rail) continue;
    for (final c in idx.lays[k].cells) {
      if (way.spans.contains(c) ||
          w.map.at(w.cx(c), w.cy(c)) == MagTerrain.river) {
        out.add(c);
      }
    }
  }
  return out;
}

/// Draws a deck (screen space: iso projection with height).
void paintDeck(Canvas c, MagDeck d) {
  final pts = d.pts;
  if (pts.length < 2) return;
  final acc = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    acc.add(acc.last + (pts[i] - pts[i - 1]).distance);
  }
  final total = acc.last;
  // A short deck cannot climb high: no spikes.
  final height = math.min(d.height, 5 + total * 6);
  final ramp = math.max(.6, math.min(1.4, total / 3));
  double z(int i) {
    final e = math.min(acc[i], total - acc[i]);
    final t = (e / ramp).clamp(0.0, 1.0);
    return height * t * t * (3 - 2 * t);
  }

  final width = d.rail ? .44 : roadWidth(d.road) + .1;
  Offset normal(int i) {
    final a = pts[math.max(0, i - 1)], b = pts[math.min(pts.length - 1, i + 1)];
    final v = b - a;
    final l = v.distance;
    return l == 0 ? const Offset(0, 1) : Offset(-v.dy / l, v.dx / l);
  }

  Offset proj(Offset p, double h) => MagIso.project(p.dx, p.dy, h);
  final left = <Offset>[], right = <Offset>[], zs = <double>[];
  for (var i = 0; i < pts.length; i++) {
    final n = normal(i) * (width / 2);
    zs.add(z(i));
    left.add(pts[i] + n);
    right.add(pts[i] - n);
  }
  // Piers where the deck is up.
  var next = .6;
  for (var i = 0; i < pts.length; i++) {
    if (acc[i] < next || zs[i] < height * .7) continue;
    next = acc[i] + 1.3;
    MagShapes.box(
      c,
      x: pts[i].dx,
      y: pts[i].dy,
      length: .12,
      width: .12,
      h: zs[i] - 2,
      color: const Color(0xFFB8BEC6),
    );
  }
  // The sides, then the top.
  final side = Path();
  for (var i = 0; i < pts.length; i++) {
    final p = proj(right[i], zs[i]);
    i == 0 ? side.moveTo(p.dx, p.dy) : side.lineTo(p.dx, p.dy);
  }
  for (var i = pts.length - 1; i >= 0; i--) {
    final p = proj(right[i], math.max(0, zs[i] - 3));
    side.lineTo(p.dx, p.dy);
  }
  side.close();
  c.drawPath(side, Paint()..color = const Color(0xFF8E959D));
  final top = Path();
  for (var i = 0; i < pts.length; i++) {
    final p = proj(left[i], zs[i]);
    i == 0 ? top.moveTo(p.dx, p.dy) : top.lineTo(p.dx, p.dy);
  }
  for (var i = pts.length - 1; i >= 0; i--) {
    final p = proj(right[i], zs[i]);
    top.lineTo(p.dx, p.dy);
  }
  top.close();
  final surface = d.rail ? const Color(0xFF9C9488) : roadColors(d.road).$2;
  c.drawPath(top, Paint()..color = surface);

  final rail = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..strokeCap = StrokeCap.round
    ..color = const Color(0xFFDDE1E5);
  for (var i = 1; i < pts.length; i++) {
    if (zs[i] < height * .35) continue;
    for (final side in [left, right]) {
      c.drawLine(
        proj(side[i - 1], zs[i - 1] + 2),
        proj(side[i], zs[i] + 2),
        rail,
      );
    }
  }
  // On top: the track, or the road's centre line.
  final centre = [for (var i = 0; i < pts.length; i++) pts[i]];
  if (d.rail) {
    for (final off in const [-.1, .1]) {
      final p = Path();
      for (var i = 0; i < pts.length; i++) {
        final q = proj(centre[i] + normal(i) * off, zs[i]);
        i == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
      }
      c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF59606A),
      );
    }
  } else if (d.road != MagRoad.dirt) {
    final p = Path();
    for (var i = 0; i < pts.length; i++) {
      final q = proj(centre[i], zs[i]);
      i == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
    }
    c.drawPath(
      dashed(p, 5, 4.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xE6F4F1E6),
    );
  }
}

/// How high a vehicle rides now (on a bridge or an overpass), screen px.
double vehicleLift(MagWorld w, MagVehicle v) {
  if (w.ways.isEmpty ||
      v.state != MagVehicleState.driving ||
      v.pathIndex + 1 >= v.path.length) {
    return 0;
  }
  final a = v.path[v.pathIndex], b = v.path[v.pathIndex + 1];
  final hop = (w.cx(a) - w.cx(b)).abs() + (w.cy(a) - w.cy(b)).abs();
  if (hop <= 1) {
    // Along its own cells over a river: on the low bridge.
    bool river(int c) =>
        w.map.at(w.cx(c), w.cy(c)) == MagTerrain.river &&
        w.onWay(c, rail: v.spec.rail);
    return river(a) && river(b)
        ? 6
        : river(b)
        ? 6 * v.progress
        : river(a)
        ? 6 * (1 - v.progress)
        : 0;
  }
  final runs = w.wayIndex.runs;
  var h = 0.0;
  for (var i = 0; i < runs.length; i++) {
    final r = runs[i];
    if (!(r.a == a && r.b == b || r.a == b && r.b == a)) continue;
    final over = r.cells.any((c) => w.roads[c] != 0 || w.rails[c] != 0);
    h = over ? 12.0 + 12.0 * (deckLevels(w)[i] - 1) : 7.0;
  }
  if (h == 0) return 0;
  h = math.min(h, 5 + (hop + 1) * 6.0); // as the deck: no spikes
  final t = v.progress;
  final edge = math.min(t, 1 - t) * hop / 1.1;
  final k = edge.clamp(0.0, 1.0);
  return h * k * k * (3 - 2 * k);
}

/// Paints [draw] raised by [lift] screen pixels.
void lifted(Canvas c, double lift, VoidCallback draw) {
  if (lift <= 0) return draw();
  c
    ..save()
    ..translate(0, -lift);
  draw();
  c.restore();
}
