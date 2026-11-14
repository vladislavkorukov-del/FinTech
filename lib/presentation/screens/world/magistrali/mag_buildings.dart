import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_art.dart';
import 'mag_iso.dart';
import 'mag_shapes.dart';
import 'mag_sprites.dart';
import 'mag_town_art.dart';

/// A place: ground pad and buildings, as a picture recorded once.
ui.Picture recordIndustry(MagIndustry i) {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final s = i.size.toDouble();
  if (i.town != null) {
    paintTown(c, i);
    return rec.endRecording();
  }
  final img = MagSprites.current?.industry(i.kind);
  if (img != null) {
    // A painted sprite: its bottom centre on the footprint's front corner.
    final front = MagIso.project(i.x + s, i.y + s);
    final w = s * MagIso.hw * 2, h = w * img.height / img.width;
    paintImage(
      canvas: c,
      rect: Rect.fromLTWH(front.dx - w / 2, front.dy - h, w, h),
      image: img,
      filterQuality: FilterQuality.medium,
    );
    return rec.endRecording();
  }
  // Ground pad.
  c.save();
  c.transform(MagIso.ground);
  final pad = switch (i.kind) {
    MagIndustryKind.farm => const Color(0xFFD9C27A),
    MagIndustryKind.city => const Color(0xFFD7D9D3),
    MagIndustryKind.village => const Color(0xFFB9D58E),
    MagIndustryKind.mine => const Color(0xFFA59C90),
    _ => const Color(0xFFCFCBBF),
  };
  c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(i.x + .06, i.y + .06, s - .12, s - .12),
      const Radius.circular(.15),
    ),
    Paint()..color = pad,
  );
  if (i.kind == MagIndustryKind.farm) {
    for (var k = 0; k < 7; k++) {
      c.drawRect(
        Rect.fromLTWH(i.x + .12 + k * .26, i.y + .12, .12, s - .24),
        Paint()..color = const Color(0xFFC7A955),
      );
    }
  }
  c.restore();
  final x = i.x.toDouble(), y = i.y.toDouble();
  switch (i.kind) {
    case MagIndustryKind.farm:
      MagShapes.box(
        c,
        x: x + 1.45,
        y: y + .55,
        length: .8,
        width: .6,
        h: 13,
        color: const Color(0xFFC0473F),
      );
      MagShapes.roof(
        c,
        x: x + 1.45,
        y: y + .55,
        length: .86,
        width: .66,
        z0: 13,
        h: 9,
        color: const Color(0xFF6E4B3A),
      );
      MagShapes.cylinder(
        c,
        x: x + .55,
        y: y + .5,
        r: .2,
        h: 28,
        color: const Color(0xFFDADDE0),
        dome: true,
      );
    case MagIndustryKind.sawmill:
      MagShapes.box(
        c,
        x: x + 1.1,
        y: y + .7,
        length: 1.3,
        width: .8,
        h: 12,
        color: const Color(0xFFA9774A),
      );
      MagShapes.roof(
        c,
        x: x + 1.1,
        y: y + .7,
        length: 1.36,
        width: .86,
        z0: 12,
        h: 7,
        color: const Color(0xFF5E6B5C),
        ridge: .8,
      );
      for (var k = 0; k < 3; k++) {
        MagShapes.box(
          c,
          x: x + .45 + k * .15,
          y: y + 1.55,
          length: .7,
          width: .12,
          ax: 0,
          ay: 1,
          h: 4 + k * 0.0,
          z0: 0,
          color: const Color(0xFF8B5A33),
          outline: false,
        );
      }
    case MagIndustryKind.mine:
      MagShapes.box(
        c,
        x: x + .7,
        y: y + 1.2,
        length: .9,
        width: .7,
        h: 10,
        color: const Color(0xFF7D7F86),
      );
      MagShapes.box(
        c,
        x: x + 1.35,
        y: y + .55,
        length: .14,
        width: .14,
        h: 34,
        color: const Color(0xFF5D6066),
      );
      MagShapes.box(
        c,
        x: x + 1.35,
        y: y + .55,
        length: .5,
        width: .14,
        z0: 30,
        h: 4,
        color: const Color(0xFFD65C4E),
      );
      final pile = MagIso.project(x + 1.45, y + 1.5);
      c.drawPath(
        Path()
          ..moveTo(pile.dx - 16, pile.dy + 4)
          ..lineTo(pile.dx, pile.dy - 12)
          ..lineTo(pile.dx + 16, pile.dy + 4)
          ..close(),
        Paint()..color = const Color(0xFF6F7884),
      );
    case MagIndustryKind.foodPlant:
      MagShapes.box(
        c,
        x: x + 1,
        y: y + 1,
        length: 1.4,
        width: 1.2,
        h: 18,
        color: const Color(0xFFF2F1EC),
      );
      MagShapes.box(
        c,
        x: x + 1,
        y: y + 1,
        length: 1.42,
        width: 1.22,
        z0: 12,
        h: 3,
        color: MagPalette.mint,
        outline: false,
      );
      MagShapes.cylinder(
        c,
        x: x + .45,
        y: y + .45,
        r: .12,
        z0: 0,
        h: 34,
        color: const Color(0xFFC9CDD0),
      );
    case MagIndustryKind.factory:
      MagShapes.box(
        c,
        x: x + 1.5,
        y: y + 1.6,
        length: 2.3,
        width: 1.6,
        h: 22,
        color: const Color(0xFF9AA1A8),
      );
      for (var k = 0; k < 3; k++) {
        MagShapes.roof(
          c,
          x: x + .85 + k * .65,
          y: y + 1.6,
          ax: 0,
          ay: 1,
          length: 1.6,
          width: .6,
          z0: 22,
          h: 8,
          color: const Color(0xFF6B737B),
          ridge: 1,
        );
      }
      MagShapes.cylinder(
        c,
        x: x + .5,
        y: y + .5,
        r: .16,
        h: 46,
        color: const Color(0xFFB45A4A),
      );
      MagShapes.cylinder(
        c,
        x: x + 1.1,
        y: y + .4,
        r: .14,
        h: 38,
        color: const Color(0xFFB45A4A),
      );
    case MagIndustryKind.city:
      final rnd = math.Random(i.id * 31);
      for (final (bx, by) in [
        (.6, .6),
        (1.6, .6),
        (2.4, .7),
        (.7, 1.6),
        (1.6, 1.5),
        (2.4, 1.7),
        (.8, 2.4),
        (1.7, 2.4),
        (2.4, 2.5),
      ]) {
        final tall = 18 + rnd.nextDouble() * 44;
        final col = [
          const Color(0xFF8FB8C9),
          const Color(0xFFE3DED3),
          const Color(0xFFB9C7D6),
          const Color(0xFFF1E3C8),
        ][rnd.nextInt(4)];
        MagShapes.box(
          c,
          x: x + bx,
          y: y + by,
          length: .62,
          width: .62,
          h: tall,
          color: col,
        );
      }
    case MagIndustryKind.quarry:
    case MagIndustryKind.mill:
    case MagIndustryKind.bakery:
    case MagIndustryKind.lumbermill:
      paintChainBuilding(c, i.kind, x, y);
    case MagIndustryKind.warehouse:
      // A hangar with a mint band, gable roof and crates at the gate.
      MagShapes.box(
        c,
        x: x + 1,
        y: y + .9,
        length: 1.6,
        width: 1.1,
        h: 15,
        color: const Color(0xFFE4E8EA),
      );
      MagShapes.box(
        c,
        x: x + 1,
        y: y + .9,
        length: 1.62,
        width: 1.12,
        z0: 9,
        h: 3,
        color: MagPalette.mint,
        outline: false,
      );
      MagShapes.roof(
        c,
        x: x + 1,
        y: y + .9,
        length: 1.66,
        width: 1.16,
        z0: 15,
        h: 9,
        color: const Color(0xFF51707A),
        ridge: 1,
      );
      for (final (bx, by, h) in [
        (.35, 1.75, 5.0),
        (.6, 1.75, 8.0),
        (1.55, 1.7, 5.0),
      ]) {
        MagShapes.box(
          c,
          x: x + bx,
          y: y + by,
          length: .2,
          width: .2,
          h: h,
          color: const Color(0xFFC08A4E),
        );
      }
    case MagIndustryKind.village:
      for (final (hx, hy, col) in [
        (.55, .6, const Color(0xFFF3E6CF)),
        (1.45, .7, const Color(0xFFEAD7BC)),
        (.9, 1.5, const Color(0xFFF6EEDD)),
      ]) {
        MagShapes.box(
          c,
          x: x + hx,
          y: y + hy,
          length: .52,
          width: .46,
          h: 9,
          color: col,
        );
        MagShapes.roof(
          c,
          x: x + hx,
          y: y + hy,
          length: .6,
          width: .54,
          z0: 9,
          h: 8,
          color: const Color(0xFFB4533E),
          ridge: .3,
        );
      }
  }
  return rec.endRecording();
}

/// Smoke from chimneys of working plants (drawn each frame).
void paintSmoke(Canvas c, MagIndustry i, double t) {
  final stacks = switch (i.kind) {
    MagIndustryKind.foodPlant => [(i.x + .45, i.y + .45, 34.0)],
    MagIndustryKind.factory => [
      (i.x + .5, i.y + .5, 46.0),
      (i.x + 1.1, i.y + .4, 38.0),
    ],
    _ => const <(double, double, double)>[],
  };
  for (final (x, y, h) in stacks) {
    for (var k = 0; k < 3; k++) {
      final f = (t * .35 + k / 3) % 1;
      final p = MagIso.project(x, y, h + f * 26) + Offset(f * 10, 0);
      c.drawCircle(
        p,
        3 + f * 6,
        Paint()..color = Colors.white.withValues(alpha: .55 * (1 - f)),
      );
    }
  }
}
