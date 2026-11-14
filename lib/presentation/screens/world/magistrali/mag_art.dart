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
    MagCargo.stone => const Color(0xFFA7A9AC),
    MagCargo.planks => const Color(0xFFD9A867),
    MagCargo.flour => const Color(0xFFF2EEE3),
    MagCargo.bread => const Color(0xFFC98A4B),
    MagCargo.coal => const Color(0xFF3B3F44),
    MagCargo.clay => const Color(0xFFB8774A),
    MagCargo.bricks => const Color(0xFFC8664E),
    MagCargo.steel => const Color(0xFF8A96A3),
    MagCargo.parts => const Color(0xFFE8B23E),
    MagCargo.passengers => const Color(0xFF8E7CC3),
  };
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
