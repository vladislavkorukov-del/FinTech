import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_iso.dart';
import 'mag_shapes.dart';

/// Structures by the ways (in iso space): tunnel rock and portals,
/// depots, the gem of a rich deposit.

/// The rock over a tunnel (in iso space, under the cell's peaks): a
/// rounded mound covering the whole cell, so the way inside is hidden.
void paintTunnelCover(Canvas c, int x, int y) {
  final n = MagIso.project(x.toDouble(), y.toDouble());
  final e = MagIso.project(x + 1.0, y.toDouble());
  final s = MagIso.project(x + 1.0, y + 1.0);
  final wv = MagIso.project(x.toDouble(), y + 1.0);
  final top = MagIso.project(x + .5, y + .5, 13);
  Path face(List<Offset> p) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    for (var i = 1; i < p.length; i++) {
      final a = p[i - 1], b = p[i];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2 - 3);
      path.quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
    }
    return path..close();
  }

  c.drawPath(face([wv, n, e, top]), Paint()..color = const Color(0xFFB0AEA6));
  c.drawPath(face([wv, top, s]), Paint()..color = const Color(0xFF9C9A92));
  c.drawPath(face([s, top, e]), Paint()..color = const Color(0xFF7F7D76));
  // A few cracks and a tuft of grass make it rock, not paper.
  final crack = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = .8
    ..color = const Color(0x55403E3A);
  c.drawLine(
    Offset.lerp(top, s, .3)!,
    Offset.lerp(top, s, .62)! + const Offset(3, 0),
    crack,
  );
  c.drawOval(
    Rect.fromCenter(center: top + const Offset(-4, 3), width: 8, height: 3),
    Paint()..color = const Color(0xAA7DA857),
  );
}

/// A tunnel portal where a way leaves the hills (in iso space): a stone
/// facade in the hillside with an arched mouth of dressed stone, a
/// keystone, a cornice and short wing walls. Portals facing away from the
/// viewer are hidden by the hill itself.
void paintPortal(Canvas c, MagWorld w, int cell, int outDir) {
  if (outDir == 0 || outDir == 3) return;
  final ex = w.cx(cell) + .5 + MagDir.dx[outDir] * .5;
  final ey = w.cy(cell) + .5 + MagDir.dy[outDir] * .5;
  // Across the way: along y for a portal facing +x, along x for +y.
  final ax = outDir == 2 ? 1.0 : 0.0, ay = outDir == 1 ? 1.0 : 0.0;
  final ox = MagDir.dx[outDir].toDouble(), oy = MagDir.dy[outDir].toDouble();
  Offset p(double t, double z, [double out = 0]) =>
      MagIso.project(ex + ax * t + ox * out, ey + ay * t + oy * out, z);
  Path poly(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    return path..close();
  }

  const half = .44, h = 21.0, mouth = .25, spring = 8.0, crown = 16.0;
  // The hillside the facade sits in.
  final hill = Path()
    ..moveTo(p(-half - .1, 0).dx, p(-half - .1, 0).dy)
    ..quadraticBezierTo(
      p(-half - .05, h + 6).dx,
      p(-half - .05, h + 6).dy,
      p(0, h + 9).dx,
      p(0, h + 9).dy,
    )
    ..quadraticBezierTo(
      p(half + .05, h + 6).dx,
      p(half + .05, h + 6).dy,
      p(half + .1, 0).dx,
      p(half + .1, 0).dy,
    )
    ..close();
  c.drawPath(hill, Paint()..color = const Color(0xFF8F8D86));
  // Wing walls, stepping down outwards.
  for (final side in [-1.0, 1.0]) {
    c.drawPath(
      poly([
        p(side * half, 0),
        p(side * half, h * .7),
        p(side * (half + .06), 5, .2),
        p(side * (half + .06), 0, .2),
      ]),
      Paint()..color = const Color(0xFF8A857C),
    );
  }
  // The facade.
  c.drawPath(
    poly([p(-half, 0), p(-half, h), p(half, h), p(half, 0)]),
    Paint()..color = const Color(0xFFA9A397),
  );
  // Courses of stone.
  final joint = Paint()
    ..strokeWidth = .6
    ..color = const Color(0x55534F48);
  for (final z in [5.0, 10.0, 15.0]) {
    c.drawLine(p(-half, z), p(half, z), joint);
  }
  // The arch: dressed stones around a dark mouth.
  Path arch(double m, double sp, double cr) => Path()
    ..moveTo(p(-m, 0).dx, p(-m, 0).dy)
    ..lineTo(p(-m, sp).dx, p(-m, sp).dy)
    ..cubicTo(
      p(-m, cr).dx,
      p(-m, cr).dy,
      p(m, cr).dx,
      p(m, cr).dy,
      p(m, sp).dx,
      p(m, sp).dy,
    )
    ..lineTo(p(m, 0).dx, p(m, 0).dy)
    ..close();
  c.drawPath(
    arch(mouth + .06, spring + 1, crown + 5),
    Paint()..color = const Color(0xFFD3CCBC),
  );
  final dark = arch(mouth, spring, crown);
  final b = dark.getBounds();
  c.drawPath(
    dark,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0E1012), Color(0xFF2A2F33)],
      ).createShader(b),
  );
  // Keystone and cornice.
  final k = p(0, crown + 3);
  c.drawPath(
    poly([
      k + const Offset(-2.6, -4),
      k + const Offset(2.6, -4),
      k + const Offset(1.8, 2),
      k + const Offset(-1.8, 2),
    ]),
    Paint()..color = const Color(0xFFE2DBCB),
  );
  c.drawLine(
    p(-half - .03, h),
    p(half + .03, h),
    Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF6F6A61),
  );
}

/// A depot (VEH-10, in iso space): a small garage with a wide door beside
/// its road cell.
void paintDepot(Canvas c, MagWorld w, int cell) {
  final x = w.cx(cell) + .5, y = w.cy(cell) + .5;
  // Beside the road: towards the first side with no road.
  var ox = 0.0, oy = -.32;
  for (var d = 0; d < 4; d++) {
    final nx = w.cx(cell) + MagDir.dx[d], ny = w.cy(cell) + MagDir.dy[d];
    if (w.map.inside(nx, ny) && w.roads[w.cellOf(nx, ny)] == 0) {
      ox = MagDir.dx[d] * .32;
      oy = MagDir.dy[d] * .32;
      break;
    }
  }
  MagShapes.box(
    c,
    x: x + ox,
    y: y + oy,
    length: .46,
    width: .4,
    h: 11,
    color: const Color(0xFF8C99A6),
    top: const Color(0xFF5C6B78),
  );
  final door = MagIso.project(x + ox, y + oy + .2, 0);
  c.drawRect(
    Rect.fromCenter(center: door - const Offset(0, 4), width: 9, height: 7),
    Paint()..color = const Color(0xFF2E3A44),
  );
  final sign = MagIso.project(x + ox, y + oy, 15);
  c.drawCircle(sign, 4, Paint()..color = MagPaletteSign.depot);
}

/// A gem by the name of a rich deposit (MAP-10).
void paintGem(Canvas c, Offset p) {
  final path = Path()
    ..moveTo(p.dx, p.dy - 5)
    ..lineTo(p.dx + 4.5, p.dy - 1)
    ..lineTo(p.dx, p.dy + 5)
    ..lineTo(p.dx - 4.5, p.dy - 1)
    ..close();
  c.drawPath(path, Paint()..color = const Color(0xFF3FA7D6));
  c.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = const Color(0xFFFFFFFF),
  );
}

abstract final class MagPaletteSign {
  static const depot = Color(0xFFE09A3E);
}

/// A city terminal (CITY-13, in iso space): a loading shed with a teal
/// awning by its road cell.
void paintTerminal(Canvas c, MagWorld w, int cell) {
  final x = w.cx(cell) + .5, y = w.cy(cell) + .5;
  var ox = 0.0, oy = .32;
  for (var d = 0; d < 4; d++) {
    final nx = w.cx(cell) + MagDir.dx[d], ny = w.cy(cell) + MagDir.dy[d];
    if (w.map.inside(nx, ny) && w.roads[w.cellOf(nx, ny)] == 0) {
      ox = MagDir.dx[d] * .3;
      oy = MagDir.dy[d] * .3;
      break;
    }
  }
  MagShapes.box(
    c,
    x: x + ox,
    y: y + oy,
    length: .5,
    width: .36,
    h: 8,
    color: const Color(0xFFE9E2D2),
  );
  MagShapes.box(
    c,
    x: x + ox,
    y: y + oy,
    length: .58,
    width: .44,
    z0: 8,
    h: 2,
    color: const Color(0xFF2BB59A),
    top: const Color(0xFF5FD0B8),
  );
}

/// Regions not open yet (MAP-08, under the ground transform): a grey veil
/// with the price in the middle.
void paintClosedRegions(Canvas c, MagWorld w) {
  final s = (w.size / 3).ceil().toDouble();
  for (var r = 0; r < 9; r++) {
    if (w.openRegions.contains(r)) continue;
    final rect = Rect.fromLTWH(
      (r % 3) * s,
      (r ~/ 3) * s,
      s,
      s,
    ).intersect(Rect.fromLTWH(0, 0, w.size.toDouble(), w.size.toDouble()));
    c.drawRect(rect, Paint()..color = const Color(0x7A303A40));
    c.drawRect(
      rect.deflate(.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .12
        ..color = const Color(0x99FFFFFF),
    );
  }
}

/// An own business's level shows (PROD-19): annexes and a tank grow by
/// its side, and at the top level a golden band.
void paintLevelStages(Canvas c, MagIndustry i) {
  final x = i.x.toDouble(), y = i.y.toDouble(), s = i.size.toDouble();
  if (i.level >= 2) {
    MagShapes.box(
      c,
      x: x + s - .3,
      y: y + .3,
      length: .4,
      width: .4,
      h: 7,
      color: const Color(0xFFD7DCDF),
      top: const Color(0xFF8C99A6),
    );
  }
  if (i.level >= 3) {
    MagShapes.cylinder(
      c,
      x: x + .3,
      y: y + s - .3,
      r: .2,
      h: 12,
      color: const Color(0xFFB9C2C8),
      dome: true,
    );
  }
  if (i.level >= 4) {
    MagShapes.box(
      c,
      x: x + .35,
      y: y + .35,
      length: .5,
      width: .45,
      h: 10,
      color: const Color(0xFFE2E6E8),
      top: const Color(0xFF2BB59A),
    );
  }
  if (i.level >= 5) {
    final p = MagIso.project(x + s / 2, y + s / 2, 46);
    c.drawCircle(p, 5, Paint()..color = const Color(0xFFD4A017));
    c.drawCircle(
      p,
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFFFFFFF),
    );
  }
}
