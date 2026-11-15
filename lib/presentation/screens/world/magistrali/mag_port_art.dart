import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_iso.dart';
import 'mag_shapes.dart';

/// Stage S25 on the map (iso space): a container terminal's gantry crane
/// and stacks (PORT-01), a rail signal with its lamp (SIG-01), a road
/// interchange — an overpass on piers (JCT-01) — and the lit windows of
/// places working a night shift (NIGHT-01).

const _boxColors = [
  Color(0xFFD64B5C),
  Color(0xFF2F6FA8),
  Color(0xFFE8B23E),
  Color(0xFF2BB59A),
];

/// A gantry crane over the berth and containers stacked on the shore.
void paintContainerTerminal(Canvas c, MagWorld w, int cell) {
  final cx = w.cx(cell), cy = w.cy(cell);
  // The shore: the first neighbour that is land.
  var sx = 0, sy = 1;
  for (var d = 0; d < 4; d++) {
    final nx = cx + MagDir.dx[d], ny = cy + MagDir.dy[d];
    if (w.map.inside(nx, ny) && !w.isWater(w.cellOf(nx, ny))) {
      sx = MagDir.dx[d];
      sy = MagDir.dy[d];
      break;
    }
  }
  final x = cx + .5, y = cy + .5;
  // Stacks on the quay.
  for (var k = 0; k < 4; k++) {
    final along = (k % 2 - .5) * .36;
    MagShapes.box(
      c,
      x: x + sx * .62 + sy * along,
      y: y + sy * .62 + sx * along,
      length: .26,
      width: .14,
      z0: k < 2 ? 0 : 5,
      h: 5,
      color: _boxColors[k],
    );
  }
  // The crane: two legs, a boom reaching over the water.
  const orange = Color(0xFFE0743C);
  for (final side in const [-.3, .3]) {
    MagShapes.box(
      c,
      x: x + sx * .35 + sy * side,
      y: y + sy * .35 + sx * side,
      length: .06,
      width: .06,
      h: 26,
      color: orange,
    );
  }
  MagShapes.box(
    c,
    x: x + sx * .1,
    y: y + sy * .1,
    ax: sx.toDouble() == 0 ? 0 : 1,
    ay: sx.toDouble() == 0 ? 1 : 0,
    length: 1.0,
    width: .12,
    z0: 26,
    h: 4,
    color: orange,
    top: const Color(0xFFF0A070),
  );
}

/// A signal post by the track; red while the block ahead is taken.
void paintSignal(Canvas c, MagWorld w, int cell) {
  final x = w.cx(cell) + .82, y = w.cy(cell) + .18;
  MagShapes.box(
    c,
    x: x,
    y: y,
    length: .05,
    width: .05,
    h: 16,
    color: const Color(0xFF4A5560),
  );
  final head = MagIso.project(x, y, 18);
  c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: head, width: 6, height: 10),
      const Radius.circular(2),
    ),
    Paint()..color = const Color(0xFF2B2E33),
  );
  final red = w.signalRed(cell);
  final lamp = red ? const Color(0xFFFF4D4D) : const Color(0xFF4DE38A);
  final at = head + Offset(0, red ? -2.2 : 2.2);
  c.drawCircle(at, 4, Paint()..color = lamp.withValues(alpha: .3));
  c.drawCircle(at, 1.8, Paint()..color = lamp);
}

/// An overpass over a crossing: a concrete deck on two piers and a
/// ring of kerb around the junction.
void paintInterchange(Canvas c, MagWorld w, int cell) {
  final x = w.cx(cell) + .5, y = w.cy(cell) + .5;
  final ring = Rect.fromCenter(
    center: MagIso.project(x, y),
    width: 48,
    height: 24,
  );
  c.drawOval(
    ring,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xCCEDEFF2),
  );
  // Along the busier direction: the one with roads on both sides.
  final alongX =
      w.hasRoad(w.cx(cell) - 1, w.cy(cell)) &&
      w.hasRoad(w.cx(cell) + 1, w.cy(cell));
  for (final o in const [-.36, .36]) {
    MagShapes.box(
      c,
      x: x + (alongX ? o : 0),
      y: y + (alongX ? 0 : o),
      length: .1,
      width: .18,
      h: 9,
      color: const Color(0xFFB8BEC6),
    );
  }
  MagShapes.box(
    c,
    x: x,
    y: y,
    ax: alongX ? 1 : 0,
    ay: alongX ? 0 : 1,
    length: 1.0,
    width: .3,
    z0: 9,
    h: 2.5,
    color: const Color(0xFFC9CED5),
    top: const Color(0xFF6D7680),
  );
}

/// Windows lit all night in places on a night shift.
void paintNightShifts(
  Canvas c,
  MagWorld w,
  double night,
  int x0,
  int y0,
  int x1,
  int y1,
) {
  if (w.nightShifts.isEmpty) return;
  for (final id in w.nightShifts) {
    final i = w.map.industry(id);
    if (i == null ||
        i.right < x0 - 1 ||
        i.left > x1 + 1 ||
        i.bottom < y0 - 1 ||
        i.top > y1 + 1) {
      continue;
    }
    final n = i.size * 4;
    for (var k = 0; k < n; k++) {
      final fx = ((k * 37 + id * 11) % 100) / 100;
      final fy = ((k * 61 + id * 23) % 100) / 100;
      final p = MagIso.project(
        i.left + .2 + fx * (i.size - .4),
        i.top + .2 + fy * (i.size - .4),
        8 + (k % 3) * 4,
      );
      c.drawCircle(
        p,
        5,
        Paint()..color = Color.fromRGBO(255, 200, 110, .25 * night),
      );
      c.drawRect(
        Rect.fromCenter(center: p, width: 3, height: 3.4),
        Paint()..color = Color.fromRGBO(255, 230, 150, .95 * night),
      );
    }
  }
}
