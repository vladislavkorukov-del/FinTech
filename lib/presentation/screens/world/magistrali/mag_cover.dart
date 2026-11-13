import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_art.dart';
import 'mag_iso.dart';
import 'mag_shapes.dart';

/// The game card's picture: a small isometric scene drawn with the game's
/// own shapes (a road, a truck, a plant and a town), fading into the dark
/// left side where the title sits.
class MagistraliCover extends StatelessWidget {
  const MagistraliCover({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _Cover());
}

class _Cover extends CustomPainter {
  const _Cover();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width * .66, size.height * .1);
    canvas.scale(size.height / 150);
    canvas.save();
    canvas.transform(MagIso.ground);
    for (var y = -2; y < 6; y++) {
      for (var x = -1; x < 7; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.02, 1.02),
          Paint()
            ..color = (x + y).isEven
                ? const Color(0xFF9FCF72)
                : const Color(0xFF94C869),
        );
      }
    }
    for (var x = -1; x < 7; x++) {
      paintRoad(canvas, MagRoad.asphalt, 0xA, x, 2, false);
    }
    canvas.restore();
    MagShapes.box(
      canvas,
      x: 1.2,
      y: .6,
      length: 1.4,
      width: 1.1,
      h: 18,
      color: const Color(0xFFF2F1EC),
    );
    MagShapes.box(
      canvas,
      x: 1.2,
      y: .6,
      length: 1.42,
      width: 1.12,
      z0: 12,
      h: 3,
      color: MagPalette.mint,
      outline: false,
    );
    MagShapes.cylinder(
      canvas,
      x: .55,
      y: .2,
      r: .12,
      h: 34,
      color: const Color(0xFFC9CDD0),
    );
    for (final (bx, by, h) in [
      (4.0, .3, 46.0),
      (4.8, .9, 30.0),
      (3.6, 1.0, 22.0),
    ]) {
      MagShapes.box(
        canvas,
        x: bx,
        y: by,
        length: .6,
        width: .6,
        h: h,
        color: const Color(0xFFB9C7D6),
      );
    }
    paintTruck(
      canvas,
      2.6,
      2.5,
      1,
      MagRules.trucks[1],
      MagPalette.cargo(MagCargo.grain),
    );
    paintTruck(canvas, .4, 2.5, 3, MagRules.trucks.first, null);
    canvas.restore();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xF216302C), Color(0x0016302C)],
          stops: [.3, .7],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_Cover old) => false;
}
