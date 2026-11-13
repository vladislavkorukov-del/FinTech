import 'dart:math' as math;
import 'dart:ui';

import 'mag_iso.dart';

/// Volume from flat shapes: boxes, roofs and cylinders projected into the
/// isometric view with soft shading (light from the upper left). Every
/// building and vehicle is drawn from these until painted sprites replace
/// them.
abstract final class MagShapes {
  static Color shade(Color c, double k) => Color.from(
    alpha: c.a,
    red: (c.r * k).clamp(0, 1),
    green: (c.g * k).clamp(0, 1),
    blue: (c.b * k).clamp(0, 1),
  );

  static Color lighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t)!;

  /// Brightness of a side face by its outward normal (nx, ny) on the grid.
  static double _light(double nx, double ny) {
    // Faces turned to +y (left on screen) are lit, +x (right) in shade.
    final len = math.sqrt(nx * nx + ny * ny);
    final t = ((ny - nx) / len + 1) / 2;
    return .66 + .22 * t;
  }

  static Path _poly(List<Offset> p) => Path()..addPolygon(p, true);

  /// A box standing on the ground: centre (x, y) in cells, its length along
  /// the unit direction (ax, ay), its width across, from height [z0] up by
  /// [h] (pixels at zoom 1).
  static void box(
    Canvas c, {
    required double x,
    required double y,
    double ax = 1,
    double ay = 0,
    required double length,
    required double width,
    double z0 = 0,
    required double h,
    required Color color,
    Color? top,
    bool outline = true,
  }) {
    final bx = -ay, by = ax; // across
    final hl = length / 2, hw = width / 2;
    final base = [
      (x + ax * hl + bx * hw, y + ay * hl + by * hw),
      (x + ax * hl - bx * hw, y + ay * hl - by * hw),
      (x - ax * hl - bx * hw, y - ay * hl - by * hw),
      (x - ax * hl + bx * hw, y - ay * hl + by * hw),
    ];
    final lo = [for (final p in base) MagIso.project(p.$1, p.$2, z0)];
    final hi = [for (final p in base) MagIso.project(p.$1, p.$2, z0 + h)];
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..color = shade(color, .55).withValues(alpha: .5);
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      final p = base[i], q = base[j];
      // Outward normal of edge p→q.
      final mx = (p.$1 + q.$1) / 2 - x, my = (p.$2 + q.$2) / 2 - y;
      if (mx + my <= 1e-6) continue; // turned away from the viewer
      final face = _poly([lo[i], lo[j], hi[j], hi[i]]);
      c.drawPath(face, Paint()..color = shade(color, _light(mx, my)));
      if (outline) c.drawPath(face, edge);
    }
    final lid = _poly(hi);
    c.drawPath(lid, Paint()..color = top ?? lighten(color, .12));
    if (outline) c.drawPath(lid, edge);
  }

  /// A hipped roof (a pyramid cut to a ridge) over a box footprint.
  static void roof(
    Canvas c, {
    required double x,
    required double y,
    double ax = 1,
    double ay = 0,
    required double length,
    required double width,
    required double z0,
    required double h,
    required Color color,
    double ridge = .45,
  }) {
    final bx = -ay, by = ax;
    final hl = length / 2, hw = width / 2, rl = hl * ridge;
    final base = [
      (x + ax * hl + bx * hw, y + ay * hl + by * hw),
      (x + ax * hl - bx * hw, y + ay * hl - by * hw),
      (x - ax * hl - bx * hw, y - ay * hl - by * hw),
      (x - ax * hl + bx * hw, y - ay * hl + by * hw),
    ];
    final r1 = (x + ax * rl, y + ay * rl), r2 = (x - ax * rl, y - ay * rl);
    final p = [for (final b in base) MagIso.project(b.$1, b.$2, z0)];
    final t1 = MagIso.project(r1.$1, r1.$2, z0 + h);
    final t2 = MagIso.project(r2.$1, r2.$2, z0 + h);
    // Faces: front end, side, back end, other side.
    final faces = [
      ([p[0], p[1], t1], ax, ay),
      ([p[1], p[2], t2, t1], -bx, -by),
      ([p[2], p[3], t2], -ax, -ay),
      ([p[3], p[0], t1, t2], bx, by),
    ];
    // Back faces first.
    faces.sort((a, b) => (a.$2 + a.$3).compareTo(b.$2 + b.$3));
    for (final (pts, nx, ny) in faces) {
      final k = nx + ny < 0 ? .95 : _light(nx, ny) + .1;
      c.drawPath(_poly(pts), Paint()..color = shade(color, k));
    }
  }

  /// A vertical cylinder (silo, tank, chimney) with an optional dome.
  static void cylinder(
    Canvas c, {
    required double x,
    required double y,
    required double r,
    double z0 = 0,
    required double h,
    required Color color,
    bool dome = false,
  }) {
    final base = MagIso.project(x, y, z0), top = MagIso.project(x, y, z0 + h);
    final w = r * 2 * MagIso.hw * 1.414, e = r * 2 * MagIso.hh * 1.414;
    final body = Path()
      ..addArc(Rect.fromCenter(center: base, width: w, height: e), 0, math.pi)
      ..lineTo(top.dx - w / 2, top.dy)
      ..arcTo(
        Rect.fromCenter(center: top, width: w, height: e),
        math.pi,
        -math.pi,
        false,
      )
      ..close();
    c.drawPath(
      body,
      Paint()
        ..shader = Gradient.linear(
          Offset(base.dx - w / 2, 0),
          Offset(base.dx + w / 2, 0),
          [lighten(color, .15), shade(color, .7)],
        ),
    );
    c.drawOval(
      Rect.fromCenter(center: top, width: w, height: e),
      Paint()..color = lighten(color, .2),
    );
    if (dome) {
      c.drawArc(
        Rect.fromCenter(center: top, width: w, height: w * .9),
        math.pi,
        math.pi,
        true,
        Paint()..color = lighten(color, .1),
      );
    }
  }

  /// A soft shadow on the ground under a footprint.
  static void shadow(Canvas c, double x, double y, double rx, double ry) {
    final p = MagIso.project(x + .12, y + .12);
    c.drawOval(
      Rect.fromCenter(
        center: p,
        width: (rx + ry) * MagIso.hw * 1.1,
        height: (rx + ry) * MagIso.hh * 1.1,
      ),
      Paint()
        ..color = const Color(0x33203024)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }
}
