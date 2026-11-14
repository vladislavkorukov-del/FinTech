import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_shapes.dart';

/// What a city is known for, drawn on one of its cells: a factory with a
/// chimney (industry), a headframe and heap (mining), a sawmill with
/// stacked logs (forestry), a grain elevator (farming), market stalls
/// (trade). Bigger cities draw it bigger.
void paintCityAccent(
  Canvas c,
  MagSpecialization s,
  double x,
  double y,
  int level,
) {
  final k = 1 + .12 * (level - MagTowns.cityLevel);
  switch (s) {
    case MagSpecialization.industry:
      MagShapes.box(
        c,
        x: x + .5,
        y: y + .55,
        length: .7,
        width: .55,
        h: 12 * k,
        color: const Color(0xFFB9A79A),
      );
      MagShapes.cylinder(
        c,
        x: x + .25,
        y: y + .25,
        r: .08,
        h: 34 * k,
        color: const Color(0xFF9C4A3A),
      );
    case MagSpecialization.mining:
      MagShapes.cylinder(
        c,
        x: x + .65,
        y: y + .65,
        r: .24,
        h: 5 * k,
        color: const Color(0xFF4A4F55),
        dome: true,
      );
      for (final (dx, dy) in [(.2, .2), (.45, .2), (.2, .45), (.45, .45)]) {
        MagShapes.box(
          c,
          x: x + dx,
          y: y + dy,
          length: .05,
          width: .05,
          h: 22 * k,
          color: const Color(0xFF5B636B),
          outline: false,
        );
      }
      MagShapes.box(
        c,
        x: x + .33,
        y: y + .33,
        length: .32,
        width: .32,
        z0: 20 * k,
        h: 3,
        color: const Color(0xFFC0473F),
      );
    case MagSpecialization.forestry:
      MagShapes.box(
        c,
        x: x + .5,
        y: y + .4,
        length: .7,
        width: .45,
        h: 9 * k,
        color: const Color(0xFFB98A5A),
      );
      MagShapes.roof(
        c,
        x: x + .5,
        y: y + .4,
        length: .76,
        width: .5,
        z0: 9 * k,
        h: 5,
        color: const Color(0xFF5E6B5C),
        ridge: .5,
      );
      for (var n = 0; n < 3; n++) {
        MagShapes.box(
          c,
          x: x + .55,
          y: y + .82,
          length: .5,
          width: .18,
          z0: 2.4 * n,
          h: 2.4,
          color: const Color(0xFF9A6A3A),
          outline: false,
        );
      }
    case MagSpecialization.farming:
      for (final dx in [.3, .62]) {
        MagShapes.cylinder(
          c,
          x: x + dx,
          y: y + .45,
          r: .14,
          h: 24 * k,
          color: const Color(0xFFE3DED3),
          dome: true,
        );
      }
      MagShapes.box(
        c,
        x: x + .5,
        y: y + .78,
        length: .6,
        width: .25,
        h: 8,
        color: const Color(0xFFC0473F),
      );
    case MagSpecialization.trade:
      for (final (dx, col) in [
        (.28, const Color(0xFFE86A5A)),
        (.55, const Color(0xFF4FB3C9)),
        (.82, const Color(0xFFE8C14A)),
      ]) {
        MagShapes.box(
          c,
          x: x + dx,
          y: y + .55,
          length: .22,
          width: .3,
          h: 5,
          color: const Color(0xFFF3E6CF),
        );
        MagShapes.roof(
          c,
          x: x + dx,
          y: y + .55,
          length: .26,
          width: .34,
          z0: 5,
          h: 4,
          color: col,
          ridge: .1,
        );
      }
  }
}
