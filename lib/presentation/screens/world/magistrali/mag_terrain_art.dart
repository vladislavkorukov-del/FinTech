import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_iso.dart';

/// The land drawn as one smooth surface instead of squares: every corner of
/// the grid gets a colour blended from the four cells around it, so grass
/// fades into forest floor, hills into rock and land into sandy shores; the
/// GPU blends the colours across each cell (stage S10 visuals).

double _hash(int x, int y, int seed) {
  var n = x * 73856093 ^ y * 19349663 ^ seed * 83492791;
  n = (n ^ (n >> 13)) * 1274126177;
  return ((n ^ (n >> 16)) & 0xffff) / 0xffff;
}

bool _wet(MagTerrain t) => t == MagTerrain.river || t == MagTerrain.lake;

/// Colour of one cell's ground (with a gentle variation).
Color _cellColor(MagMap map, int x, int y) {
  final cx = x.clamp(0, map.size - 1), cy = y.clamp(0, map.size - 1);
  final t = map.at(cx, cy);
  final h =
      _hash(cx ~/ 2, cy ~/ 2, map.seed) * .6 + _hash(cx, cy, map.seed) * .4;
  return switch (t) {
    MagTerrain.grass => Color.lerp(
      const Color(0xFF9CCB6C),
      const Color(0xFF86BD5E),
      h,
    )!,
    MagTerrain.forest => Color.lerp(
      const Color(0xFF6FA650),
      const Color(0xFF5E9744),
      h,
    )!,
    MagTerrain.hill => Color.lerp(
      const Color(0xFFB4AE86),
      const Color(0xFF9E9A7A),
      h,
    )!,
    MagTerrain.river => const Color(0xFF5DB2D6),
    MagTerrain.lake => const Color(0xFF4A9FCC),
  };
}

/// A grid corner's colour: the average of the four cells around it, water
/// counted as sand, so land turns sandy towards a shore (the water itself
/// is drawn over it with crisp edges).
Color _cornerColor(MagMap map, int x, int y) {
  var r = 0.0, g = 0.0, b = 0.0;
  for (final (dx, dy) in const [(-1, -1), (0, -1), (-1, 0), (0, 0)]) {
    final cx = (x + dx).clamp(0, map.size - 1);
    final cy = (y + dy).clamp(0, map.size - 1);
    final c = _wet(map.at(cx, cy))
        ? const Color(0xFFE0D29C)
        : _cellColor(map, cx, cy);
    r += c.r;
    g += c.g;
    b += c.b;
  }
  return Color.from(alpha: 1, red: r / 4, green: g / 4, blue: b / 4);
}

/// Water over the land: each water cell a rounded pool joined to its water
/// neighbours (diagonals too — rivers wind), with a pale shallow rim.
void _paintWater(Canvas c, MagMap map, int x0, int y0, int x1, int y1) {
  for (final (grow, deep) in [(.16, false), (0.0, true)]) {
    for (var y = y0 - 1; y <= y1; y++) {
      for (var x = x0 - 1; x <= x1; x++) {
        if (!map.inside(x, y) || !_wet(map.at(x, y))) continue;
        final lake = map.at(x, y) == MagTerrain.lake;
        final paint = Paint()
          ..color = deep
              ? (lake ? const Color(0xFF4A9FCC) : const Color(0xFF5BB0D6))
              : const Color(0xFF9FD8E6)
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.fill;
        final ctr = Offset(x + .5, y + .5);
        c.drawCircle(ctr, .58 + grow, paint);
        for (final (dx, dy) in const [(1, 0), (0, 1), (1, 1), (1, -1)]) {
          final nx = x + dx, ny = y + dy;
          if (!map.inside(nx, ny) || !_wet(map.at(nx, ny))) continue;
          c.drawLine(
            ctr,
            Offset(nx + .5, ny + .5),
            Paint()
              ..color = paint.color
              ..strokeWidth = (dx != 0 && dy != 0 ? .9 : 1.1) + grow * 2
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }
  }
}

/// The ground of cells [x0, x1) × [y0, y1) as one picture of blended
/// triangles (under the ground transform: a cell is 1×1), with ripples on
/// water and a few flowers on grass.
void paintTerrain(Canvas c, MagMap map, int x0, int y0, int x1, int y1) {
  final w = x1 - x0, h = y1 - y0;
  final corners = <Color>[
    for (var y = y0; y <= y1; y++)
      for (var x = x0; x <= x1; x++) _cornerColor(map, x, y),
  ];
  Color at(int x, int y) => corners[(y - y0) * (w + 1) + (x - x0)];
  final pos = Float32List(w * h * 12);
  final col = Int32List(w * h * 6);
  var p = 0, q = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final a = at(x, y), b = at(x + 1, y);
      final d = at(x, y + 1), e = at(x + 1, y + 1);
      for (final (vx, vy, vc) in [
        (x, y, a),
        (x + 1, y, b),
        (x + 1, y + 1, e),
        (x, y, a),
        (x + 1, y + 1, e),
        (x, y + 1, d),
      ]) {
        pos[p++] = vx.toDouble();
        pos[p++] = vy.toDouble();
        col[q++] = vc.toARGB32();
      }
    }
  }
  c.drawVertices(
    ui.Vertices.raw(VertexMode.triangles, pos, colors: col),
    BlendMode.dst,
    Paint(),
  );
  // Water, clipped to this piece so neighbouring pieces join cleanly.
  c.save();
  c.clipRect(
    Rect.fromLTRB(x0.toDouble(), y0.toDouble(), x1.toDouble(), y1.toDouble()),
  );
  _paintWater(c, map, x0, y0, x1, y1);
  c.restore();
  final ripple = Paint()
    ..color = const Color(0x40FFFFFF)
    ..strokeWidth = .04
    ..strokeCap = StrokeCap.round;
  final flower = Paint()..color = const Color(0xFFF6E9A6);
  final flower2 = Paint()..color = const Color(0xFFF2B6C6);
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final t = map.at(x, y);
      final hh = _hash(x, y, map.seed + 3);
      if (_wet(t) && hh > .55) {
        c.drawLine(
          Offset(x + .2, y + hh * .8),
          Offset(x + .5, y + hh * .8),
          ripple,
        );
      } else if (t == MagTerrain.grass && hh > .86) {
        c.drawCircle(
          Offset(x + hh, y + 1 - hh),
          .045,
          hh > .93 ? flower2 : flower,
        );
      }
    }
  }
}

/// Rocks on a hill cell (drawn in iso space, sorted with the objects):
/// pointed peaks (snow on the tallest), rounded boulders and ridges, lit
/// from the upper left. Deep inside a range they grow into cliffs; next to
/// water they stay small and keep to the middle of their cell, so they
/// never stand in a river or a lake.
void paintRocks(Canvas c, MagMap map, int x, int y) {
  var inner = 0;
  var wet = false;
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      final nx = x + dx, ny = y + dy;
      if (!map.inside(nx, ny) || (dx == 0 && dy == 0)) continue;
      final t = map.at(nx, ny);
      if (_wet(t)) wet = true;
      if (t == MagTerrain.hill && (dx == 0 || dy == 0)) inner++;
    }
  }
  final n = 1 + (_hash(x, y, map.seed + 21) * 2.4).floor();
  for (var k = 0; k < n; k++) {
    final hx = _hash(x * 5 + k, y, map.seed + 23);
    final hy = _hash(x, y * 5 + k, map.seed + 29);
    final kind = _hash(x + 3 * k, y - k, map.seed + 37);
    final spread = wet ? .16 : .5;
    final big = wet ? .55 : (k == 0 ? 1 + inner * .3 : .65);
    final px = x + .5 + (hx - .5) * spread, py = y + .5 + (hy - .5) * spread;
    final r = (.2 + hx * .1) * big, h = (9 + hy * 12) * big;
    final seed = _hash(x + k, y - k, map.seed + 31);
    if (kind < .14) {
      _boulder(c, px, py, r * .6, h * .5);
    } else if (kind < .36 && !wet) {
      _crag(c, px - .14, py + .08, r * .75, h * .8, seed);
      _crag(c, px + .12, py - .06, r * .8, h * .95, 1 - seed);
    } else {
      _crag(c, px, py, r, h, seed);
    }
  }
}

/// A rounded boulder: a low dome of grey shades.
void _boulder(Canvas c, double x, double y, double r, double h) {
  final base = MagIso.project(x, y);
  final hw = r * MagIso.hw * 1.6, hh = r * MagIso.hh * 1.6;
  c.drawOval(
    Rect.fromCenter(
      center: base + Offset(hw * .3, hh * .35),
      width: hw * 2.3,
      height: hh * 2,
    ),
    Paint()..color = const Color(0x2A1F2A1C),
  );
  final body = Rect.fromCenter(
    center: base - Offset(0, h * .45),
    width: hw * 2,
    height: hh * 1.6 + h,
  );
  c.drawOval(body, Paint()..color = const Color(0xFF8A8881));
  c.drawOval(
    Rect.fromLTWH(body.left + 1, body.top, body.width * .8, body.height * .7),
    Paint()..color = const Color(0xFFA9A79F),
  );
  c.drawOval(
    Rect.fromLTWH(
      body.left + body.width * .2,
      body.top + body.height * .12,
      body.width * .35,
      body.height * .25,
    ),
    Paint()..color = const Color(0x55FFFFFF),
  );
}

void _crag(Canvas c, double x, double y, double r, double h, double seed) {
  final base = MagIso.project(x, y);
  final hw = r * MagIso.hw * 1.6, hh = r * MagIso.hh * 1.6;
  final tilt = (seed - .5) * hw * .5;
  final top = base + Offset(tilt, -h);
  // Shadow.
  c.drawOval(
    Rect.fromCenter(
      center: base + Offset(hw * .25, hh * .3),
      width: hw * 2.4,
      height: hh * 2.2,
    ),
    Paint()..color = const Color(0x2A1F2A1C),
  );
  final left = base + Offset(-hw, 0);
  final right = base + Offset(hw, 0);
  final front = base + Offset(0, hh);
  final back = base + Offset(hw * .1, -hh * .8);
  final shoulderL = Offset.lerp(left, top, .55)! + Offset(-hw * .1, 0);
  final shoulderR = Offset.lerp(right, top, .6)! + Offset(hw * .08, 0);
  void face(List<Offset> pts, Color color) {
    final path = Path()..addPolygon(pts, true);
    c.drawPath(path, Paint()..color = color);
  }

  face([left, shoulderL, top, back], const Color(0xFFB5B3AC));
  face([left, front, shoulderL], const Color(0xFF8F8D86));
  face([shoulderL, front, top], const Color(0xFFA19F98));
  face([front, right, shoulderR, top], const Color(0xFF74726C));
  face([back, top, shoulderR, right], const Color(0xFF85837C));
  // Snow on the tallest peaks.
  if (h > 20) {
    final snowL = Offset.lerp(top, shoulderL, .38)!;
    final snowR = Offset.lerp(top, shoulderR, .34)!;
    final snowF = Offset.lerp(top, front, .3)!;
    c.drawPath(
      Path()..addPolygon([snowL, top, snowR, snowF], true),
      Paint()..color = const Color(0xFFF4F6F7),
    );
  }
  // A lit edge and a tuft of grass at the foot.
  c.drawLine(
    shoulderL,
    top,
    Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1,
  );
  c.drawCircle(
    front + Offset(-hw * .3, -1),
    math.max(1.5, hw * .12),
    Paint()..color = const Color(0xFF7DA857),
  );
}

/// Trees on a forest cell with volume: firs of shaded tiers, broadleaves of
/// overlapping crowns lit from the upper left, each with a soft shadow.
void paintForest(Canvas c, MagMap map, int x, int y, double zoom) {
  final n = 2 + (_hash(x, y, map.seed + 9) * 2.2).floor();
  final trees = <(double, double, double, bool)>[
    for (var i = 0; i < n; i++)
      (
        x + .18 + _hash(x * 3 + i, y, map.seed + 11) * .64,
        y + .18 + _hash(x, y * 3 + i, map.seed + 13) * .64,
        .75 + _hash(x + i, y + i, map.seed) * .55,
        _hash(x - i, y + 2 * i, map.seed + 17) > .45,
      ),
  ]..sort((a, b) => (a.$1 + a.$2).compareTo(b.$1 + b.$2));
  for (final (px, py, s, fir) in trees) {
    final p = MagIso.project(px, py);
    if (zoom < .55) {
      c.drawCircle(
        Offset(p.dx, p.dy - 10 * s),
        7 * s,
        Paint()
          ..color = fir ? const Color(0xFF2F7546) : const Color(0xFF4C9444),
      );
      continue;
    }
    c.drawOval(
      Rect.fromCenter(
        center: p + Offset(5 * s, 1.5),
        width: 18 * s,
        height: 7 * s,
      ),
      Paint()..color = const Color(0x33182418),
    );
    c.drawRect(
      Rect.fromLTWH(p.dx - 1.3, p.dy - 7 * s, 2.6, 7 * s),
      Paint()..color = const Color(0xFF6E4C2E),
    );
    if (fir) {
      for (var k = 0; k < 3; k++) {
        final wd = (15 - k * 3.6) * s, base = p.dy - (6 + k * 6.5) * s;
        final tip = Offset(p.dx, base - 10 * s);
        final l = Offset(p.dx - wd / 2, base), r = Offset(p.dx + wd / 2, base);
        final m = Offset(p.dx + wd * .05, base + 1.5 * s);
        c.drawPath(
          Path()..addPolygon([l, tip, m], true),
          Paint()
            ..color = Color.lerp(
              const Color(0xFF3B8F55),
              const Color(0xFF4FA866),
              k / 3,
            )!,
        );
        c.drawPath(
          Path()..addPolygon([m, tip, r], true),
          Paint()
            ..color = Color.lerp(
              const Color(0xFF256B3D),
              const Color(0xFF2F7D4A),
              k / 3,
            )!,
        );
      }
    } else {
      final ctr = Offset(p.dx, p.dy - 13 * s);
      for (final (o, rr, col) in [
        (Offset(3 * s, 2 * s), 6.5, const Color(0xFF3E8240)),
        (Offset(-3.5 * s, 1.5 * s), 6.0, const Color(0xFF468C45)),
        (Offset(0, -2.5 * s), 7.0, const Color(0xFF54A04D)),
        (Offset(-2 * s, -4.5 * s), 3.8, const Color(0xFF76BE62)),
      ]) {
        c.drawCircle(ctr + o, rr * s, Paint()..color = col);
      }
    }
  }
}
