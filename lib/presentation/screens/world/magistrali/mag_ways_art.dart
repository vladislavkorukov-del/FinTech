import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_art.dart';
import 'mag_network_art.dart';

/// Stage S27 (VIS-05): the network on the ground — free ways drawn along
/// the curves the player laid, older roads of cells as smooth chains that
/// run into the ways they meet, and clean junctions: a plate of the
/// road's surface over every crossing and branch, so lines, ruts and caps
/// never pile up where roads meet.
class MagNet {
  int _version = -1, _ways = -1;
  List<NetChain> roads = const [], rails = const [];
  List<(Offset, MagRoad)> junctions = const [];

  void refresh(MagWorld w) {
    if (_version == w.roadVersion && _ways == w.ways.length) return;
    _version = w.roadVersion;
    _ways = w.ways.length;
    final idx = w.ways.isEmpty ? null : w.wayIndex;
    Offset at(int c) {
      final (x, y) = w.wayPoint(c);
      return Offset(x, y);
    }

    List<NetChain> build(bool rail) {
      int type(int c) => rail ? w.rails[c] : w.roads[c];
      final legacy = netChains(w, (c) => w.onWay(c, rail: rail) ? 0 : type(c));
      final out = <NetChain>[];
      for (final ch in legacy) {
        // An old chain runs on into a free way it touches.
        final pts = List.of(ch.points);
        for (final (end, front) in [
          (ch.cells.first, true),
          (ch.cells.last, false),
        ]) {
          for (var d = 0; d < 4; d++) {
            final x = w.cx(end) + MagDir.dx[d], y = w.cy(end) + MagDir.dy[d];
            if (!w.map.inside(x, y)) continue;
            final n = w.cellOf(x, y);
            if (!w.onWay(n, rail: rail)) continue;
            if (front) {
              pts.insert(0, at(n));
            } else {
              pts.add(at(n));
            }
            break;
          }
        }
        out.add(NetChain(ch.cells, ch.road)..points = pts);
      }
      if (idx != null) {
        for (var k = 0; k < idx.ways.length; k++) {
          final way = idx.ways[k];
          if (way.rail != rail) continue;
          final lay = idx.lays[k];
          out.add(
            NetChain(lay.cells, rail ? MagRoad.none : way.road)
              ..points = [for (final (x, y) in lay.curve) Offset(x, y)],
          );
        }
      }
      return out;
    }

    roads = build(false);
    rails = build(true);
    // Junctions: a road cell with three or more roads around it, or one
    // two ways share.
    final owners = <int, int>{};
    if (idx != null) {
      for (var k = 0; k < idx.ways.length; k++) {
        if (idx.ways[k].rail) continue;
        for (final c in idx.lays[k].cells) {
          owners[c] = (owners[c] ?? 0) + 1;
        }
      }
    }
    final out = <(Offset, MagRoad)>[];
    for (var c = 0; c < w.roads.length; c++) {
      if (w.roads[c] == 0) continue;
      var deg = 0, legacy = 0;
      for (var d = 0; d < 4; d++) {
        final x = w.cx(c) + MagDir.dx[d], y = w.cy(c) + MagDir.dy[d];
        if (!w.hasRoad(x, y)) continue;
        deg++;
        if (owners[w.cellOf(x, y)] == null) legacy++;
      }
      final mine = owners[c] ?? 0;
      // Inside one way the cells of its footprint touch side by side on
      // bends — no junction there; an old road running into it is one.
      final junction = mine >= 2 || (mine == 1 ? legacy > 0 : deg >= 3);
      if (junction) {
        out.add((at(c), MagRoad.values[w.roads[c]]));
      }
    }
    junctions = out;
  }

  /// Roads in three passes (shoulders, surfaces, marking), then the
  /// junction plates over them.
  void paintRoads(Canvas c, Rect view, int size) {
    bool seen(NetChain ch) => view.overlaps(ch.bounds(size));
    for (var pass = 0; pass < 3; pass++) {
      for (final ch in roads) {
        if (seen(ch)) paintRoadChain(c, ch, pass);
      }
    }
    for (final (p, r) in junctions) {
      if (!view.contains(p)) continue;
      final (_, surface) = roadColors(r);
      c.drawCircle(p, roadWidth(r) / 2 + .02, Paint()..color = surface);
    }
  }

  void paintRails(Canvas c, Rect view, int size) {
    for (final ch in rails) {
      if (view.overlaps(ch.bounds(size))) paintRailChain(c, ch);
    }
  }
}

/// A free way being drawn (under the ground transform): its curve over
/// the cells it will take.
void paintPlanShape(Canvas c, MagWorld w, List<Offset> shape, bool ok) {
  if (shape.length < 2) return;
  final curve = w.wayCurve([for (final p in shape) (p.dx, p.dy)]);
  final path = Path()..moveTo(curve.first.$1, curve.first.$2);
  for (final (x, y) in curve.skip(1)) {
    path.lineTo(x, y);
  }
  final color = ok ? MagPalette.mint : const Color(0xFFE0566B);
  c.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: .75),
  );
  for (final p in [shape.first, shape.last]) {
    c.drawCircle(p, .22, Paint()..color = Colors.white);
    c.drawCircle(p, .14, Paint()..color = color);
  }
}
