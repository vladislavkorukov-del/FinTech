import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../domain/finorio/finorio.dart';

/// Finorio's look: soft 3D shapes drawn in code for now. Drawing is kept
/// apart from the simulation: to switch to painted PNGs later, list them
/// in [FinSprites.assets] — a building with a sprite is drawn from it,
/// the rest keep their procedural shape. No text is ever drawn here.
abstract final class FinPalette {
  static const teal = Color(0xFF3FD6C2);
  static const lavender = Color(0xFFB79CF2);
  static const plum = Color(0xFF4B2346);
  static const shell = Color(0xFFF6F2FA);
  static const shellDark = Color(0xFFD9D0E6);
  static const belt = Color(0xFF5E5872);
  static const beltLight = Color(0xFF8D86A6);

  static Color terrain(FinTerrain t) => switch (t) {
    FinTerrain.ground => const Color(0xFFE6E9E4),
    FinTerrain.iron => const Color(0xFFB9C3CF),
    FinTerrain.copper => const Color(0xFFE8B79A),
    FinTerrain.crystal => const Color(0xFFCDE4F7),
    FinTerrain.biomass => const Color(0xFFBFE0B5),
    FinTerrain.rock => const Color(0xFF8A8494),
  };

  static Color item(FinItem i) => switch (i) {
    FinItem.ironOre => const Color(0xFF7D8A9C),
    FinItem.copperOre => const Color(0xFFC97A4E),
    FinItem.crystal => const Color(0xFF63B8F0),
    FinItem.biomass => const Color(0xFF5DB36A),
    FinItem.ironPlate => const Color(0xFFD7DEE8),
    FinItem.copperPlate => const Color(0xFFF0A774),
    FinItem.gear => const Color(0xFFB8BFCC),
    FinItem.circuit => const Color(0xFF3FD6A6),
  };

  static Color accent(FinBuilding b) => switch (b) {
    FinBuilding.drill => teal,
    FinBuilding.furnace => const Color(0xFFFFA45C),
    FinBuilding.assembler => lavender,
    FinBuilding.generator => const Color(0xFF52E0B0),
    FinBuilding.storage => const Color(0xFFC9B48A),
    FinBuilding.lab => const Color(0xFF8FA8FF),
    FinBuilding.belt => beltLight,
    FinBuilding.fastBelt => teal,
  };
}

/// Optional painted sprites (none yet): building → asset path.
abstract final class FinSprites {
  static const assets = <FinBuilding, String>{};
}

/// Draws one cell's ground (deposits get soft pebbles).
void paintTerrain(Canvas c, FinTerrain t, int x, int y, int seed) {
  final r = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
  c.drawRect(r, Paint()..color = FinPalette.terrain(t));
  if (t == FinTerrain.ground) return;
  final rnd = math.Random(x * 7919 + y * 104729 + seed);
  if (t == FinTerrain.rock) {
    c.drawRRect(
      RRect.fromRectAndRadius(r.deflate(.08), const Radius.circular(.22)),
      Paint()..color = const Color(0xFF77708A),
    );
    c.drawCircle(
      r.center.translate(-.12, -.14),
      .16,
      Paint()..color = Colors.white.withValues(alpha: .12),
    );
    return;
  }
  final dot = Color.lerp(FinPalette.terrain(t), Colors.black, .22)!;
  for (var i = 0; i < 4; i++) {
    final p = Offset(
      x + .18 + rnd.nextDouble() * .64,
      y + .18 + rnd.nextDouble() * .64,
    );
    final s = .07 + rnd.nextDouble() * .08;
    if (t == FinTerrain.crystal) {
      final path = Path()
        ..moveTo(p.dx, p.dy - s * 1.6)
        ..lineTo(p.dx + s, p.dy)
        ..lineTo(p.dx, p.dy + s * 1.2)
        ..lineTo(p.dx - s, p.dy)
        ..close();
      c.drawPath(path, Paint()..color = const Color(0xFF7CC4F2));
    } else {
      c.drawCircle(p, s, Paint()..color = dot);
      c.drawCircle(
        p.translate(-s * .3, -s * .3),
        s * .4,
        Paint()..color = Colors.white.withValues(alpha: .35),
      );
    }
  }
}

/// One item: a small glossy gem in the item's colour.
void paintItem(Canvas c, Offset at, FinItem item, double size) {
  final color = FinPalette.item(item);
  c.drawCircle(
    at.translate(0, size * .18),
    size * .5,
    Paint()..color = Colors.black.withValues(alpha: .18),
  );
  final rect = Rect.fromCenter(center: at, width: size, height: size);
  final shape = item == FinItem.ironPlate || item == FinItem.copperPlate
      ? RRect.fromRectAndRadius(rect, Radius.circular(size * .18))
      : RRect.fromRectAndRadius(rect, Radius.circular(size * .5));
  c.drawRRect(
    shape,
    Paint()
      ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
        Color.lerp(color, Colors.white, .45)!,
        color,
      ]),
  );
  if (item == FinItem.gear) {
    c.drawCircle(at, size * .18, Paint()..color = const Color(0xFF7E8596));
  } else if (item == FinItem.circuit) {
    c.drawRect(
      Rect.fromCenter(center: at, width: size * .4, height: size * .4),
      Paint()..color = const Color(0xFF1E8C6A),
    );
  }
}

/// A building on its cell (unit square at [x],[y]); [t] is seconds of
/// simulated time for gentle motion, [active] whether it is working.
void paintBuilding(Canvas c, FinMachine m, double t, {required bool active}) {
  final cell = Rect.fromLTWH(m.x.toDouble(), m.y.toDouble(), 1, 1);
  final body = RRect.fromRectAndRadius(
    cell.deflate(.07),
    const Radius.circular(.2),
  );
  final accent = FinPalette.accent(m.kind);
  // Soft shadow, shell with a glossy top.
  c.drawRRect(
    body.shift(const Offset(0, .06)),
    Paint()..color = Colors.black.withValues(alpha: .16),
  );
  c.drawRRect(
    body,
    Paint()
      ..shader = ui.Gradient.linear(
        body.outerRect.topCenter,
        body.outerRect.bottomCenter,
        [FinPalette.shell, FinPalette.shellDark],
      ),
  );
  c.drawRRect(
    body.deflate(.02),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .025
      ..color = Colors.white.withValues(alpha: .9),
  );
  final center = cell.center;
  final glow = active ? .55 + .25 * math.sin(t * 4) : .18;
  switch (m.kind) {
    case FinBuilding.drill:
      c.save();
      c.translate(center.dx, center.dy);
      if (active) c.rotate(t * 5);
      final bit = Path();
      for (var i = 0; i < 3; i++) {
        final a = i * math.pi * 2 / 3;
        bit
          ..moveTo(0, 0)
          ..lineTo(math.cos(a) * .26, math.sin(a) * .26)
          ..lineTo(math.cos(a + .6) * .2, math.sin(a + .6) * .2)
          ..close();
      }
      c.drawPath(bit, Paint()..color = accent);
      c.restore();
      c.drawCircle(center, .07, Paint()..color = FinPalette.plum);
    case FinBuilding.furnace:
      final window = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center.translate(0, .06),
          width: .46,
          height: .3,
        ),
        const Radius.circular(.08),
      );
      c.drawRRect(window, Paint()..color = const Color(0xFF5A3A4E));
      c.drawRRect(
        window.deflate(.04),
        Paint()..color = accent.withValues(alpha: glow),
      );
    case FinBuilding.assembler:
      c.save();
      c.translate(center.dx, center.dy);
      if (active) c.rotate(t * 2);
      final teeth = Paint()..color = accent;
      for (var i = 0; i < 8; i++) {
        c.save();
        c.rotate(i * math.pi / 4);
        c.drawRect(const Rect.fromLTWH(-.04, -.27, .08, .1), teeth);
        c.restore();
      }
      c.drawCircle(Offset.zero, .19, teeth);
      c.drawCircle(Offset.zero, .07, Paint()..color = FinPalette.shell);
      c.restore();
    case FinBuilding.generator:
      c.drawCircle(center, .24, Paint()..color = const Color(0xFF2E5E57));
      c.drawCircle(
        center,
        .17,
        Paint()..color = accent.withValues(alpha: .35 + glow * .65),
      );
      c.drawCircle(
        center.translate(-.05, -.06),
        .05,
        Paint()..color = Colors.white.withValues(alpha: .7),
      );
    case FinBuilding.storage:
      final lid = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = .05;
      c.drawRRect(
        RRect.fromRectAndRadius(cell.deflate(.22), const Radius.circular(.06)),
        lid,
      );
      c.drawLine(center.translate(-.28, 0), center.translate(.28, 0), lid);
    case FinBuilding.lab:
      c.drawArc(
        Rect.fromCenter(
          center: center.translate(0, .1),
          width: .56,
          height: .6,
        ),
        math.pi,
        math.pi,
        true,
        Paint()..color = accent.withValues(alpha: .4 + glow * .5),
      );
      c.drawCircle(
        center.translate(0, -.02),
        .06,
        Paint()..color = Colors.white,
      );
    case FinBuilding.belt:
    case FinBuilding.fastBelt:
      break;
  }
  // The side it hands things out of.
  if (m.kind != FinBuilding.storage && m.kind != FinBuilding.generator) {
    final f = Offset(FinDir.dx[m.dir].toDouble(), FinDir.dy[m.dir].toDouble());
    final tip = center + f * .44;
    final side = Offset(-f.dy, f.dx) * .09;
    c.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - f.dx * .12 + side.dx, tip.dy - f.dy * .12 + side.dy)
        ..lineTo(tip.dx - f.dx * .12 - side.dx, tip.dy - f.dy * .12 - side.dy)
        ..close(),
      Paint()..color = FinPalette.plum.withValues(alpha: .55),
    );
  }
}

/// A belt cell: a soft track with chevrons moving at the belt's speed.
/// [from] is the side items enter from (equal to dir's back for straight).
void paintBelt(Canvas c, FinMachine b, int from, double t) {
  final cell = Rect.fromLTWH(b.x.toDouble(), b.y.toDouble(), 1, 1);
  final fast = b.kind == FinBuilding.fastBelt;
  final track = RRect.fromRectAndRadius(
    cell.deflate(.1),
    const Radius.circular(.14),
  );
  c.drawRRect(
    track.shift(const Offset(0, .04)),
    Paint()..color = Colors.black.withValues(alpha: .14),
  );
  c.drawRRect(
    track,
    Paint()..color = fast ? const Color(0xFF3E6F73) : FinPalette.belt,
  );
  final speed =
      (FinRules.beltSpeed[b.kind]! * FinRules.ticksPerSecond) /
      FinRules.beltLength;
  final phase = (t * speed) % .5;
  final chevron = Paint()
    ..color = (fast ? FinPalette.teal : FinPalette.beltLight).withValues(
      alpha: .8,
    )
    ..style = PaintingStyle.stroke
    ..strokeWidth = .05
    ..strokeCap = StrokeCap.round;
  for (var k = 0; k < 2; k++) {
    final s = (phase + k * .5);
    final p = beltPoint(b, from, s.clamp(0, 1));
    final dir = beltPoint(b, from, (s + .01).clamp(0, 1)) - p;
    final n = dir.distance == 0 ? const Offset(1, 0) : dir / dir.distance;
    final side = Offset(-n.dy, n.dx) * .14;
    c.drawPath(
      Path()
        ..moveTo(p.dx - n.dx * .08 + side.dx, p.dy - n.dy * .08 + side.dy)
        ..lineTo(p.dx + n.dx * .04, p.dy + n.dy * .04)
        ..lineTo(p.dx - n.dx * .08 - side.dx, p.dy - n.dy * .08 - side.dy),
      chevron,
    );
  }
}

/// Where along a belt (0 entry .. 1 exit) a point lies, in world units.
/// A belt fed from a side bends round a quarter circle.
Offset beltPoint(FinMachine b, int from, double s) {
  final cx = b.x + .5, cy = b.y + .5;
  final out = Offset(FinDir.dx[b.dir].toDouble(), FinDir.dy[b.dir].toDouble());
  final back = FinDir.opposite(b.dir);
  if (from == back) {
    return Offset(cx, cy) + out * (s - .5);
  }
  final inn = Offset(FinDir.dx[from].toDouble(), FinDir.dy[from].toDouble());
  // Quarter circle from the entry edge to the exit edge, centred on the
  // corner they share.
  final corner = Offset(cx, cy) + (inn + out) * .5;
  final a0 = math.atan2(-out.dy, -out.dx);
  final a1 = math.atan2(-inn.dy, -inn.dx);
  var da = a1 - a0;
  while (da > math.pi) {
    da -= 2 * math.pi;
  }
  while (da < -math.pi) {
    da += 2 * math.pi;
  }
  final a = a0 + da * s; // s = 0 at the entry edge, 1 at the exit
  return corner + Offset(math.cos(a), math.sin(a)) * .5;
}
