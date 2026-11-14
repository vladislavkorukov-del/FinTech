import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_art.dart';
import 'mag_iso.dart';
import 'mag_shapes.dart';

/// The first production chains (master plan stage 3): quarry, windmill,
/// bakery and lumber mill.
void paintChainBuilding(Canvas c, MagIndustryKind kind, double x, double y) {
  switch (kind) {
    case MagIndustryKind.quarry:
      // Grey ground, a stone pile and a wooden crane.
      final pile = MagIso.project(x + 1.2, y + 1.2);
      c.drawPath(
        Path()
          ..moveTo(pile.dx - 20, pile.dy + 6)
          ..lineTo(pile.dx - 4, pile.dy - 14)
          ..lineTo(pile.dx + 18, pile.dy + 6)
          ..close(),
        Paint()..color = const Color(0xFFA7A9AC),
      );
      MagShapes.box(
        c,
        x: x + .5,
        y: y + .5,
        length: .12,
        width: .12,
        h: 26,
        color: const Color(0xFF8B5A33),
      );
      MagShapes.box(
        c,
        x: x + .75,
        y: y + .5,
        length: .6,
        width: .08,
        z0: 24,
        h: 3,
        color: const Color(0xFF8B5A33),
        outline: false,
      );
      for (final (bx, by) in [(.6, 1.6), (1.6, .6)]) {
        MagShapes.box(
          c,
          x: x + bx,
          y: y + by,
          length: .26,
          width: .22,
          h: 6,
          color: const Color(0xFF9EA1A3),
        );
      }
    case MagIndustryKind.mill:
      // A windmill: a tower, a cap and four sails.
      MagShapes.cylinder(
        c,
        x: x + 1,
        y: y + 1,
        r: .32,
        h: 26,
        color: const Color(0xFFF0E6D2),
      );
      MagShapes.roof(
        c,
        x: x + 1,
        y: y + 1,
        length: .5,
        width: .5,
        z0: 26,
        h: 10,
        color: const Color(0xFF8B5A33),
        ridge: .2,
      );
      final hub = MagIso.project(x + 1.25, y + 1.25, 28);
      for (var k = 0; k < 4; k++) {
        final a = k * 1.5708 + .4;
        c.drawLine(
          hub,
          hub + Offset(math.cos(a) * 18, math.sin(a) * 18),
          Paint()
            ..color = const Color(0xFF6F4E37)
            ..strokeWidth = 3,
        );
      }
      c.drawCircle(hub, 2.5, Paint()..color = const Color(0xFF4E3524));
    case MagIndustryKind.bakery:
      MagShapes.box(
        c,
        x: x + 1,
        y: y + .9,
        length: 1.1,
        width: .8,
        h: 12,
        color: const Color(0xFFF3E6CF),
      );
      MagShapes.roof(
        c,
        x: x + 1,
        y: y + .9,
        length: 1.16,
        width: .86,
        z0: 12,
        h: 9,
        color: const Color(0xFFB4533E),
        ridge: .5,
      );
      MagShapes.box(
        c,
        x: x + .55,
        y: y + .6,
        length: .14,
        width: .14,
        z0: 14,
        h: 12,
        color: const Color(0xFF9C6B4E),
      );
      MagShapes.cylinder(
        c,
        x: x + 1.6,
        y: y + 1.6,
        r: .12,
        h: 4,
        color: const Color(0xFFC98A4B),
        dome: true,
      );
    case MagIndustryKind.lumbermill:
      MagShapes.box(
        c,
        x: x + .9,
        y: y + .7,
        length: 1.2,
        width: .7,
        h: 11,
        color: const Color(0xFFB98A5A),
      );
      MagShapes.roof(
        c,
        x: x + .9,
        y: y + .7,
        length: 1.26,
        width: .76,
        z0: 11,
        h: 6,
        color: const Color(0xFF5E6B5C),
        ridge: .8,
      );
      for (var k = 0; k < 3; k++) {
        MagShapes.box(
          c,
          x: x + 1.5,
          y: y + 1.55,
          length: .5,
          width: .3,
          z0: 2.5 * k,
          h: 2.5,
          color: const Color(0xFFD9A867),
          outline: false,
        );
      }
    default:
      break;
  }
}

double _h(int x, int y, int salt) {
  var n = x * 73856093 ^ y * 19349663 ^ salt * 83492791;
  n = (n ^ (n >> 13)) * 1274126177;
  return ((n ^ (n >> 16)) & 0xffff) / 0xffff;
}

/// A settlement drawn cell by cell over its own land: cottages for a
/// hamlet, houses for a village, blocks for a town, towers for a
/// metropolis — each cell different, the centre with a landmark.
void paintTown(Canvas c, MagIndustry i) {
  final t = i.town!;
  final cells = t.cells.toList()
    ..sort((a, b) {
      final s = MagSettlement.keyX(a) + MagSettlement.keyY(a);
      final o = MagSettlement.keyX(b) + MagSettlement.keyY(b);
      return s != o ? s.compareTo(o) : a.compareTo(b);
    });
  // Ground: soft yards, paved as the town grows.
  c.save();
  c.transform(MagIso.ground);
  final yard = t.level >= 5
      ? const Color(0xFFD5D7D0)
      : t.level >= 3
      ? const Color(0xFFC9D59A)
      : const Color(0xFFB7D58A);
  for (final k in cells) {
    final x = MagSettlement.keyX(k).toDouble(),
        y = MagSettlement.keyY(k).toDouble();
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + .04, y + .04, .92, .92),
        const Radius.circular(.12),
      ),
      Paint()..color = yard,
    );
  }
  c.restore();
  for (final k in cells) {
    final x = MagSettlement.keyX(k), y = MagSettlement.keyY(k);
    final h = _h(x, y, i.id);
    final centre = x == i.x && y == i.y;
    final fx = x.toDouble(), fy = y.toDouble();
    if (centre) {
      _landmark(c, fx, fy, t.level);
      continue;
    }
    if (t.level <= 2) {
      // A cottage and a haystack.
      _house(c, fx + .45, fy + .5, .42, .36, 8, h);
      MagShapes.cylinder(
        c,
        x: fx + .8,
        y: fy + .2,
        r: .1,
        h: 5,
        color: const Color(0xFFD9B95A),
      );
    } else if (t.level <= 4) {
      _house(c, fx + .3, fy + .35, .36, .3, 8, h);
      _house(c, fx + .7, fy + .7, .38, .32, 10, 1 - h);
    } else if (t.level <= 7) {
      final floors = 2 + (h * (t.level - 3)).floor();
      MagShapes.box(
        c,
        x: fx + .5,
        y: fy + .5,
        length: .62,
        width: .6,
        h: 7.0 * floors,
        color: [
          const Color(0xFFE8DCC8),
          const Color(0xFFCFD8DC),
          const Color(0xFFF1E3C8),
        ][(h * 3).floor() % 3],
      );
    } else {
      final tall = 40 + h * 14 * (t.level - 6);
      MagShapes.box(
        c,
        x: fx + .5,
        y: fy + .5,
        length: .58,
        width: .58,
        h: tall,
        color: [
          const Color(0xFF8FB8C9),
          const Color(0xFFB9C7D6),
          const Color(0xFF9FD3C7),
        ][(h * 3).floor() % 3],
      );
      MagShapes.box(
        c,
        x: fx + .5,
        y: fy + .5,
        length: .6,
        width: .6,
        z0: tall,
        h: 2,
        color: MagPalette.mint,
        outline: false,
      );
    }
  }
}

void _house(
  Canvas c,
  double x,
  double y,
  double l,
  double w,
  double h,
  double tone,
) {
  MagShapes.box(
    c,
    x: x,
    y: y,
    length: l,
    width: w,
    h: h,
    color: Color.lerp(const Color(0xFFF3E6CF), const Color(0xFFE2CDB0), tone)!,
  );
  MagShapes.roof(
    c,
    x: x,
    y: y,
    length: l + .06,
    width: w + .06,
    z0: h,
    h: 7,
    color: Color.lerp(const Color(0xFFB4533E), const Color(0xFF7E5A44), tone)!,
    ridge: .3,
  );
}

/// The settlement's centre: a well, a chapel, a town hall, a tower.
void _landmark(Canvas c, double x, double y, int level) {
  if (level <= 1) {
    _house(c, x + .5, y + .5, .5, .42, 9, .2);
    MagShapes.cylinder(
      c,
      x: x + .15,
      y: y + .85,
      r: .08,
      h: 4,
      color: const Color(0xFF9EA1A3),
    );
  } else if (level <= 4) {
    MagShapes.box(
      c,
      x: x + .5,
      y: y + .5,
      length: .5,
      width: .4,
      h: 12,
      color: const Color(0xFFF6EEDD),
    );
    MagShapes.roof(
      c,
      x: x + .5,
      y: y + .5,
      length: .56,
      width: .46,
      z0: 12,
      h: 8,
      color: const Color(0xFF5E8C7A),
      ridge: .3,
    );
    MagShapes.box(
      c,
      x: x + .25,
      y: y + .5,
      length: .14,
      width: .14,
      h: 24,
      color: const Color(0xFFF6EEDD),
    );
  } else if (level <= 7) {
    MagShapes.box(
      c,
      x: x + .5,
      y: y + .5,
      length: .7,
      width: .6,
      h: 18,
      color: const Color(0xFFEDE3D2),
    );
    MagShapes.box(
      c,
      x: x + .5,
      y: y + .5,
      length: .2,
      width: .2,
      z0: 18,
      h: 16,
      color: const Color(0xFFEDE3D2),
    );
    MagShapes.roof(
      c,
      x: x + .5,
      y: y + .5,
      length: .24,
      width: .24,
      z0: 34,
      h: 8,
      color: MagPalette.teal,
      ridge: .1,
    );
  } else {
    MagShapes.box(
      c,
      x: x + .5,
      y: y + .5,
      length: .62,
      width: .62,
      h: 90 + 6.0 * level,
      color: const Color(0xFF7FB3C8),
    );
    MagShapes.box(
      c,
      x: x + .5,
      y: y + .5,
      length: .2,
      width: .2,
      z0: 90 + 6.0 * level,
      h: 18,
      color: MagPalette.mint,
    );
  }
}

/// A small mint flag over a business the company owns.
void paintOwnerFlag(Canvas c, MagIndustry i) {
  final base = MagIso.project(i.x + .25, i.y + .25);
  final top = base - const Offset(0, 30);
  c.drawLine(
    base,
    top,
    Paint()
      ..color = const Color(0xFF4E5B60)
      ..strokeWidth = 1.6,
  );
  c.drawPath(
    Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(top.dx + 12, top.dy + 4)
      ..lineTo(top.dx, top.dy + 8)
      ..close(),
    Paint()..color = MagPalette.mint,
  );
}
