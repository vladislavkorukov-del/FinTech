import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_iso.dart';
import 'mag_shapes.dart';

/// Stage S23: a lakeside resort — a white hotel with a blue roof, beach
/// umbrellas and a small pier.
void paintLakeResort(Canvas c, double x, double y) {
  MagShapes.box(
    c,
    x: x + .8,
    y: y + .7,
    length: 1.1,
    width: .7,
    h: 22,
    color: const Color(0xFFF7F5EF),
  );
  MagShapes.roof(
    c,
    x: x + .8,
    y: y + .7,
    length: 1.16,
    width: .76,
    z0: 22,
    h: 8,
    color: const Color(0xFF3F8FC2),
    ridge: .3,
  );
  // Balconies.
  for (var k = 0; k < 3; k++) {
    MagShapes.box(
      c,
      x: x + .45 + k * .35,
      y: y + 1.07,
      length: .22,
      width: .05,
      z0: 7 + 0.0,
      h: 1.5,
      color: const Color(0xFF3F8FC2),
      outline: false,
    );
  }
  // Umbrellas on the beach.
  for (final (dx, dy, col) in [
    (.35, 1.65, 0xFFE0566B),
    (.85, 1.75, 0xFFE8B23E),
    (1.4, 1.6, 0xFF2BB59A),
  ]) {
    MagShapes.box(
      c,
      x: x + dx,
      y: y + dy,
      length: .03,
      width: .03,
      h: 8,
      color: const Color(0xFFE8E3D8),
      outline: false,
    );
    final top = MagIso.project(x + dx, y + dy, 8);
    c.drawOval(
      Rect.fromCenter(center: top, width: 14, height: 6),
      Paint()..color = Color(col),
    );
  }
}

/// Stage S23: a ski resort — a wooden chalet with a steep roof and a
/// chair lift climbing the hill.
void paintSkiResort(Canvas c, double x, double y) {
  MagShapes.box(
    c,
    x: x + .7,
    y: y + .9,
    length: .9,
    width: .7,
    h: 14,
    color: const Color(0xFF9A6A3F),
  );
  MagShapes.roof(
    c,
    x: x + .7,
    y: y + .9,
    length: .98,
    width: .78,
    z0: 14,
    h: 16,
    color: const Color(0xFF5E3B26),
    ridge: .45,
  );
  // Snow on the roof edge.
  MagShapes.box(
    c,
    x: x + .7,
    y: y + .9,
    length: .98,
    width: .78,
    z0: 14,
    h: 1.5,
    color: const Color(0xFFF4F7FA),
    outline: false,
  );
  // The lift: poles and a cable up to the back corner.
  final poles = [(1.5, 1.6), (1.6, 1.0), (1.7, .35)];
  Offset? last;
  for (final (dx, dy) in poles) {
    MagShapes.box(
      c,
      x: x + dx,
      y: y + dy,
      length: .05,
      width: .05,
      h: 18 + (1.6 - dy) * 10,
      color: const Color(0xFF8E9AA0),
      outline: false,
    );
    final top = MagIso.project(x + dx, y + dy, 18 + (1.6 - dy) * 10);
    if (last != null) {
      c.drawLine(
        last,
        top,
        Paint()
          ..color = const Color(0xFF5B6B70)
          ..strokeWidth = 1,
      );
    }
    last = top;
  }
}

/// DIS-01 (S23): a broken road cell — a crack across it and two striped
/// barriers.
void paintDamage(Canvas c, MagWorld w, int cell) {
  final x = w.cx(cell).toDouble(), y = w.cy(cell).toDouble();
  c.save();
  c.transform(MagIso.ground);
  c.drawPath(
    Path()
      ..moveTo(x + .2, y + .3)
      ..lineTo(x + .45, y + .5)
      ..lineTo(x + .38, y + .62)
      ..lineTo(x + .8, y + .78),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .06
      ..color = const Color(0xFF2B2E33),
  );
  c.restore();
  for (final (dx, dy) in [(.25, .75), (.75, .25)]) {
    MagShapes.box(
      c,
      x: x + dx,
      y: y + dy,
      length: .3,
      width: .06,
      z0: 3,
      h: 4,
      color: const Color(0xFFE0743C),
    );
    MagShapes.box(
      c,
      x: x + dx,
      y: y + dy,
      length: .12,
      width: .065,
      z0: 3,
      h: 4,
      color: const Color(0xFFF4F2EC),
      outline: false,
    );
  }
}
