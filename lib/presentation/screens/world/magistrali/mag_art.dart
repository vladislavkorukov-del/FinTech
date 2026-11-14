import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_iso.dart';
import 'mag_shapes.dart';
import 'mag_sprites.dart';

/// Finora's palette for the transport game: natural map tones, bright
/// vehicles, mint and teal accents.
abstract final class MagPalette {
  static const mint = Color(0xFF2BB59A);
  static const teal = Color(0xFF1C8C86);
  static const ink = Color(0xFF233238);
  static const sky = Color(0xFFDDEFE6);
  static const card = Color(0xF7FFFFFF);

  static Color cargo(MagCargo c) => switch (c) {
    MagCargo.grain => const Color(0xFFE8C14A),
    MagCargo.wood => const Color(0xFF9A6A3A),
    MagCargo.ore => const Color(0xFF7C8796),
    MagCargo.food => const Color(0xFFE86A5A),
    MagCargo.goods => const Color(0xFF4FB3C9),
  };
}

double _hash(int x, int y, int seed) {
  var n = x * 73856093 ^ y * 19349663 ^ seed * 83492791;
  n = (n ^ (n >> 13)) * 1274126177;
  return ((n ^ (n >> 16)) & 0xffff) / 0xffff;
}

/// Ground of one cell (drawn under the ground transform: one cell = 1).
void paintGround(Canvas c, MagMap map, int x, int y) {
  final t = map.at(x, y);
  final h = _hash(x, y, map.seed);
  final water = t == MagTerrain.river || t == MagTerrain.lake;
  var color = switch (t) {
    MagTerrain.grass => Color.lerp(
      const Color(0xFF9FCF72),
      const Color(0xFF8CC266),
      h,
    )!,
    MagTerrain.forest => Color.lerp(
      const Color(0xFF7DB45C),
      const Color(0xFF71A853),
      h,
    )!,
    MagTerrain.hill => Color.lerp(
      const Color(0xFFB7B47C),
      const Color(0xFFA9A86F),
      h,
    )!,
    MagTerrain.river => const Color(0xFF63B9DA),
    MagTerrain.lake => const Color(0xFF4FA6D2),
  };
  if (water) {
    // Shallows next to land.
    var shore = false;
    for (var d = 0; d < 4; d++) {
      final nx = x + MagDir.dx[d], ny = y + MagDir.dy[d];
      if (!map.inside(nx, ny)) continue;
      final n = map.at(nx, ny);
      if (n != MagTerrain.river && n != MagTerrain.lake) shore = true;
    }
    if (shore) color = Color.lerp(color, const Color(0xFFA9DCE6), .35)!;
  }
  final r = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.02, 1.02);
  c.drawRect(r, Paint()..color = color);
  if (t == MagTerrain.grass && h > .82) {
    // A few flowers.
    c.drawCircle(
      Offset(x + h, y + (1 - h)),
      .05,
      Paint()..color = const Color(0xFFF6E9A6),
    );
  }
  if (water && h > .6) {
    c.drawLine(
      Offset(x + .2, y + h * .8),
      Offset(x + .55, y + h * .8),
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..strokeWidth = .05,
    );
  }
}

/// A low mound on a hill cell (drawn in iso space, part of the terrain).
void paintHill(Canvas c, MagMap map, int x, int y) {
  final h = _hash(x, y, map.seed + 5);
  final p = MagIso.project(x + .5, y + .5);
  final w = MagIso.hw * (1.3 + h * .3), hgt = 8 + h * 8;
  final mound = Path()
    ..moveTo(p.dx - w / 2, p.dy + 4)
    ..quadraticBezierTo(p.dx - w * .1, p.dy - hgt * 1.6, p.dx + w / 2, p.dy + 4)
    ..close();
  c.drawPath(
    mound,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(p.dx - w / 2, p.dy - hgt),
        Offset(p.dx + w / 2, p.dy),
        [const Color(0xFFC9C38B), const Color(0xFF8F8C5B)],
      ),
  );
  if (h > .55) {
    MagShapes.box(
      c,
      x: x + .3 + h * .3,
      y: y + .6,
      length: .18,
      width: .14,
      h: 5,
      color: const Color(0xFF9EA1A3),
      outline: false,
    );
  }
}

/// The road on one cell, under the ground transform. Arms go to the
/// neighbours it joins (roads and places).
void paintRoad(Canvas c, MagRoad r, int mask, int x, int y, bool bridge) {
  final w = switch (r) {
    MagRoad.dirt => .42,
    MagRoad.asphalt => .46,
    MagRoad.highway => .56,
    MagRoad.motorway => .66,
    MagRoad.none => 0.0,
  };
  final base = switch (r) {
    MagRoad.dirt => const Color(0xFFC49A62),
    MagRoad.asphalt => const Color(0xFF5E666C),
    MagRoad.highway => const Color(0xFF545B61),
    MagRoad.motorway => const Color(0xFF4A5056),
    MagRoad.none => Colors.transparent,
  };
  final edge = switch (r) {
    MagRoad.dirt => const Color(0xFFA77E4B),
    MagRoad.highway => const Color(0xFFE9C64B),
    _ => const Color(0xFFBFC6C9),
  };
  final cx = x + .5, cy = y + .5, hw = w / 2;
  final rects = <Rect>[
    Rect.fromLTRB(cx - hw, cy - hw, cx + hw, cy + hw),
    for (var d = 0; d < 4; d++)
      if (mask & (1 << d) != 0)
        switch (d) {
          0 => Rect.fromLTRB(cx - hw, y.toDouble(), cx + hw, cy),
          1 => Rect.fromLTRB(cx, cy - hw, x + 1.0, cy + hw),
          2 => Rect.fromLTRB(cx - hw, cy, cx + hw, y + 1.0),
          _ => Rect.fromLTRB(x.toDouble(), cy - hw, cx, cy + hw),
        },
  ];
  if (bridge) {
    for (final rr in rects) {
      c.drawRect(rr.inflate(.07), Paint()..color = const Color(0xFFE6E0D2));
    }
  }
  for (final rr in rects) {
    c.drawRect(rr.inflate(.03), Paint()..color = edge);
  }
  for (final rr in rects) {
    c.drawRect(rr, Paint()..color = base);
  }
  if (r == MagRoad.dirt) return;
  // Centre line dashes along each arm.
  final dash = Paint()
    ..color = r == MagRoad.motorway
        ? const Color(0xFFE9C64B)
        : const Color(0xE6FFFFFF)
    ..strokeWidth = r == MagRoad.motorway ? .06 : .035;
  for (var d = 0; d < 4; d++) {
    if (mask & (1 << d) == 0) continue;
    final ex = cx + MagDir.dx[d] * .5, ey = cy + MagDir.dy[d] * .5;
    c.drawLine(
      Offset(cx + MagDir.dx[d] * .12, cy + MagDir.dy[d] * .12),
      Offset(
        (cx + ex) / 2 + MagDir.dx[d] * .12,
        (cy + ey) / 2 + MagDir.dy[d] * .12,
      ),
      dash,
    );
  }
}

/// Trees of a forest cell (objects: drawn in depth order).
void paintTrees(Canvas c, MagMap map, int x, int y, double zoom) {
  final n = 1 + (_hash(x, y, map.seed + 9) * 2.2).floor();
  for (var i = 0; i < n; i++) {
    final hx = _hash(x * 3 + i, y, map.seed + 11);
    final hy = _hash(x, y * 3 + i, map.seed + 13);
    final px = x + .2 + hx * .6, py = y + .2 + hy * .6;
    final p = MagIso.project(px, py);
    final s = .8 + _hash(x + i, y + i, map.seed) * .5;
    if (zoom < .55) {
      // Far away: one shape per tree is enough.
      c.drawCircle(
        Offset(p.dx, p.dy - 10 * s),
        7 * s,
        Paint()
          ..color = hx > .45
              ? const Color(0xFF357F4C)
              : const Color(0xFF4E9A48),
      );
      continue;
    }
    c.drawOval(
      Rect.fromCenter(
        center: p + const Offset(3, 1),
        width: 16 * s,
        height: 7 * s,
      ),
      Paint()..color = const Color(0x33203024),
    );
    c.drawRect(
      Rect.fromLTWH(p.dx - 1.2, p.dy - 6 * s, 2.4, 6 * s),
      Paint()..color = const Color(0xFF7A5634),
    );
    if (hx > .45) {
      // A fir: stacked triangles.
      for (var k = 0; k < 3; k++) {
        final w = (13 - k * 3) * s, top = p.dy - (8 + k * 6) * s;
        c.drawPath(
          Path()
            ..moveTo(p.dx - w / 2, top + 7 * s)
            ..lineTo(p.dx, top - 4 * s)
            ..lineTo(p.dx + w / 2, top + 7 * s)
            ..close(),
          Paint()
            ..color = Color.lerp(
              const Color(0xFF2F7D4A),
              const Color(0xFF3F9A5A),
              k / 3,
            )!,
        );
      }
    } else {
      final center = Offset(p.dx, p.dy - 12 * s);
      c.drawCircle(center, 7.5 * s, Paint()..color = const Color(0xFF4E9A48));
      if (zoom > .6) {
        c.drawCircle(
          center + Offset(-2.5 * s, -2.5 * s),
          4 * s,
          Paint()..color = const Color(0xFF6DBA5A),
        );
      }
    }
  }
}

/// A truck at (x, y) cells driving in grid direction [dir], with an
/// optional load colour.
void paintTruck(
  Canvas c,
  double x,
  double y,
  int dir,
  MagTruckModel m,
  Color? load, {
  bool selected = false,
}) {
  final ax = MagDir.dx[dir].toDouble(), ay = MagDir.dy[dir].toDouble();
  // Keep to the right-hand lane.
  final px = x - ay * .19, py = y + ax * .19;
  final big = m.capacity / 22;
  final img = MagSprites.current?.truck(m.id, dir);
  if (img != null) {
    final p = MagIso.project(px, py);
    final w = 34.0 * (.8 + big * .25), h = w * img.height / img.width;
    paintImage(
      canvas: c,
      rect: Rect.fromLTWH(p.dx - w / 2, p.dy - h * .8, w, h),
      image: img,
    );
    return;
  }
  if (m.horse) {
    paintCart(c, px, py, ax, ay, m, load, selected: selected);
    return;
  }
  MagShapes.shadow(c, px, py, .33, .26);
  if (selected) {
    c.drawOval(
      Rect.fromCenter(center: MagIso.project(px, py), width: 46, height: 23),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = MagPalette.mint,
    );
  }
  final length = .46 + .12 * big, cab = .22;
  final body = Color(m.color);
  // Cargo box behind, cab in front; draw the one further back first.
  final backX = px - ax * cab / 2, backY = py - ay * cab / 2;
  final cabX = px + ax * length / 2, cabY = py + ay * length / 2;
  void cargo() => MagShapes.box(
    c,
    x: backX,
    y: backY,
    ax: ax,
    ay: ay,
    length: length,
    width: .34,
    z0: 2,
    h: 12 + 4 * big,
    color: load ?? const Color(0xFFE4E7EA),
  );
  void front() {
    MagShapes.box(
      c,
      x: cabX,
      y: cabY,
      ax: ax,
      ay: ay,
      length: cab,
      width: .34,
      z0: 2,
      h: 12,
      color: body,
    );
    // Windscreen.
    final g = MagIso.project(cabX + ax * cab / 2, cabY + ay * cab / 2, 10);
    if (ax + ay > 0) {
      c.drawCircle(g, 2.2, Paint()..color = const Color(0xFFBFE9F2));
    }
  }

  if (ax + ay > 0) {
    cargo();
    front();
  } else {
    front();
    cargo();
  }
}

/// A horse (or a pair) pulling a wooden cart, facing (ax, ay).
void paintCart(
  Canvas c,
  double px,
  double py,
  double ax,
  double ay,
  MagTruckModel m,
  Color? load, {
  bool selected = false,
}) {
  final pair = m.capacity > 8;
  MagShapes.shadow(c, px, py, .36, .24);
  if (selected) {
    c.drawOval(
      Rect.fromCenter(center: MagIso.project(px, py), width: 46, height: 23),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = MagPalette.mint,
    );
  }
  final bx = -ay, by = ax; // across
  // Cart behind, horse(s) in front; draw the farther one first.
  final cartX = px - ax * .14, cartY = py - ay * .14;
  final horseX = px + ax * .2, horseY = py + ay * .2;
  void cart() {
    // Two wheels on the visible side, then the box and its load.
    for (final side in [-1.0, 1.0]) {
      final w = MagIso.project(
        cartX + bx * .15 * side,
        cartY + by * .15 * side,
        3,
      );
      c.drawCircle(w, 3.2, Paint()..color = const Color(0xFF4E3524));
      c.drawCircle(w, 1.4, Paint()..color = const Color(0xFFB08A5A));
    }
    MagShapes.box(
      c,
      x: cartX,
      y: cartY,
      ax: ax,
      ay: ay,
      length: pair ? .34 : .28,
      width: .26,
      z0: 3,
      h: 5,
      color: Color(m.color),
    );
    if (load != null) {
      MagShapes.box(
        c,
        x: cartX,
        y: cartY,
        ax: ax,
        ay: ay,
        length: pair ? .28 : .22,
        width: .2,
        z0: 8,
        h: 3,
        color: load,
        outline: false,
      );
    }
  }

  void horses() {
    for (final side in pair ? [-1.0, 1.0] : [0.0]) {
      final hx = horseX + bx * .07 * side, hy = horseY + by * .07 * side;
      // Legs, body, neck and head.
      for (final k in [-1.0, 1.0]) {
        final leg = MagIso.project(hx + ax * .06 * k, hy + ay * .06 * k);
        c.drawLine(
          leg,
          leg - const Offset(0, 5),
          Paint()
            ..color = const Color(0xFF5A3A26)
            ..strokeWidth = 1.6,
        );
      }
      MagShapes.box(
        c,
        x: hx,
        y: hy,
        ax: ax,
        ay: ay,
        length: .2,
        width: .07,
        z0: 5,
        h: 4,
        color: const Color(0xFF8B5A33),
        outline: false,
      );
      MagShapes.box(
        c,
        x: hx + ax * .12,
        y: hy + ay * .12,
        ax: ax,
        ay: ay,
        length: .07,
        width: .05,
        z0: 7,
        h: 5,
        color: const Color(0xFF7A4E2D),
        outline: false,
      );
    }
  }

  if (ax + ay > 0) {
    cart();
    horses();
  } else {
    horses();
    cart();
  }
}
