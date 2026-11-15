import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mag_iso.dart';
import 'mag_shapes.dart';

/// The machine-tool works (PROD-10, S21): a long hall with a saw-tooth
/// roof of skylights, a gantry crane over the yard, a big gear on the
/// gable and finished machines waiting under tarpaulins.
void paintMachineWorks(Canvas c, double x, double y) {
  // The hall.
  MagShapes.box(
    c,
    x: x + 1.05,
    y: y + .8,
    length: 1.7,
    width: 1.1,
    h: 16,
    color: const Color(0xFF8FA3B4),
  );
  // Saw-tooth roof: three rows of skylights.
  for (var k = 0; k < 3; k++) {
    MagShapes.roof(
      c,
      x: x + .55 + k * .5,
      y: y + .8,
      length: .48,
      width: 1.12,
      z0: 16,
      h: 8,
      color: k.isEven ? const Color(0xFF5D7286) : const Color(0xFF6E8497),
      ridge: .1,
    );
  }
  // A big gear on the gable.
  final g = MagIso.project(x + 1.9, y + .55, 10);
  final teeth = Path();
  for (var k = 0; k < 16; k++) {
    final a = k * math.pi / 8;
    final r = k.isEven ? 7.5 : 5.8;
    final p = g + Offset(math.cos(a) * r, math.sin(a) * r * .85);
    k == 0 ? teeth.moveTo(p.dx, p.dy) : teeth.lineTo(p.dx, p.dy);
  }
  teeth.close();
  c.drawPath(teeth, Paint()..color = const Color(0xFFE8B23E));
  c.drawCircle(g, 2.4, Paint()..color = const Color(0xFF5D7286));
  // The gantry crane over the yard.
  for (final dx in [.15, .75]) {
    MagShapes.box(
      c,
      x: x + dx,
      y: y + 1.75,
      length: .07,
      width: .07,
      h: 22,
      color: const Color(0xFFE0743C),
      outline: false,
    );
  }
  MagShapes.box(
    c,
    x: x + .45,
    y: y + 1.75,
    length: .7,
    width: .08,
    z0: 22,
    h: 2.5,
    color: const Color(0xFFE0743C),
    outline: false,
  );
  // Machines under tarpaulins.
  for (final (dx, dy) in [(.35, 1.6), (.65, 1.8)]) {
    MagShapes.box(
      c,
      x: x + dx,
      y: y + dy,
      length: .22,
      width: .18,
      h: 5,
      color: const Color(0xFF3F6E5E),
    );
  }
}
