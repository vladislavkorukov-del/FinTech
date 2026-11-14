import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_iso.dart';
import 'mag_shapes.dart';

/// Track on one cell (under the ground transform: a cell is 1×1): a ballast
/// bed, sleepers and two steel rails towards each joined neighbour. A
/// station cell gets a platform beside the track.
void paintRail(Canvas c, int mask, int x, int y, {bool station = false}) {
  final cx = x + .5, cy = y + .5;
  if (station) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + .04, y + .04, .92, .92),
        const Radius.circular(.08),
      ),
      Paint()..color = const Color(0xFFD9D4C7),
    );
  }
  final arms = [
    for (var d = 0; d < 4; d++)
      if (mask & (1 << d) != 0) d,
  ];
  if (arms.isEmpty) arms.addAll([1, 3]);
  final bed = Paint()..color = const Color(0xFF9C9488);
  final sleeper = Paint()..color = const Color(0xFF6E4E35);
  final steel = Paint()
    ..color = const Color(0xFF5A6066)
    ..strokeWidth = .045;
  for (final d in arms) {
    final dx = MagDir.dx[d].toDouble(), dy = MagDir.dy[d].toDouble();
    final ex = cx + dx * .5, ey = cy + dy * .5;
    // Ballast.
    final wx = dx == 0 ? .17 : 0.0, wy = dy == 0 ? .17 : 0.0;
    c.drawRect(
      Rect.fromLTRB(
        math.min(cx, ex) - wx,
        math.min(cy, ey) - wy,
        math.max(cx, ex) + wx,
        math.max(cy, ey) + wy,
      ),
      bed,
    );
    // Sleepers across the track.
    for (var k = 0; k < 3; k++) {
      final t = .08 + k * .16;
      final sx = cx + dx * t, sy = cy + dy * t;
      c.drawRect(
        Rect.fromCenter(
          center: Offset(sx, sy),
          width: dx == 0 ? .36 : .06,
          height: dy == 0 ? .36 : .06,
        ),
        sleeper,
      );
    }
    // Two rails.
    for (final s in [-.1, .1]) {
      c.drawLine(
        Offset(cx + dy.abs() * s, cy + dx.abs() * s),
        Offset(ex + dy.abs() * s, ey + dx.abs() * s),
        steel,
      );
    }
  }
}

/// A small station building beside its platform.
void paintStationHouse(Canvas c, int x, int y) {
  MagShapes.box(
    c,
    x: x + .78,
    y: y + .22,
    length: .3,
    width: .26,
    h: 9,
    color: const Color(0xFFF1E3C8),
  );
  MagShapes.roof(
    c,
    x: x + .78,
    y: y + .22,
    length: .34,
    width: .3,
    z0: 9,
    h: 5,
    color: const Color(0xFFB4533E),
    ridge: .1,
  );
}

/// A train: the locomotive at [cars].first, wagons behind, each a box on
/// the track facing its way; loaded wagons show the cargo colour.
void paintTrain(
  Canvas c,
  List<(double, double, int)> cars,
  MagTruckModel m,
  Color? load, {
  bool selected = false,
}) {
  // Back to front, so the engine is drawn over its first wagon.
  for (var k = cars.length - 1; k >= 0; k--) {
    final (x, y, dir) = cars[k];
    final along = dir == 1 || dir == 3;
    MagShapes.shadow(c, x, y, .32, .22);
    if (k == 0) {
      MagShapes.box(
        c,
        x: x,
        y: y,
        length: along ? .62 : .34,
        width: along ? .34 : .62,
        h: 9,
        color: Color(m.color),
      );
      // Cab and chimney.
      MagShapes.box(
        c,
        x: x - MagDir.dx[dir] * .18,
        y: y - MagDir.dy[dir] * .18,
        length: .26,
        width: .3,
        z0: 9,
        h: 6,
        color: const Color(0xFF2E3338),
      );
      MagShapes.cylinder(
        c,
        x: x + MagDir.dx[dir] * .18,
        y: y + MagDir.dy[dir] * .18,
        r: .06,
        z0: 9,
        h: m.id == 'steam' ? 7 : 2,
        color: const Color(0xFF1F2326),
      );
      if (selected) {
        c.drawOval(
          Rect.fromCenter(center: MagIso.project(x, y), width: 48, height: 24),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFF2BB59A),
        );
      }
    } else {
      MagShapes.box(
        c,
        x: x,
        y: y,
        length: along ? .6 : .32,
        width: along ? .32 : .6,
        h: 8,
        color: load ?? const Color(0xFF8E6F5A),
      );
    }
  }
}

/// Where a train's locomotive and wagons are: the engine where the train
/// is, each wagon one cell further back along the way it came.
List<(double, double, int)> trainCars(MagWorld w, MagVehicle v) {
  final (x, y) = w.positionOf(v);
  final out = <(double, double, int)>[(x, y, v.dir)];
  final path = v.path;
  final driving =
      v.state == MagVehicleState.driving && v.pathIndex + 1 < path.length;
  for (var k = 1; k <= v.wagons; k++) {
    if (!driving) {
      // Standing: the wagons line up behind on the platform side.
      out.add((
        x - MagDir.dx[v.dir] * .55 * k,
        y - MagDir.dy[v.dir] * .55 * k,
        v.dir,
      ));
      continue;
    }
    final i = v.pathIndex - k;
    if (i < 0) {
      final c = path.first;
      out.add((w.cx(c) + .5, w.cy(c) + .5, v.dir));
      continue;
    }
    final a = path[i], b = path[i + 1];
    final ax = w.cx(a) + .5, ay = w.cy(a) + .5;
    final bx = w.cx(b) + .5, by = w.cy(b) + .5;
    final d = b - a == 1 ? 1 : (a - b == 1 ? 3 : (b > a ? 2 : 0));
    out.add((ax + (bx - ax) * v.progress, ay + (by - ay) * v.progress, d));
  }
  return out;
}

/// A wooden pier on a water cell (under the ground transform).
void paintPier(Canvas c, int x, int y) {
  c.drawRect(
    Rect.fromLTWH(x + .12, y + .12, .76, .76),
    Paint()..color = const Color(0xFF9C7A54),
  );
  final plank = Paint()
    ..color = const Color(0xFF7A5A3C)
    ..strokeWidth = .025;
  for (var k = 1; k < 5; k++) {
    c.drawLine(
      Offset(x + .12, y + .12 + k * .152),
      Offset(x + .88, y + .12 + k * .152),
      plank,
    );
  }
}

/// A small crane at a port.
void paintPortCrane(Canvas c, int x, int y) {
  MagShapes.box(
    c,
    x: x + .25,
    y: y + .25,
    length: .06,
    width: .06,
    h: 18,
    color: const Color(0xFFE8B23E),
    outline: false,
  );
  MagShapes.box(
    c,
    x: x + .45,
    y: y + .25,
    length: .45,
    width: .05,
    z0: 17,
    h: 1.5,
    color: const Color(0xFFE8B23E),
    outline: false,
  );
}

/// A vessel: a hull with a cabin; loaded, its hold shows the cargo.
void paintShip(
  Canvas c,
  double x,
  double y,
  int dir,
  MagTruckModel m,
  Color? load, {
  bool selected = false,
}) {
  final along = dir == 1 || dir == 3;
  final big = m.capacity > 100;
  final len = big ? .9 : .7, wid = big ? .42 : .34;
  MagShapes.box(
    c,
    x: x,
    y: y,
    length: along ? len : wid,
    width: along ? wid : len,
    h: 4,
    color: Color(m.color),
  );
  if (load != null) {
    MagShapes.box(
      c,
      x: x + MagDir.dx[dir] * .1,
      y: y + MagDir.dy[dir] * .1,
      length: along ? len * .5 : wid * .7,
      width: along ? wid * .7 : len * .5,
      z0: 4,
      h: 3,
      color: load,
      outline: false,
    );
  }
  MagShapes.box(
    c,
    x: x - MagDir.dx[dir] * len * .32,
    y: y - MagDir.dy[dir] * len * .32,
    length: .18,
    width: .2,
    z0: 4,
    h: big ? 8 : 6,
    color: const Color(0xFFF1F3F4),
  );
  if (selected) {
    c.drawOval(
      Rect.fromCenter(center: MagIso.project(x, y), width: 52, height: 26),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF2BB59A),
    );
  }
}
