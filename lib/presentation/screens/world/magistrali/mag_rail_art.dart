import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_curve.dart';
import 'mag_iso.dart';
import 'mag_shapes.dart';

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
/// is, each wagon a little further back along the curve it came by.
List<(double, double, int)> trainCars(MagWorld w, MagVehicle v) => [
  for (var k = 0; k <= v.wagons; k++)
    () {
      final (p, d) = vehiclePose(w, v, back: k * .9);
      return (p.dx, p.dy, dirOf(d));
    }(),
];

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
