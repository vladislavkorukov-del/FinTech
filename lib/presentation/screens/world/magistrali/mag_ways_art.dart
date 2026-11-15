import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_art.dart';
import 'mag_deck_art.dart';
import 'mag_iso.dart';
import 'mag_network_art.dart';
import 'mag_structures_art.dart';

/// Stage S27 (VIS-05): the network on the ground — free ways drawn along
/// the curves the player laid, older roads of cells as smooth chains that
/// run into the ways they meet, and clean junctions: a plate of the
/// road's surface over every crossing and branch, so lines, ruts and caps
/// never pile up where roads meet.
class MagNet {
  int _version = -1, _ways = -1;
  List<NetChain> roads = const [], rails = const [];
  List<(Offset, MagRoad)> junctions = const [];

  /// S28: where a road meets one of another kind: (point, direction from
  /// the wider road, wider kind, narrower kind).
  List<(Offset, Offset, MagRoad, MagRoad)> tapers = const [];

  /// S28: decks of bridges and overpasses; tram tracks along streets.
  List<MagDeck> decks = const [];
  List<(Offset, Offset)> tramTracks = const [];

  /// S29: tunnel portals where curves enter and leave the hills (point,
  /// outward direction), and lamps along highways and motorways.
  List<(Offset, Offset)> portals = const [];
  List<Offset> lamps = const [];
  int _trams = -1;

  /// The network drawn last (for the night lights).
  static MagNet? current;

  void refresh(MagWorld w) {
    current = this;
    final trams = w.vehicles.values
        .where((v) => v.spec.body == 'tram' && v.routeId != null)
        .fold(0, (s, v) => s * 31 + v.routeId! + 1);
    if (_version == w.roadVersion &&
        _ways == w.ways.length &&
        _trams == trams) {
      return;
    }
    _version = w.roadVersion;
    _ways = w.ways.length;
    _trams = trams;
    decks = magDecks(w);
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
        // A way on the ground, broken where a deck carries it.
        final up = magDeckCells(w, rail: rail);
        for (var k = 0; k < idx.ways.length; k++) {
          final way = idx.ways[k];
          if (way.rail != rail) continue;
          final lay = idx.lays[k];
          var piece = <Offset>[];
          void flush() {
            if (piece.length > 1) {
              out.add(
                NetChain(lay.cells, rail ? MagRoad.none : way.road)
                  ..points = piece,
              );
            }
            piece = [];
          }

          for (final (x, y) in lay.curve) {
            final c = w.cellOf(
              x.floor().clamp(0, w.size - 1),
              y.floor().clamp(0, w.size - 1),
            );
            if (up.contains(c)) {
              flush();
            } else {
              piece.add(Offset(x, y));
            }
          }
          flush();
        }
      }
      return out;
    }

    roads = build(false);
    rails = build(true);
    portals = _portals(w, idx);
    lamps = _lamps(roads);
    // Junctions: a road cell with three or more roads around it, or one
    // two ways share.
    final owners = <int, int>{};
    if (idx != null) {
      for (var k = 0; k < idx.ways.length; k++) {
        if (idx.ways[k].rail) continue;
        for (final c in idx.lays[k].cells) {
          if (idx.ways[k].spans.contains(c)) continue;
          owners[c] = (owners[c] ?? 0) + 1;
        }
      }
    }
    final out = <(Offset, MagRoad)>[];
    final cuts = w.spanCuts(), n = w.size * w.size;
    for (var c = 0; c < w.roads.length; c++) {
      if (w.roads[c] == 0) continue;
      var deg = 0, legacy = 0;
      for (var d = 0; d < 4; d++) {
        final x = w.cx(c) + MagDir.dx[d], y = w.cy(c) + MagDir.dy[d];
        if (!w.hasRoad(x, y)) continue;
        // Not joined: an overpass beside the road it passes over.
        if (cuts != null && cuts.contains(c * n + w.cellOf(x, y))) continue;
        deg++;
        if (owners[w.cellOf(x, y)] == null) legacy++;
      }
      final mine = owners[c] ?? 0;
      // Inside one way the cells of its footprint touch side by side on
      // bends — no junction there; an old road running into it is one.
      // Two ways end to end (a change of kind) are no junction: a taper
      // joins them.
      final junction = deg >= 3 && (mine != 1 || legacy > 0);
      if (junction) {
        out.add((at(c), MagRoad.values[w.roads[c]]));
      }
    }
    junctions = out;
    tapers = _tapers(roads, out);
    tramTracks = [
      for (final c in w.tramStreets())
        for (final d in const [1, 2])
          if (w.map.inside(w.cx(c) + MagDir.dx[d], w.cy(c) + MagDir.dy[d]))
            if (w.cellOf(w.cx(c) + MagDir.dx[d], w.cy(c) + MagDir.dy[d])
                case final o when w.roads[o] != 0)
              (at(c), at(o)),
    ];
  }

  /// Where a curve crosses from the hills to open ground.
  List<(Offset, Offset)> _portals(MagWorld w, MagWayIndex? idx) {
    if (idx == null) return const [];
    final out = <(Offset, Offset)>[];
    bool hill(double x, double y) =>
        w.map.at(
          x.floor().clamp(0, w.size - 1),
          y.floor().clamp(0, w.size - 1),
        ) ==
        MagTerrain.hill;
    for (final lay in idx.lays) {
      final c = lay.curve;
      for (var i = 1; i < c.length; i++) {
        final a = hill(c[i - 1].$1, c[i - 1].$2), b = hill(c[i].$1, c[i].$2);
        if (a == b) continue;
        final p = Offset(c[i].$1, c[i].$2),
            q = Offset(c[i - 1].$1, c[i - 1].$2);
        var d = a ? p - q : q - p; // outwards, away from the hill
        final l = d.distance;
        if (l < 1e-6) continue;
        d = d / l;
        out.add((Offset.lerp(p, q, .5)!, d));
      }
    }
    return out;
  }

  /// Lamps every cell and a half along both sides of the big roads.
  List<Offset> _lamps(List<NetChain> chains) {
    final out = <Offset>[];
    for (final ch in chains) {
      if (ch.road != MagRoad.highway && ch.road != MagRoad.motorway) continue;
      final side = roadWidth(ch.road) / 2 + .1;
      var next = .7, run = 0.0;
      final p = ch.points;
      for (var i = 1; i < p.length; i++) {
        final d = p[i] - p[i - 1];
        final l = d.distance;
        if (l == 0) continue;
        while (run + l >= next) {
          final t = (next - run) / l;
          final at = Offset.lerp(p[i - 1], p[i], t)!;
          final n = Offset(-d.dy, d.dx) / l * side;
          out
            ..add(at + n)
            ..add(at - n);
          next += 1.5;
        }
        run += l;
      }
    }
    return out;
  }

  /// Ends of two chains of different kinds meeting alone at a point: the
  /// wider one is cut short and a taper joins them.
  List<(Offset, Offset, MagRoad, MagRoad)> _tapers(
    List<NetChain> chains,
    List<(Offset, MagRoad)> plates,
  ) {
    final ends = <(int, int), List<(NetChain, bool)>>{};
    (int, int) key(Offset p) => ((p.dx * 8).round(), (p.dy * 8).round());
    for (final ch in chains) {
      if (ch.points.length < 2) continue;
      (ends[key(ch.points.first)] ??= []).add((ch, true));
      (ends[key(ch.points.last)] ??= []).add((ch, false));
    }
    final plated = {for (final (p, _) in plates) key(p)};
    final out = <(Offset, Offset, MagRoad, MagRoad)>[];
    for (final e in ends.entries) {
      if (e.value.length != 2 || plated.contains(e.key)) continue;
      final (a, af) = e.value[0];
      final (b, bf) = e.value[1];
      if (a.road == b.road) continue;
      final (wide, wf) = roadWidth(a.road) >= roadWidth(b.road)
          ? (a, af)
          : (b, bf);
      final narrow = identical(wide, a) ? b : a;
      final pts = wide.points;
      final p = wf ? pts.first : pts.last;
      final cut = _cutEnd(pts, .5, front: wf);
      if (cut == null) continue;
      wide
        ..points = cut
        ..butt = true;
      final q = wf ? cut.first : cut.last;
      final d = p - q;
      final l = d.distance;
      if (l < 1e-6) continue;
      out.add((p, d / l, wide.road, narrow.road));
    }
    return out;
  }

  /// [pts] with [d] cut from one end (null: too short).
  List<Offset>? _cutEnd(List<Offset> pts, double d, {required bool front}) {
    final src = front ? pts.reversed.toList() : pts;
    var run = 0.0;
    for (var i = src.length - 1; i > 0; i--) {
      final l = (src[i] - src[i - 1]).distance;
      if (run + l >= d) {
        final t = (d - run) / l;
        final out = [...src.sublist(0, i), Offset.lerp(src[i], src[i - 1], t)!];
        if (out.length < 2) return null;
        return front ? out.reversed.toList() : out;
      }
      run += l;
    }
    return null;
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
    // Tapers between roads of different kinds: shoulder, then surface.
    for (final (p, d, wide, narrow) in tapers) {
      if (!view.contains(p)) continue;
      final q = p - d * .5, n = Offset(-d.dy, d.dx);
      for (final pass in const [0, 1]) {
        final grow = pass == 0 ? .06 : 0;
        final ww = (roadWidth(wide) + grow) / 2;
        final nw = (roadWidth(narrow) + grow) / 2;
        final path = Path()
          ..moveTo((q + n * ww).dx, (q + n * ww).dy)
          ..lineTo((p + n * nw).dx, (p + n * nw).dy)
          ..lineTo((p - n * nw).dx, (p - n * nw).dy)
          ..lineTo((q - n * ww).dx, (q - n * ww).dy)
          ..close();
        final (sw, fw) = roadColors(wide);
        final (sn, fn) = roadColors(narrow);
        c.drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.linear(
              q,
              p,
              pass == 0 ? [sw, sn] : [fw, fn],
            ),
        );
      }
    }
    // Tram tracks set in the street.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .03
      ..color = const Color(0xFF9AA2A9);
    for (final (a, b) in tramTracks) {
      if (!view.contains(a)) continue;
      final d = b - a;
      final l = d.distance;
      if (l == 0) continue;
      final n = Offset(-d.dy, d.dx) / l * .07;
      c
        ..drawLine(a + n, b + n, track)
        ..drawLine(a - n, b - n, track);
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

/// Driveways from road cells into the places beside them.
void paintStubs(Canvas c, MagWorld w, int x0, int y0, int x1, int y1) {
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final r = w.roadAt(x, y);
      if (r == MagRoad.none) continue;
      for (var d = 0; d < 4; d++) {
        final nx = x + MagDir.dx[d], ny = y + MagDir.dy[d];
        final place = w.map.inside(nx, ny) && !w.hasRoad(nx, ny)
            ? w.map.industryAt(nx, ny)
            : null;
        if (place != null &&
            (place.town != null || w.entranceOf(place) == w.cellOf(x, y))) {
          paintRoadStub(c, r, x, y, d);
        }
      }
    }
  }
}

/// S29: tunnel portals along curves and lamp posts by the big roads, as
/// objects sorted with the rest of the map.
void addWayObjects(
  MagNet net,
  Canvas c,
  List<(double, void Function())> objects,
  int x0,
  int y0,
  int x1,
  int y1,
) {
  bool seen(Offset p) =>
      p.dx >= x0 - 1 && p.dy >= y0 - 1 && p.dx <= x1 + 2 && p.dy <= y1 + 2;
  for (final (p, out) in net.portals) {
    if (!seen(p)) continue;
    objects.add((p.dx + p.dy + .3, () => paintPortalAt(c, p, out)));
  }
  for (final p in net.lamps) {
    if (!seen(p)) continue;
    objects.add((p.dx + p.dy, () => paintLampPost(c, p)));
  }
}

/// A street lamp: a slim post and its head.
void paintLampPost(Canvas c, Offset p) {
  final foot = MagIso.project(p.dx, p.dy);
  final head = MagIso.project(p.dx, p.dy, 14);
  c
    ..drawLine(
      foot,
      head,
      Paint()
        ..strokeWidth = 1.2
        ..color = const Color(0xFF5B646C),
    )
    ..drawCircle(head, 1.8, Paint()..color = const Color(0xFFE8ECEF));
}

/// The lamps alight at night (screen space).
void paintLampGlow(Canvas c, double night, int x0, int y0, int x1, int y1) {
  final net = MagNet.current;
  if (net == null || night <= .05) return;
  for (final p in net.lamps) {
    if (p.dx < x0 - 1 || p.dy < y0 - 1 || p.dx > x1 + 2 || p.dy > y1 + 2) {
      continue;
    }
    final head = MagIso.project(p.dx, p.dy, 14);
    final ground = MagIso.project(p.dx, p.dy);
    c
      ..drawOval(
        Rect.fromCenter(center: ground, width: 26, height: 13),
        Paint()..color = Color.fromRGBO(255, 214, 140, .18 * night),
      )
      ..drawCircle(
        head,
        5,
        Paint()..color = Color.fromRGBO(255, 220, 150, .35 * night),
      )
      ..drawCircle(
        head,
        2,
        Paint()..color = Color.fromRGBO(255, 244, 205, night),
      );
  }
}
