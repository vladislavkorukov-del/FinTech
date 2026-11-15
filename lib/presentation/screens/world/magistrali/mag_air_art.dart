import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_iso.dart';
import 'mag_shapes.dart';

/// Stage S22: an airport — a runway with markings and a control tower.
void paintAirport(Canvas c, MagWorld w, int cell) {
  final x = w.cx(cell).toDouble(), y = w.cy(cell).toDouble();
  c.save();
  c.transform(MagIso.ground);
  c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(x + .05, y + .05, .9, .9),
      const Radius.circular(.08),
    ),
    Paint()..color = const Color(0xFF5E6870),
  );
  for (var k = 0; k < 4; k++) {
    c.drawRect(
      Rect.fromLTWH(x + .14 + k * .2, y + .47, .12, .06),
      Paint()..color = const Color(0xFFF3F1EA),
    );
  }
  c.drawRect(
    Rect.fromLTWH(x + .08, y + .1, .84, .03),
    Paint()..color = const Color(0xFFE8B23E),
  );
  c.restore();
  MagShapes.box(
    c,
    x: x + .85,
    y: y + .82,
    length: .14,
    width: .14,
    h: 18,
    color: const Color(0xFFE8E3D8),
  );
  MagShapes.box(
    c,
    x: x + .85,
    y: y + .82,
    length: .2,
    width: .2,
    z0: 18,
    h: 5,
    color: const Color(0xFF6FB3C9),
  );
}

/// An aircraft in the air: its shadow on the ground, the plane above.
void paintPlane(
  Canvas c,
  double x,
  double y,
  Offset heading,
  MagTruckModel m, {
  bool selected = false,
  double altitude = 34,
}) {
  final ground = MagIso.project(x, y);
  final air = MagIso.project(x, y, altitude);
  // The heading on screen.
  final ahead = MagIso.project(x + heading.dx, y + heading.dy) - ground;
  final a = math.atan2(ahead.dy, ahead.dx);
  final big = m.capacity > 20;
  final len = big ? 34.0 : 24.0, span = big ? 40.0 : 28.0;
  void body(Offset at, Paint fuselage, Paint wing, double s) {
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(a);
    c.scale(1, .62); // the isometric squash
    c.drawPath(
      Path()..addPolygon([
        Offset(-len * .1 * s, -span / 2 * s),
        Offset(len * .12 * s, -span / 2 * s),
        Offset(len * .2 * s, 0),
        Offset(len * .12 * s, span / 2 * s),
        Offset(-len * .1 * s, span / 2 * s),
        Offset.zero,
      ], true),
      wing,
    );
    c.drawPath(
      Path()..addPolygon([
        Offset(-len * .5 * s, -span * .2 * s),
        Offset(-len * .38 * s, -span * .2 * s),
        Offset(-len * .32 * s, 0),
        Offset(-len * .38 * s, span * .2 * s),
        Offset(-len * .5 * s, span * .2 * s),
      ], true),
      wing,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: len * s,
          height: len * .22 * s,
        ),
        Radius.circular(len * .11 * s),
      ),
      fuselage,
    );
    c.restore();
  }

  body(
    ground,
    Paint()..color = const Color(0x33152420),
    Paint()..color = const Color(0x26152420),
    1,
  );
  if (selected) {
    c.drawCircle(
      air,
      len * .9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF2BB59A),
    );
  }
  body(
    air,
    Paint()..color = const Color(0xFFF4F2EC),
    Paint()..color = Color(m.color),
    1,
  );
  // A little window line and the nose.
  c.drawCircle(
    air + Offset(math.cos(a) * len * .45, math.sin(a) * len * .28),
    1.8,
    Paint()..color = const Color(0xFF2F5D75),
  );
}
